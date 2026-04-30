package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"math/big"
	"net"
	"sync"
	"time"

	"github.com/pion/datachannel"
	"github.com/pion/dtls/v3"
	"github.com/pion/ice/v4"
	"github.com/pion/logging"
	"github.com/pion/rtcp"
	"github.com/pion/sctp"
	"github.com/pion/srtp/v3"
)

// ParticipantConfig holds the client's join parameters extracted from the join payload.
type ParticipantConfig struct {
	AudioSSRC   uint32
	Ufrag       string
	Pwd         string
	Fingerprint string // SHA-256, colon-separated uppercase hex (e.g., "AB:CD:EF:...")
}

// Participant holds the per-participant transport stack: ICE → DTLS → SRTP + SCTP/DataChannel.
type Participant struct {
	ID        int
	AudioSSRC uint32

	iceAgent *ice.Agent
	iceConn  *ice.Conn

	demux    *PacketDemux
	dtlsConn *dtls.Conn

	srtpSession *srtp.SessionSRTP
	srtpWriter  *srtp.WriteStreamSRTP
	srtpProfile srtp.ProtectionProfile
	srtpKeys    srtp.SessionKeys // saved for creating SRTCP contexts

	// Separate SRTCP contexts for manual RTCP decrypt/encrypt.
	// These are independent from the SessionSRTP used for RTP.
	srtcpRemoteCtx *srtp.Context // decrypt SRTCP received from this participant
	srtcpLocalCtx  *srtp.Context // encrypt SRTCP sent to this participant
	srtcpMu        sync.Mutex    // protects srtcpLocalCtx (single-writer)

	sctpAssoc   *sctp.Association
	dataChannel *datachannel.DataChannel

	tlsCert     tls.Certificate
	fingerprint string // SHA-256, colon-separated uppercase hex
	localUfrag  string
	localPwd    string

	loggerFactory logging.LoggerFactory
	log           logging.LeveledLogger

	// Video layer selection: receiver requests which layer to receive from each sender.
	videoLayerMu    sync.RWMutex
	requestedLayers map[int]int // senderID -> layer index

	// Bandwidth estimation from REMB.
	bwEstimator *BandwidthEstimator

	// Selected layers: what the SFU actually forwards (set by LayerSelector).
	selectedLayerMu sync.RWMutex
	selectedLayers  map[int]int // senderID -> layer index
	onColibriMessage func(participantID int, msg string) // set before Connect(), read from acceptDataChannel goroutine

	// RTCP feedback callback: called when PLI or FIR is received from this participant.
	// mediaSSRC is the SSRC the receiver wants a keyframe for.
	onRTCPFeedback func(participantID int, mediaSSRC uint32, isFIR bool)

	// Network simulation (delay/jitter/loss/bandwidth cap per direction).
	ingressSim *NetworkSimulator
	egressSim  *NetworkSimulator

	closed chan struct{}
	once   sync.Once
}

// NewParticipant creates a new Participant with an ICE agent and self-signed certificate.
// It does NOT start ICE gathering or connection — call GatherCandidates() and Connect() for that.
func NewParticipant(id int, config ParticipantConfig, loggerFactory logging.LoggerFactory) (*Participant, error) {
	log := loggerFactory.NewLogger(fmt.Sprintf("participant-%d", id))

	// Generate self-signed ECDSA P-256 certificate.
	privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate ECDSA key: %w", err)
	}

	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
	}
	certDER, err := x509.CreateCertificate(rand.Reader, template, template, &privKey.PublicKey, privKey)
	if err != nil {
		return nil, fmt.Errorf("create certificate: %w", err)
	}

	tlsCert := tls.Certificate{
		Certificate: [][]byte{certDER},
		PrivateKey:  privKey,
	}

	// Compute SHA-256 fingerprint of the DER certificate.
	hash := sha256.Sum256(certDER)
	fingerprint := formatFingerprint(hash[:])

	// Create ICE agent — UDP, host candidates, ICE-lite.
	// The tgcalls GroupNetworkManager hardcodes ICEROLE_CONTROLLED for the client,
	// so the SFU must be the controlling side (use Dial, not Accept).
	// ICE-lite: the SFU passively accepts incoming connectivity checks.
	// No remote candidates needed: when the client's STUN binding requests arrive,
	// pion creates peer-reflexive candidates automatically.
	agent, err := ice.NewAgent(&ice.AgentConfig{
		NetworkTypes:    []ice.NetworkType{ice.NetworkTypeUDP4},
		CandidateTypes:  []ice.CandidateType{ice.CandidateTypeHost},
		Lite:            true,
		IncludeLoopback: true,
		IPFilter: func(ip net.IP) bool {
			return true // accept all interfaces, including loopback
		},
		LoggerFactory: loggerFactory,
	})
	if err != nil {
		return nil, fmt.Errorf("create ICE agent: %w", err)
	}

	localUfrag, localPwd, err := agent.GetLocalUserCredentials()
	if err != nil {
		_ = agent.Close()
		return nil, fmt.Errorf("get local credentials: %w", err)
	}

	log.Infof("Created participant %d (SSRC=%d, ufrag=%s, fingerprint=%s)", id, config.AudioSSRC, localUfrag, fingerprint)

	return &Participant{
		ID:              id,
		AudioSSRC:       config.AudioSSRC,
		iceAgent:        agent,
		tlsCert:         tlsCert,
		fingerprint:     fingerprint,
		localUfrag:      localUfrag,
		localPwd:        localPwd,
		loggerFactory:   loggerFactory,
		log:             log,
		requestedLayers: make(map[int]int),
		bwEstimator:     &BandwidthEstimator{},
		selectedLayers:  make(map[int]int),
		ingressSim:      NewNetworkSimulator(),
		egressSim:       NewNetworkSimulator(),
		closed:          make(chan struct{}),
	}, nil
}

// Fingerprint returns the SHA-256 fingerprint of the participant's DTLS certificate.
func (p *Participant) Fingerprint() string {
	return p.fingerprint
}

// LocalUfrag returns the local ICE username fragment.
func (p *Participant) LocalUfrag() string {
	return p.localUfrag
}

// LocalPwd returns the local ICE password.
func (p *Participant) LocalPwd() string {
	return p.localPwd
}

// GatherCandidates triggers ICE gathering and waits for completion.
// Returns the gathered ICE candidates.
func (p *Participant) GatherCandidates() ([]ice.Candidate, error) {
	var (
		candidates []ice.Candidate
		mu         sync.Mutex
		done       = make(chan struct{})
	)

	if err := p.iceAgent.OnCandidate(func(c ice.Candidate) {
		if c == nil {
			// nil candidate signals gathering complete.
			close(done)
			return
		}
		mu.Lock()
		candidates = append(candidates, c)
		mu.Unlock()
	}); err != nil {
		return nil, fmt.Errorf("set OnCandidate: %w", err)
	}

	if err := p.iceAgent.GatherCandidates(); err != nil {
		return nil, fmt.Errorf("gather candidates: %w", err)
	}

	<-done

	mu.Lock()
	defer mu.Unlock()
	p.log.Infof("Gathered %d ICE candidates", len(candidates))
	return candidates, nil
}

// Connect establishes the full transport stack: ICE → DTLS → SRTP + SCTP.
// The SFU is DTLS client (active). tgcalls GroupNetworkManager hardcodes SSL_SERVER.
//
// iceControlling selects the ICE role:
//   - true  (Dial):   SFU is controlling. Required for tgcalls GroupNetworkManager which
//     hardcodes ICEROLE_CONTROLLED (non-standard).
//   - false (Accept): SFU is controlled (standard for ICE-lite). Required for PeerConnection
//     clients that follow RFC 8445 (full agent = controlling when remote is ice-lite).
func (p *Participant) Connect(ctx context.Context, remoteUfrag, remotePwd string, iceControlling bool) error {
	// 1. ICE connection.
	var iceConn *ice.Conn
	var err error
	if iceControlling {
		iceConn, err = p.iceAgent.Dial(ctx, remoteUfrag, remotePwd)
	} else {
		iceConn, err = p.iceAgent.Accept(ctx, remoteUfrag, remotePwd)
	}
	if err != nil {
		return fmt.Errorf("ICE dial: %w", err)
	}
	p.iceConn = iceConn
	p.log.Infof("ICE connected")

	// 2. Demux: split DTLS and SRTP traffic.
	p.demux = NewPacketDemux(iceConn, fmt.Sprintf("p%d", p.ID))

	// 3. DTLS: client-side handshake over the DTLS endpoint.
	// tgcalls GroupNetworkManager hardcodes SetDtlsRole(SSL_SERVER), so the SFU must be the DTLS client.
	dtlsEndpoint := p.demux.DTLSEndpoint()
	remoteAddr := dtlsEndpoint.RemoteAddr()
	packetConn := WrapAsPacketConn(dtlsEndpoint)

	dtlsConn, err := dtls.Client(packetConn, remoteAddr, &dtls.Config{
		Certificates: []tls.Certificate{p.tlsCert},
		// Offer GCM profiles matching tgcalls GroupNetworkManager::getDefaulCryptoOptions()
		// which enables enable_gcm_crypto_suites=true and disables AES-128-CM-SHA1-80.
		SRTPProtectionProfiles: []dtls.SRTPProtectionProfile{
			dtls.SRTP_AEAD_AES_256_GCM,
			dtls.SRTP_AEAD_AES_128_GCM,
		},
		ExtendedMasterSecret: dtls.RequireExtendedMasterSecret,
		InsecureSkipVerify:   true, // tgcalls verifies fingerprint out-of-band; we skip TLS chain verification
		LoggerFactory:        p.loggerFactory,
	})
	if err != nil {
		p.demux.Close()
		return fmt.Errorf("DTLS create: %w", err)
	}
	p.dtlsConn = dtlsConn

	// dtls.Client() is lazy; explicitly run the handshake before accessing ConnectionState.
	if err := dtlsConn.HandshakeContext(ctx); err != nil {
		p.demux.Close()
		return fmt.Errorf("DTLS handshake: %w", err)
	}
	p.log.Infof("DTLS connected")

	// 4. Extract SRTP keying material from DTLS.
	state, ok := dtlsConn.ConnectionState()
	if !ok {
		return fmt.Errorf("DTLS connection state not available")
	}

	// Map the negotiated DTLS-SRTP protection profile to a pion/srtp ProtectionProfile.
	negotiatedProfile, profileOk := dtlsConn.SelectedSRTPProtectionProfile()
	if !profileOk {
		p.demux.Close()
		return fmt.Errorf("no SRTP protection profile negotiated")
	}
	var srtpProfile srtp.ProtectionProfile
	switch negotiatedProfile {
	case dtls.SRTP_AEAD_AES_256_GCM:
		srtpProfile = srtp.ProtectionProfileAeadAes256Gcm
	case dtls.SRTP_AEAD_AES_128_GCM:
		srtpProfile = srtp.ProtectionProfileAeadAes128Gcm
	case dtls.SRTP_AES128_CM_HMAC_SHA1_80:
		srtpProfile = srtp.ProtectionProfileAes128CmHmacSha1_80
	case dtls.SRTP_AES128_CM_HMAC_SHA1_32:
		srtpProfile = srtp.ProtectionProfileAes128CmHmacSha1_32
	default:
		p.demux.Close()
		return fmt.Errorf("unsupported SRTP protection profile: 0x%04x", negotiatedProfile)
	}
	p.log.Infof("Negotiated SRTP profile: 0x%04x", negotiatedProfile)

	srtpConfig := &srtp.Config{
		Profile: srtpProfile,
	}
	// SFU is DTLS client → isClient=true
	if err := srtpConfig.ExtractSessionKeysFromDTLS(&state, true); err != nil {
		return fmt.Errorf("extract SRTP keys: %w", err)
	}

	// Save keys and profile for creating SRTCP contexts.
	p.srtpProfile = srtpProfile
	p.srtpKeys = srtpConfig.Keys

	// 5. SRTP session over the SRTP endpoint (RTP only — RTCP is handled separately).
	srtpEndpoint := p.demux.SRTPEndpoint()
	srtpSession, err := srtp.NewSessionSRTP(srtpEndpoint, srtpConfig)
	if err != nil {
		return fmt.Errorf("create SRTP session: %w", err)
	}
	p.srtpSession = srtpSession

	srtpWriter, err := srtpSession.OpenWriteStream()
	if err != nil {
		return fmt.Errorf("open SRTP write stream: %w", err)
	}
	p.srtpWriter = srtpWriter
	p.log.Infof("SRTP session established")

	// 5b. Create separate SRTCP contexts for manual RTCP handling.
	// Remote context: decrypt SRTCP received from this participant (their local = our remote).
	p.srtcpRemoteCtx, err = srtp.CreateContext(
		p.srtpKeys.RemoteMasterKey, p.srtpKeys.RemoteMasterSalt, p.srtpProfile,
	)
	if err != nil {
		return fmt.Errorf("create SRTCP remote context: %w", err)
	}
	// Local context: encrypt SRTCP we send to this participant (our local keys).
	p.srtcpLocalCtx, err = srtp.CreateContext(
		p.srtpKeys.LocalMasterKey, p.srtpKeys.LocalMasterSalt, p.srtpProfile,
	)
	if err != nil {
		return fmt.Errorf("create SRTCP local context: %w", err)
	}
	p.log.Infof("SRTCP contexts created")

	// 5c. Start RTCP read loop.
	go p.readRTCPLoop()

	// 6. SCTP association over DTLS.
	sctpAssoc, err := sctp.Server(sctp.Config{
		NetConn:       dtlsConn,
		LoggerFactory: p.loggerFactory,
	})
	if err != nil {
		return fmt.Errorf("create SCTP association: %w", err)
	}
	p.sctpAssoc = sctpAssoc
	p.log.Infof("SCTP association established")

	// 7. Start goroutine to accept data channels.
	go p.acceptDataChannel()

	return nil
}

// acceptDataChannel waits for the client to open a data channel and reads Colibri messages.
func (p *Participant) acceptDataChannel() {
	dc, err := datachannel.Accept(p.sctpAssoc, &datachannel.Config{
		LoggerFactory: p.loggerFactory,
	})
	if err != nil {
		select {
		case <-p.closed:
			return // Expected during shutdown.
		default:
			p.log.Warnf("Accept data channel: %v", err)
			return
		}
	}
	p.dataChannel = dc
	p.log.Infof("Data channel accepted")

	buf := make([]byte, 4096)
	for {
		n, isString, err := dc.ReadDataChannel(buf)
		if err != nil {
			select {
			case <-p.closed:
				return
			default:
				p.log.Debugf("Data channel read error: %v", err)
				return
			}
		}
		if isString {
			msg := string(buf[:n])
			p.log.Debugf("Colibri message: %s", msg)
			if p.onColibriMessage != nil {
				p.onColibriMessage(p.ID, msg)
			}
		} else {
			p.log.Debugf("Data channel binary message (%d bytes)", n)
		}
	}
}

// SetColibriCallback sets the callback for incoming Colibri data channel messages.
func (p *Participant) SetColibriCallback(cb func(participantID int, msg string)) {
	p.onColibriMessage = cb
}

// SetRTCPFeedbackCallback sets the callback for PLI/FIR RTCP feedback from this participant.
func (p *Participant) SetRTCPFeedbackCallback(cb func(participantID int, mediaSSRC uint32, isFIR bool)) {
	p.onRTCPFeedback = cb
}

// readRTCPLoop reads encrypted SRTCP packets from the demux RTCP channel,
// decrypts them, parses for PLI/FIR, and invokes the feedback callback.
func (p *Participant) readRTCPLoop() {
	rtcpCh := p.demux.RTCPChannel()
	decryptBuf := make([]byte, 8192)
	pktCount := 0

	for {
		select {
		case <-p.closed:
			return
		case encrypted, ok := <-rtcpCh:
			if !ok {
				return
			}

			// Decrypt SRTCP.
			decrypted, err := p.srtcpRemoteCtx.DecryptRTCP(decryptBuf[:0], encrypted, nil)
			if err != nil {
				pktCount++
				if pktCount <= 5 {
					p.log.Debugf("SRTCP decrypt error: %v", err)
				}
				continue
			}

			// Parse RTCP compound packet.
			packets, err := rtcp.Unmarshal(decrypted)
			if err != nil {
				p.log.Debugf("RTCP unmarshal error: %v", err)
				continue
			}

			for _, pkt := range packets {
				switch fb := pkt.(type) {
				case *rtcp.PictureLossIndication:
					p.log.Infof("Received PLI from participant %d for MediaSSRC=%d", p.ID, fb.MediaSSRC)
					if p.onRTCPFeedback != nil {
						p.onRTCPFeedback(p.ID, fb.MediaSSRC, false)
					}
				case *rtcp.FullIntraRequest:
					for _, entry := range fb.FIR {
						p.log.Infof("Received FIR from participant %d for SSRC=%d", p.ID, entry.SSRC)
						if p.onRTCPFeedback != nil {
							p.onRTCPFeedback(p.ID, entry.SSRC, true)
						}
					}
				case *rtcp.ReceiverEstimatedMaximumBitrate:
					bps := float64(fb.Bitrate)
					p.bwEstimator.OnREMB(bps)
					p.log.Debugf("REMB from participant %d: %.0f bps (smoothed=%.0f, effective=%.0f)",
						p.ID, bps, p.bwEstimator.SmoothedBps(), p.bwEstimator.EffectiveBps())
				}
			}
		}
	}
}

// WriteRTCP sends a plaintext RTCP packet to this participant, encrypting it with
// the local SRTCP context and writing directly to the ICE connection.
func (p *Participant) WriteRTCP(data []byte) error {
	if p.srtcpLocalCtx == nil || p.iceConn == nil {
		return fmt.Errorf("SRTCP context or ICE conn not established")
	}
	if p.egressSim.IsPassthrough() {
		return p.writeRTCPDirect(data)
	}
	p.egressSim.Send(data, func(delayed []byte) {
		p.writeRTCPDirect(delayed)
	})
	return nil
}

func (p *Participant) writeRTCPDirect(data []byte) error {
	p.srtcpMu.Lock()
	encrypted, err := p.srtcpLocalCtx.EncryptRTCP(nil, data, nil)
	p.srtcpMu.Unlock()
	if err != nil {
		return fmt.Errorf("encrypt SRTCP: %w", err)
	}
	_, err = p.iceConn.Write(encrypted)
	return err
}

// SetRequestedLayer sets the video layer this receiver wants from a given sender.
func (p *Participant) SetRequestedLayer(senderID int, layer int) {
	p.videoLayerMu.Lock()
	p.requestedLayers[senderID] = layer
	p.videoLayerMu.Unlock()
}

// GetRequestedLayer returns the video layer this receiver wants from a given sender.
// Returns -1 if no layer is requested (meaning: don't forward video from this sender).
func (p *Participant) GetRequestedLayer(senderID int) int {
	p.videoLayerMu.RLock()
	defer p.videoLayerMu.RUnlock()
	if layer, ok := p.requestedLayers[senderID]; ok {
		return layer
	}
	return -1
}

// SetSelectedLayer sets the video layer the SFU actually forwards from a given sender to this receiver.
func (p *Participant) SetSelectedLayer(senderID int, layer int) {
	p.selectedLayerMu.Lock()
	p.selectedLayers[senderID] = layer
	p.selectedLayerMu.Unlock()
}

// GetSelectedLayer returns the video layer the SFU forwards from a given sender to this receiver.
// Returns -1 if no layer is selected (don't forward).
func (p *Participant) GetSelectedLayer(senderID int) int {
	p.selectedLayerMu.RLock()
	defer p.selectedLayerMu.RUnlock()
	if layer, ok := p.selectedLayers[senderID]; ok {
		return layer
	}
	return -1
}

// SendText sends a UTF-8 string message over the data channel.
// Returns an error if the data channel is not yet established.
func (p *Participant) SendText(msg string) error {
	dc := p.dataChannel
	if dc == nil {
		return fmt.Errorf("data channel not established")
	}
	_, err := dc.WriteDataChannel([]byte(msg), true)
	return err
}

// WriteRTP sends an encrypted RTP packet to this participant via the SRTP write stream.
func (p *Participant) WriteRTP(pkt []byte) (int, error) {
	if p.srtpWriter == nil {
		return 0, fmt.Errorf("SRTP session not established")
	}
	if p.egressSim.IsPassthrough() {
		return p.srtpWriter.Write(pkt)
	}
	var n int
	var writeErr error
	p.egressSim.Send(pkt, func(delayed []byte) {
		n, writeErr = p.srtpWriter.Write(delayed)
	})
	return n, writeErr
}

// AcceptStream blocks until a new SRTP read stream appears (new SSRC from client).
// Returns the read stream and its SSRC.
func (p *Participant) AcceptStream() (*srtp.ReadStreamSRTP, uint32, error) {
	if p.srtpSession == nil {
		return nil, 0, fmt.Errorf("SRTP session not established")
	}
	return p.srtpSession.AcceptStream()
}

// Close tears down all transport layers in order.
func (p *Participant) Close() error {
	var firstErr error
	p.once.Do(func() {
		close(p.closed)

		if p.ingressSim != nil {
			p.ingressSim.Close()
		}
		if p.egressSim != nil {
			p.egressSim.Close()
		}

		if p.dataChannel != nil {
			if err := p.dataChannel.Close(); err != nil && firstErr == nil {
				firstErr = err
			}
		}
		if p.sctpAssoc != nil {
			if err := p.sctpAssoc.Close(); err != nil && firstErr == nil {
				firstErr = err
			}
		}
		if p.srtpSession != nil {
			if err := p.srtpSession.Close(); err != nil && firstErr == nil {
				firstErr = err
			}
		}
		if p.dtlsConn != nil {
			if err := p.dtlsConn.Close(); err != nil && firstErr == nil {
				firstErr = err
			}
		}
		if p.demux != nil {
			if err := p.demux.Close(); err != nil && firstErr == nil {
				firstErr = err
			}
		}
		if p.iceConn != nil {
			if err := p.iceConn.Close(); err != nil && firstErr == nil {
				firstErr = err
			}
		}
		if p.iceAgent != nil {
			if err := p.iceAgent.Close(); err != nil && firstErr == nil {
				firstErr = err
			}
		}

		p.log.Infof("Participant %d closed", p.ID)
	})
	return firstErr
}

// formatFingerprint converts a hash byte slice to colon-separated uppercase hex.
func formatFingerprint(hash []byte) string {
	result := make([]byte, 0, len(hash)*3-1)
	for i, b := range hash {
		if i > 0 {
			result = append(result, ':')
		}
		result = append(result, fmt.Sprintf("%02X", b)...)
	}
	return string(result)
}
