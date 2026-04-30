package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	"github.com/pion/ice/v4"
	"github.com/pion/logging"
	"github.com/pion/rtcp"
)

// --- JSON types for tgcalls join protocol ---

type joinPayload struct {
	SSRC         int32              `json:"ssrc"` // signed in JSON, cast to uint32
	Ufrag        string             `json:"ufrag"`
	Pwd          string             `json:"pwd"`
	Fingerprints []fingerprintJSON  `json:"fingerprints"`
	SSRCGroups   []ssrcGroupJSON    `json:"ssrc-groups"`
}

type ssrcGroupJSON struct {
	Semantics string  `json:"semantics"` // "SIM" or "FID"
	Sources   []int32 `json:"sources"`   // tgcalls serializes as "sources", not "ssrcs"
}

// ssrcInfo identifies the owner and type of an SSRC in the registry.
type ssrcInfo struct {
	participantID int
	kind          string // "audio", "video", "video-rtx"
	layer         int    // -1 for audio, 0/1/2 for video simulcast layers
}

// SimulcastLayer holds the primary and RTX SSRCs for one simulcast layer.
type SimulcastLayer struct {
	SSRC    uint32
	FidSSRC uint32
}

type fingerprintJSON struct {
	Hash        string `json:"hash"`
	Fingerprint string `json:"fingerprint"`
	Setup       string `json:"setup"`
}

type joinResponse struct {
	Transport transportJSON     `json:"transport"`
	Video     *videoResponseJSON `json:"video,omitempty"`
}

type videoResponseJSON struct {
	Endpoint          string                `json:"endpoint"`
	ServerSSRCs       []videoServerSSRC     `json:"server_ssrcs,omitempty"`
	PayloadTypes      []videoPayloadTypeJSON `json:"payload-types"`
	RTPHdrexts        []rtpHdrextJSON       `json:"rtp-hdrexts"`
}

type videoServerSSRC struct {
	SSRC   int32           `json:"ssrc"`
	Groups []ssrcGroupJSON `json:"ssrc-groups,omitempty"`
}

type videoPayloadTypeJSON struct {
	ID         int                  `json:"id"`
	Name       string               `json:"name"`
	Clockrate  int                  `json:"clockrate"`
	Channels   int                  `json:"channels,omitempty"`
	Parameters map[string]string    `json:"parameters,omitempty"`
	Feedback   []rtcpFeedbackJSON   `json:"rtcp-fbs,omitempty"`
}

type rtcpFeedbackJSON struct {
	Type    string `json:"type"`
	Subtype string `json:"subtype,omitempty"`
}

type rtpHdrextJSON struct {
	ID  int    `json:"id"`
	URI string `json:"uri"`
}

type transportJSON struct {
	Ufrag        string            `json:"ufrag"`
	Pwd          string            `json:"pwd"`
	Fingerprints []fingerprintJSON `json:"fingerprints"`
	Candidates   []candidateJSON   `json:"candidates"`
}

type candidateJSON struct {
	Port       string `json:"port"`
	Protocol   string `json:"protocol"`
	Network    string `json:"network"`
	Generation string `json:"generation"`
	ID         string `json:"id"`
	Component  string `json:"component"`
	Foundation string `json:"foundation"`
	Priority   string `json:"priority"`
	IP         string `json:"ip"`
	Type       string `json:"type"`
}

// --- SFU ---

type SFU struct {
	mu            sync.RWMutex
	participants  map[int]*Participant
	ssrcRegistry  map[uint32]ssrcInfo
	videoSSRCs     map[int][]SimulcastLayer   // participantID -> simulcast layers
	rtxBuffers     map[int]*RtxRingBuffer    // senderID -> RTX ring buffer
	layerSelectors map[[2]int]*LayerSelector // [receiverID, senderID] -> selector
	maxActiveLayer map[int]int              // senderID -> highest layer with traffic
	twccGenerators map[int]*TransportCCGenerator // senderID -> transport-cc generator
	loggerFactory  logging.LoggerFactory
	log           logging.LeveledLogger
	ctx           context.Context
	cancel        context.CancelFunc
}

func NewSFU() *SFU {
	lf := logging.NewDefaultLoggerFactory()
	lf.DefaultLogLevel = logging.LogLevelDebug
	ctx, cancel := context.WithCancel(context.Background())
	return &SFU{
		participants:  make(map[int]*Participant),
		ssrcRegistry:  make(map[uint32]ssrcInfo),
		videoSSRCs:     make(map[int][]SimulcastLayer),
		rtxBuffers:     make(map[int]*RtxRingBuffer),
		layerSelectors: make(map[[2]int]*LayerSelector),
		maxActiveLayer: make(map[int]int),
		twccGenerators: make(map[int]*TransportCCGenerator),
		loggerFactory:  lf,
		log:           lf.NewLogger("sfu"),
		ctx:           ctx,
		cancel:        cancel,
	}
}

// Join processes a participant's join payload and returns the SFU's join response JSON.
// iceControlling: true for CustomImpl clients (which hardcode CONTROLLED role),
// false for PeerConnection clients (standard ICE: full agent is controlling when remote is ice-lite).
func (s *SFU) Join(participantID int, joinPayloadJSON string, iceControlling bool) (string, error) {
	// 1. Parse join payload.
	var payload joinPayload
	if err := json.Unmarshal([]byte(joinPayloadJSON), &payload); err != nil {
		return "", fmt.Errorf("parse join payload: %w", err)
	}

	// 2. Extract audio SSRC (signed int32 -> uint32).
	audioSSRC := uint32(payload.SSRC)

	// 3. Extract fingerprint from payload (use first sha-256 fingerprint).
	var remoteFingerprint string
	for _, fp := range payload.Fingerprints {
		if fp.Hash == "sha-256" {
			remoteFingerprint = fp.Fingerprint
			break
		}
	}
	if remoteFingerprint == "" && len(payload.Fingerprints) > 0 {
		remoteFingerprint = payload.Fingerprints[0].Fingerprint
	}

	// 4. Parse video ssrc-groups into SimulcastLayers.
	var simSSRCs []uint32 // SIM group: primary SSRCs per layer
	fidMap := make(map[uint32]uint32) // primary SSRC -> RTX SSRC
	for _, g := range payload.SSRCGroups {
		switch g.Semantics {
		case "SIM":
			for _, v := range g.Sources {
				simSSRCs = append(simSSRCs, uint32(v))
			}
		case "FID":
			if len(g.Sources) == 2 {
				fidMap[uint32(g.Sources[0])] = uint32(g.Sources[1])
			}
		}
	}

	var videoLayers []SimulcastLayer
	for _, primary := range simSSRCs {
		layer := SimulcastLayer{SSRC: primary}
		if rtx, ok := fidMap[primary]; ok {
			layer.FidSSRC = rtx
		}
		videoLayers = append(videoLayers, layer)
	}

	// 5. Create participant config.
	config := ParticipantConfig{
		AudioSSRC:   audioSSRC,
		Ufrag:       payload.Ufrag,
		Pwd:         payload.Pwd,
		Fingerprint: remoteFingerprint,
	}

	// 6. Create participant.
	p, err := NewParticipant(participantID, config, s.loggerFactory)
	if err != nil {
		return "", fmt.Errorf("create participant: %w", err)
	}

	// 7. Wire Colibri callback for video constraint messages.
	p.SetColibriCallback(s.handleColibriMessage)

	// 7b. Wire RTCP feedback callback for PLI/FIR forwarding.
	p.SetRTCPFeedbackCallback(s.handleRTCPFeedback)

	// 8. Gather ICE candidates.
	candidates, err := p.GatherCandidates()
	if err != nil {
		p.Close()
		return "", fmt.Errorf("gather candidates: %w", err)
	}

	// 9. Register participant and all SSRCs.
	s.mu.Lock()
	s.participants[participantID] = p
	s.ssrcRegistry[audioSSRC] = ssrcInfo{participantID: participantID, kind: "audio", layer: -1}
	if len(videoLayers) > 0 {
		s.videoSSRCs[participantID] = videoLayers
		for i, vl := range videoLayers {
			s.ssrcRegistry[vl.SSRC] = ssrcInfo{participantID: participantID, kind: "video", layer: i}
			if vl.FidSSRC != 0 {
				s.ssrcRegistry[vl.FidSSRC] = ssrcInfo{participantID: participantID, kind: "video-rtx", layer: i}
			}
		}
		s.rtxBuffers[participantID] = NewRtxRingBuffer(200)
	}
	s.mu.Unlock()

	s.log.Infof("Registered participant %d: audio=%d, video layers=%d", participantID, audioSSRC, len(videoLayers))
	for i, vl := range videoLayers {
		s.log.Infof("  video layer %d: ssrc=%d fid=%d", i, vl.SSRC, vl.FidSSRC)
	}

	// 10. Build response JSON.
	var candidatesJSON []candidateJSON
	for _, c := range candidates {
		candidatesJSON = append(candidatesJSON, iceCandidateToJSON(c))
	}

	resp := joinResponse{
		Transport: transportJSON{
			Ufrag: p.LocalUfrag(),
			Pwd:   p.LocalPwd(),
			Fingerprints: []fingerprintJSON{
				{
					Hash:        "sha-256",
					Fingerprint: p.Fingerprint(),
					Setup:       "active", // SFU is DTLS client (active); tgcalls is SSL_SERVER (passive)
				},
			},
			Candidates: candidatesJSON,
		},
	}

	// Add video section if participant has video SSRCs.
	if len(videoLayers) > 0 {
		resp.Video = &videoResponseJSON{
			Endpoint: fmt.Sprintf("%d", participantID),
			PayloadTypes: []videoPayloadTypeJSON{
				{
					ID:        100,
					Name:      "H264",
					Clockrate: 90000,
					Parameters: map[string]string{
						"profile-level-id":  "42e01f",
						"packetization-mode": "1",
					},
					Feedback: []rtcpFeedbackJSON{
						{Type: "goog-remb"},
						{Type: "transport-cc"},
						{Type: "ccm", Subtype: "fir"},
						{Type: "nack"},
						{Type: "nack", Subtype: "pli"},
					},
				},
				{
					ID:        101,
					Name:      "rtx",
					Clockrate: 90000,
					Parameters: map[string]string{
						"apt": "100",
					},
				},
			},
			RTPHdrexts: []rtpHdrextJSON{
				{ID: 2, URI: "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time"},
				{ID: 3, URI: "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01"},
				{ID: 13, URI: "urn:3gpp:video-orientation"},
			},
		}
	}

	respBytes, err := json.Marshal(resp)
	if err != nil {
		return "", fmt.Errorf("marshal response: %w", err)
	}

	// 11. Start connection + RTP forwarding in background.
	go func() {
		if err := p.Connect(s.ctx, payload.Ufrag, payload.Pwd, iceControlling); err != nil {
			s.log.Warnf("Participant %d connect failed: %v", participantID, err)
			return
		}
		s.log.Infof("Participant %d connected, starting RTP forwarding", participantID)

		// Start transport-cc feedback generator for this participant.
		twccGen := NewTransportCCGenerator(func(data []byte) {
			if err := p.WriteRTCP(data); err != nil {
				s.log.Debugf("TWCC feedback to participant %d failed: %v", participantID, err)
			}
		})
		s.mu.Lock()
		s.twccGenerators[participantID] = twccGen
		s.mu.Unlock()

		// Broadcast updated SSRC list to all participants (after data channel is ready).
		// Small delay to let the data channel establish.
		time.Sleep(500 * time.Millisecond)
		s.broadcastActiveSSRCs()
		s.broadcastActiveVideoSSRCs()

		s.forwardRTP(p)
	}()

	return string(respBytes), nil
}

// readParticipants returns a snapshot of the current participant map.
func (s *SFU) readParticipants() map[int]*Participant {
	s.mu.RLock()
	defer s.mu.RUnlock()
	snap := make(map[int]*Participant, len(s.participants))
	for id, p := range s.participants {
		snap[id] = p
	}
	return snap
}

// forwardRTP reads RTP from a participant and forwards to all others.
// For video/video-rtx SSRCs, only forwards to receivers whose requested layer matches.
// Audio is forwarded unconditionally to all other participants.
func (s *SFU) forwardRTP(from *Participant) {
	for {
		stream, ssrc, err := from.AcceptStream()
		if err != nil {
			select {
			case <-s.ctx.Done():
				return
			default:
				s.log.Warnf("Participant %d AcceptStream error: %v", from.ID, err)
				return
			}
		}

		// Register SSRC if not already known (assume audio for undeclared SSRCs).
		s.mu.Lock()
		if _, exists := s.ssrcRegistry[ssrc]; !exists {
			s.log.Warnf("Participant %d: undeclared SSRC %d, registering as audio", from.ID, ssrc)
			s.ssrcRegistry[ssrc] = ssrcInfo{participantID: from.ID, kind: "audio", layer: -1}
		}
		info := s.ssrcRegistry[ssrc]
		s.mu.Unlock()

		s.log.Infof("Participant %d: accepted stream SSRC=%d (kind=%s, layer=%d)", from.ID, ssrc, info.kind, info.layer)

		go func(streamInfo ssrcInfo) {
			buf := make([]byte, 1500)
			for {
				n, err := stream.Read(buf)
				if err != nil {
					select {
					case <-s.ctx.Done():
						return
					default:
						s.log.Debugf("Participant %d stream read error: %v", from.ID, err)
						return
					}
				}

				pkt := make([]byte, n)
				copy(pkt, buf[:n])

				from.ingressSim.Send(pkt, func(simPkt []byte) {
					// Record transport-cc arrival after ingress simulation.
					twccSeq, ok := parseTWCCSeq(simPkt, 3)
					if ok {
						s.mu.RLock()
						gen := s.twccGenerators[from.ID]
						s.mu.RUnlock()
						if gen != nil {
							gen.RecordArrival(twccSeq)
						}
					}

					s.processIncomingRTP(from, simPkt, ssrc, streamInfo)
				})
			}
		}(info)
	}
}

// processIncomingRTP handles a single RTP packet from a participant after ingress simulation.
func (s *SFU) processIncomingRTP(from *Participant, pkt []byte, ssrc uint32, streamInfo ssrcInfo) {
	if streamInfo.kind == "audio" {
		// Audio: forward to all other participants unconditionally.
		s.mu.RLock()
		for id, p := range s.participants {
			if id == from.ID {
				continue
			}
			if _, err := p.WriteRTP(pkt); err != nil {
				s.log.Debugf("WriteRTP to participant %d failed: %v", id, err)
			}
		}
		s.mu.RUnlock()
	} else {
		// Video/video-rtx: forward the best available layer to each receiver.
		// Track max active layer for video (not video-rtx) packets.
		if streamInfo.kind == "video" {
			s.mu.Lock()
			rtxBuf := s.rtxBuffers[from.ID]
			maxActiveIncreased := false
			if cur, ok := s.maxActiveLayer[from.ID]; !ok || streamInfo.layer > cur {
				s.maxActiveLayer[from.ID] = streamInfo.layer
				maxActiveIncreased = true
			}
			newMax := s.maxActiveLayer[from.ID]
			var selectorsToNotify []*LayerSelector
			if maxActiveIncreased {
				for key, sel := range s.layerSelectors {
					if key[1] == from.ID {
						selectorsToNotify = append(selectorsToNotify, sel)
					}
				}
			}
			s.mu.Unlock()

			// Notify layer selectors outside the lock to avoid deadlock.
			for _, sel := range selectorsToNotify {
				sel.OnMaxActiveLayerIncreased(newMax)
			}

			if rtxBuf != nil && len(pkt) >= 4 {
				seqNum := uint16(pkt[2])<<8 | uint16(pkt[3])
				var ts uint32
				if len(pkt) >= 8 {
					ts = uint32(pkt[4])<<24 | uint32(pkt[5])<<16 | uint32(pkt[6])<<8 | uint32(pkt[7])
				}
				rtxBuf.Push(pkt, seqNum, ts)
			}
		}

		s.mu.RLock()
		maxActive, hasActive := s.maxActiveLayer[from.ID]
		s.mu.RUnlock()

		snap := s.readParticipants()
		for id, p := range snap {
			if id == from.ID {
				continue
			}
			// Determine effective layer: use selectedLayer if set,
			// otherwise use maxActiveLayer (best available).
			selectedLayer := p.GetSelectedLayer(from.ID)
			requestedLayer := p.GetRequestedLayer(from.ID)
			var effectiveLayer int
			if selectedLayer >= 0 {
				effectiveLayer = selectedLayer
			} else if requestedLayer >= 0 {
				// Pre-selector: forward at best available, capped by request.
				effectiveLayer = requestedLayer
			} else {
				continue // receiver doesn't want video from this sender
			}
			// Clamp to what the sender actually produces.
			if hasActive && effectiveLayer > maxActive {
				effectiveLayer = maxActive
			}
			if streamInfo.layer == effectiveLayer {
				fwdPkt := pkt
				// If forwarding a non-base layer, rewrite the SSRC in the
				// RTP header to the primary (layer 0) SSRC. The receiver's
				// video sink is attached to the primary SSRC only.
				if effectiveLayer > 0 && len(fwdPkt) >= 12 {
					s.mu.RLock()
					senderLayers := s.videoSSRCs[from.ID]
					s.mu.RUnlock()
					if len(senderLayers) > 0 {
						primarySSRC := senderLayers[0].SSRC
						var rtxSSRC uint32
						if streamInfo.kind == "video-rtx" && senderLayers[0].FidSSRC != 0 {
							rtxSSRC = senderLayers[0].FidSSRC
						}
						fwdPkt = make([]byte, len(pkt))
						copy(fwdPkt, pkt)
						targetSSRC := primarySSRC
						if streamInfo.kind == "video-rtx" && rtxSSRC != 0 {
							targetSSRC = rtxSSRC
						}
						fwdPkt[8] = byte(targetSSRC >> 24)
						fwdPkt[9] = byte(targetSSRC >> 16)
						fwdPkt[10] = byte(targetSSRC >> 8)
						fwdPkt[11] = byte(targetSSRC)
					}
				}
				if _, err := p.WriteRTP(fwdPkt); err != nil {
					s.log.Debugf("WriteRTP video to participant %d failed: %v", id, err)
				}
			}
		}
	}
}

// heightToLayer maps a requested video height to a simulcast layer index.
func heightToLayer(height int) int {
	if height <= 0 {
		return -1
	}
	if height <= 90 {
		return 0
	}
	if height <= 180 {
		return 1
	}
	return 2
}

// handleColibriMessage processes an incoming Colibri message from a participant.
func (s *SFU) handleColibriMessage(participantID int, msg string) {
	var base struct {
		ColibriClass string `json:"colibriClass"`
	}
	if err := json.Unmarshal([]byte(msg), &base); err != nil {
		s.log.Debugf("Participant %d: invalid Colibri JSON: %v", participantID, err)
		return
	}

	switch base.ColibriClass {
	case "ReceiverVideoConstraints":
		s.handleReceiverVideoConstraints(participantID, msg)
	default:
		s.log.Debugf("Participant %d: unhandled Colibri class: %s", participantID, base.ColibriClass)
	}
}

// handleRTCPFeedback is called when a participant sends PLI or FIR for a MediaSSRC.
// It looks up the sender of that SSRC and forwards a new PLI to them.
func (s *SFU) handleRTCPFeedback(fromID int, mediaSSRC uint32, isFIR bool) {
	s.mu.RLock()
	info, ok := s.ssrcRegistry[mediaSSRC]
	if !ok {
		s.mu.RUnlock()
		s.log.Debugf("RTCP feedback from %d: unknown MediaSSRC=%d", fromID, mediaSSRC)
		return
	}
	sender, senderOk := s.participants[info.participantID]
	s.mu.RUnlock()

	if !senderOk {
		s.log.Debugf("RTCP feedback from %d: sender %d not found for MediaSSRC=%d", fromID, info.participantID, mediaSSRC)
		return
	}

	kind := "PLI"
	if isFIR {
		kind = "FIR"
	}
	s.log.Infof("Forwarding %s to participant %d for MediaSSRC=%d (requested by %d)", kind, info.participantID, mediaSSRC, fromID)

	// Construct and send PLI to the sender (PLI is simpler and universally supported).
	pli := &rtcp.PictureLossIndication{
		SenderSSRC: 0,
		MediaSSRC:  mediaSSRC,
	}
	data, err := rtcp.Marshal([]rtcp.Packet{pli})
	if err != nil {
		s.log.Warnf("Failed to marshal PLI: %v", err)
		return
	}

	if err := sender.WriteRTCP(data); err != nil {
		s.log.Debugf("Failed to send PLI to participant %d: %v", info.participantID, err)
	}
}

type receiverVideoConstraints struct {
	DefaultConstraints *videoConstraint            `json:"defaultConstraints"`
	Constraints        map[string]videoConstraint  `json:"constraints"`
}

type videoConstraint struct {
	MinHeight int `json:"minHeight"`
	MaxHeight int `json:"maxHeight"`
}

type senderVideoConstraints struct {
	ColibriClass     string               `json:"colibriClass"`
	VideoConstraints senderVideoConstraint `json:"videoConstraints"`
}

type senderVideoConstraint struct {
	IdealHeight int `json:"idealHeight"`
}

func (s *SFU) handleReceiverVideoConstraints(receiverID int, msg string) {
	var rvc receiverVideoConstraints
	if err := json.Unmarshal([]byte(msg), &rvc); err != nil {
		s.log.Warnf("Participant %d: bad ReceiverVideoConstraints: %v", receiverID, err)
		return
	}

	s.mu.RLock()
	receiver, ok := s.participants[receiverID]
	s.mu.RUnlock()
	if !ok {
		return
	}

	// Track which senders are affected so we can update their SenderVideoConstraints.
	affectedSenders := make(map[int]bool)

	// Apply per-endpoint constraints and wire LayerSelector.
	for endpointStr, constraint := range rvc.Constraints {
		var senderID int
		if _, err := fmt.Sscanf(endpointStr, "%d", &senderID); err != nil {
			continue
		}
		layer := heightToLayer(constraint.MaxHeight)
		receiver.SetRequestedLayer(senderID, layer)
		s.ensureLayerSelector(receiverID, senderID, layer)
		affectedSenders[senderID] = true
	}

	// Apply default constraints to all other senders with video.
	// Collect senderIDs under RLock, release, then call ensureLayerSelector (needs write lock).
	if rvc.DefaultConstraints != nil {
		defaultLayer := heightToLayer(rvc.DefaultConstraints.MaxHeight)
		var defaultSenders []int
		s.mu.RLock()
		for senderID := range s.videoSSRCs {
			if senderID == receiverID {
				continue
			}
			if !affectedSenders[senderID] {
				defaultSenders = append(defaultSenders, senderID)
			}
		}
		s.mu.RUnlock()

		for _, senderID := range defaultSenders {
			receiver.SetRequestedLayer(senderID, defaultLayer)
			s.ensureLayerSelector(receiverID, senderID, defaultLayer)
			affectedSenders[senderID] = true
		}
	}

	// Send SenderVideoConstraints to each affected sender.
	// idealHeight = max height any receiver wants from this sender.
	for senderID := range affectedSenders {
		s.sendSenderVideoConstraints(senderID)
	}

	// Send PLI to each sender that the receiver wants video from.
	// This triggers a keyframe so the decoder can start producing frames.
	for senderID := range affectedSenders {
		layer := receiver.GetRequestedLayer(senderID)
		if layer >= 0 {
			s.mu.RLock()
			layers := s.videoSSRCs[senderID]
			s.mu.RUnlock()
			if len(layers) > 0 {
				s.handleRTCPFeedback(receiverID, layers[0].SSRC, false)
			}
		}
	}
}

// ensureLayerSelector creates or updates a LayerSelector for a (receiver, sender) pair.
func (s *SFU) ensureLayerSelector(receiverID, senderID, maxLayer int) {
	if maxLayer < 0 {
		return // no video requested from this sender
	}

	key := [2]int{receiverID, senderID}

	s.mu.Lock()
	existing, exists := s.layerSelectors[key]
	if exists {
		s.mu.Unlock()
		existing.SetMaxLayer(maxLayer)
		return
	}

	receiver, recvOk := s.participants[receiverID]
	videoLayers := s.videoSSRCs[senderID]
	s.mu.Unlock()

	if !recvOk {
		return
	}

	initialLayer := maxLayer
	if initialLayer > 2 {
		initialLayer = 2
	}

	// Set selectedLayer immediately, clamped to what the sender produces.
	// The forwardRTP loop will further clamp to maxActiveLayer on each packet.
	s.mu.RLock()
	maxActive, hasActive := s.maxActiveLayer[senderID]
	s.mu.RUnlock()
	layer := initialLayer
	if hasActive && layer > maxActive {
		layer = maxActive
	}
	receiver.SetSelectedLayer(senderID, layer)

	layersCopy := make([]SimulcastLayer, len(videoLayers))
	copy(layersCopy, videoLayers)

	cb := LayerSelectorCallbacks{
		GetEffectiveBW: func() float64 {
			return receiver.bwEstimator.EffectiveBps()
		},
		SetSelectedLayer: func(layer int) {
			receiver.SetSelectedLayer(senderID, layer)
		},
		SendPLI: func(ssrc uint32) {
			s.handleRTCPFeedback(receiverID, ssrc, false)
		},
		GetSenderVideoLayers: func() []SimulcastLayer {
			return layersCopy
		},
		GetRtxBuffer: func() *RtxRingBuffer {
			s.mu.RLock()
			defer s.mu.RUnlock()
			return s.rtxBuffers[senderID]
		},
		SendRtxPadding: func(rtxPayload []byte, rtxSSRC uint32, seqNum uint16, timestamp uint32) {
			hdr := make([]byte, 12+len(rtxPayload))
			hdr[0] = 0x80 // V=2
			hdr[1] = 101  // PT=101 (RTX for H264)
			hdr[2] = byte(seqNum >> 8)
			hdr[3] = byte(seqNum)
			hdr[4] = byte(timestamp >> 24)
			hdr[5] = byte(timestamp >> 16)
			hdr[6] = byte(timestamp >> 8)
			hdr[7] = byte(timestamp)
			hdr[8] = byte(rtxSSRC >> 24)
			hdr[9] = byte(rtxSSRC >> 16)
			hdr[10] = byte(rtxSSRC >> 8)
			hdr[11] = byte(rtxSSRC)
			copy(hdr[12:], rtxPayload)
			if _, err := receiver.WriteRTP(hdr); err != nil {
				s.log.Debugf("RTX padding to participant %d failed: %v", receiverID, err)
			}
		},
		Log: func(level string, format string, args ...interface{}) {
			msg := fmt.Sprintf(format, args...)
			if level == "INFO" {
				s.log.Infof("%s", msg)
			} else {
				s.log.Debugf("%s", msg)
			}
		},
	}

	ls := NewLayerSelector(receiverID, senderID, initialLayer, maxLayer, cb)

	s.mu.Lock()
	s.layerSelectors[key] = ls
	s.mu.Unlock()
}

func (s *SFU) sendSenderVideoConstraints(senderID int) {
	snap := s.readParticipants()

	maxHeight := 0
	for id, p := range snap {
		if id == senderID {
			continue
		}
		layer := p.GetRequestedLayer(senderID)
		var h int
		switch layer {
		case 0:
			h = 90
		case 1:
			h = 180
		case 2:
			h = 720
		default:
			continue
		}
		if h > maxHeight {
			maxHeight = h
		}
	}

	sender, ok := snap[senderID]
	if !ok {
		return
	}

	svc := senderVideoConstraints{
		ColibriClass:     "SenderVideoConstraints",
		VideoConstraints: senderVideoConstraint{IdealHeight: maxHeight},
	}
	data, _ := json.Marshal(svc)
	if err := sender.SendText(string(data)); err != nil {
		s.log.Debugf("SendText SenderVideoConstraints to %d: %v", senderID, err)
	}
}

// QuerySSRC returns the participant ID for a given SSRC, or -1 if unknown.
func (s *SFU) QuerySSRC(ssrc uint32) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if info, ok := s.ssrcRegistry[ssrc]; ok {
		return info.participantID
	}
	return -1
}

// QueryVideoSSRCs returns a JSON array of simulcast layers for a given participant.
// Format: [{"ssrc":N,"fidSsrc":M},...]
// Returns "[]" if the participant has no video SSRCs.
func (s *SFU) QueryVideoSSRCs(participantID int) string {
	s.mu.RLock()
	defer s.mu.RUnlock()

	layers, ok := s.videoSSRCs[participantID]
	if !ok || len(layers) == 0 {
		return "[]"
	}

	type layerJSON struct {
		SSRC    uint32 `json:"ssrc"`
		FidSSRC uint32 `json:"fidSsrc"`
	}
	out := make([]layerJSON, len(layers))
	for i, l := range layers {
		out[i] = layerJSON{SSRC: l.SSRC, FidSSRC: l.FidSSRC}
	}
	data, _ := json.Marshal(out)
	return string(data)
}

// SetNetworkParams configures network simulation for a participant.
// direction: 0 = ingress (from client), 1 = egress (to client).
func (s *SFU) SetNetworkParams(participantID int, direction int, delayMs, jitterMs int, dropRate float64, bandwidthBps int64) {
	s.mu.RLock()
	p, ok := s.participants[participantID]
	s.mu.RUnlock()
	if !ok {
		return
	}
	var sim *NetworkSimulator
	if direction == 0 {
		sim = p.ingressSim
	} else {
		sim = p.egressSim
	}
	if sim != nil {
		sim.SetParams(delayMs, jitterMs, dropRate, bandwidthBps)
	}
	dirName := "ingress"
	if direction == 1 {
		dirName = "egress"
	}
	s.log.Infof("Participant %d %s: delay=%dms jitter=%dms drop=%.2f bw=%d bps",
		participantID, dirName, delayMs, jitterMs, dropRate, bandwidthBps)
}

// broadcastActiveSSRCs sends the current set of active audio SSRCs to all connected participants.
// Each participant receives a list excluding their own SSRC.
func (s *SFU) broadcastActiveSSRCs() {
	s.mu.RLock()
	defer s.mu.RUnlock()

	// Collect all audio SSRCs per participant.
	participantSSRCs := make(map[int]uint32) // participantID -> audioSSRC
	for ssrc, info := range s.ssrcRegistry {
		if info.kind == "audio" {
			if _, exists := participantSSRCs[info.participantID]; !exists {
				participantSSRCs[info.participantID] = ssrc
			}
		}
	}

	for id, p := range s.participants {
		var ssrcs []int32
		for otherID, ssrc := range participantSSRCs {
			if otherID == id {
				continue
			}
			ssrcs = append(ssrcs, int32(ssrc))
		}

		msg := buildActiveSSRCsMessage(ssrcs)
		if err := p.SendText(msg); err != nil {
			s.log.Debugf("SendText to participant %d: %v", id, err)
		}
	}
}

// broadcastActiveVideoSSRCs sends the current set of active video SSRCs to all connected participants.
// Each participant receives a list excluding their own video SSRCs.
func (s *SFU) broadcastActiveVideoSSRCs() {
	s.mu.RLock()
	defer s.mu.RUnlock()

	// Only broadcast if any participant has video.
	if len(s.videoSSRCs) == 0 {
		return
	}

	for id, p := range s.participants {
		var entries []videoSSRCEntry
		for otherID, layers := range s.videoSSRCs {
			if otherID == id {
				continue
			}
			if len(layers) == 0 {
				continue
			}
			entry := videoSSRCEntry{
				EndpointID: fmt.Sprintf("%d", otherID),
				SSRC:       int32(layers[0].SSRC),
			}
			// Build SIM group.
			simGroup := ssrcGroupJSON{Semantics: "SIM"}
			for _, l := range layers {
				simGroup.Sources = append(simGroup.Sources, int32(l.SSRC))
			}
			entry.SSRCGroups = append(entry.SSRCGroups, simGroup)
			// Build FID groups.
			for _, l := range layers {
				if l.FidSSRC != 0 {
					entry.SSRCGroups = append(entry.SSRCGroups, ssrcGroupJSON{
						Semantics: "FID",
						Sources:   []int32{int32(l.SSRC), int32(l.FidSSRC)},
					})
				}
			}
			entries = append(entries, entry)
		}

		if len(entries) == 0 {
			continue
		}

		msg := buildActiveVideoSSRCsMessage(entries)
		if err := p.SendText(msg); err != nil {
			s.log.Debugf("SendText video SSRCs to participant %d: %v", id, err)
		}
	}
}

type videoSSRCEntry struct {
	EndpointID string          `json:"endpointId"`
	SSRC       int32           `json:"ssrc"`
	SSRCGroups []ssrcGroupJSON `json:"ssrcGroups"`
}

func buildActiveVideoSSRCsMessage(entries []videoSSRCEntry) string {
	type msg struct {
		ColibriClass string           `json:"colibriClass"`
		SSRCs        []videoSSRCEntry `json:"ssrcs"`
	}
	data, _ := json.Marshal(msg{ColibriClass: "ActiveVideoSsrcs", SSRCs: entries})
	return string(data)
}

func buildActiveSSRCsMessage(ssrcs []int32) string {
	buf := []byte(`{"colibriClass":"ActiveAudioSsrcs","ssrcs":[`)
	for i, ssrc := range ssrcs {
		if i > 0 {
			buf = append(buf, ',')
		}
		buf = append(buf, fmt.Sprintf("%d", ssrc)...)
	}
	buf = append(buf, ']', '}')
	return string(buf)
}

// Leave removes a participant from the SFU, closes their transport,
// and broadcasts updated SSRC lists to remaining participants.
func (s *SFU) Leave(participantID int) error {
	s.mu.Lock()
	p, ok := s.participants[participantID]
	if !ok {
		s.mu.Unlock()
		return fmt.Errorf("participant %d not found", participantID)
	}

	// Remove from participants map.
	delete(s.participants, participantID)

	// Remove all SSRCs owned by this participant.
	for ssrc, info := range s.ssrcRegistry {
		if info.participantID == participantID {
			delete(s.ssrcRegistry, ssrc)
		}
	}

	// Remove video SSRCs.
	delete(s.videoSSRCs, participantID)

	// Remove RTX buffer for this sender.
	delete(s.rtxBuffers, participantID)
	delete(s.maxActiveLayer, participantID)

	// Stop and remove all layer selectors involving this participant.
	var toStop []*LayerSelector
	for key, ls := range s.layerSelectors {
		if key[0] == participantID || key[1] == participantID {
			toStop = append(toStop, ls)
			delete(s.layerSelectors, key)
		}
	}

	// Remove TWCC generator.
	var twccGen *TransportCCGenerator
	if gen, ok := s.twccGenerators[participantID]; ok {
		twccGen = gen
		delete(s.twccGenerators, participantID)
	}

	s.mu.Unlock()

	// Stop layer selectors outside the lock.
	for _, ls := range toStop {
		ls.Stop()
	}

	// Stop TWCC generator outside the lock.
	if twccGen != nil {
		twccGen.Stop()
	}

	// Close transport (outside lock — Close can block).
	if err := p.Close(); err != nil {
		s.log.Warnf("Error closing participant %d: %v", participantID, err)
	}

	s.log.Infof("Participant %d left", participantID)

	// Broadcast updated SSRC lists to remaining participants.
	s.broadcastActiveSSRCs()
	s.broadcastActiveVideoSSRCs()

	return nil
}

// Destroy closes all participants and cancels the SFU context.
func (s *SFU) Destroy() {
	s.cancel()
	s.mu.Lock()
	// Stop all layer selectors before closing participants.
	for _, ls := range s.layerSelectors {
		ls.Stop()
	}
	s.layerSelectors = nil
	// Stop all TWCC generators.
	for _, gen := range s.twccGenerators {
		gen.Stop()
	}
	s.twccGenerators = nil
	for id, p := range s.participants {
		if err := p.Close(); err != nil {
			s.log.Warnf("Error closing participant %d: %v", id, err)
		}
	}
	s.participants = nil
	s.ssrcRegistry = nil
	s.videoSSRCs = nil
	s.rtxBuffers = nil
	s.maxActiveLayer = nil
	s.mu.Unlock()
}

// iceCandidateToJSON converts a pion ICE candidate to our JSON format.
func iceCandidateToJSON(c ice.Candidate) candidateJSON {
	return candidateJSON{
		Port:       fmt.Sprintf("%d", c.Port()),
		Protocol:   "udp",
		Network:    "0",
		Generation: "0",
		ID:         c.ID(),
		Component:  fmt.Sprintf("%d", c.Component()),
		Foundation: c.Foundation(),
		Priority:   fmt.Sprintf("%d", c.Priority()),
		IP:         c.Address(),
		Type:       "host",
	}
}

// --- Global SFU registry ---

var (
	sfuRegistry   = make(map[int]*SFU)
	sfuRegistryMu sync.Mutex
	sfuNextID     int32
)

// --- CGo exports ---

//export GoSfu_Init
func GoSfu_Init() C.int {
	fmt.Println("[GoSfu] Initialized")
	return 0
}

//export GoSfu_Create
func GoSfu_Create() C.int {
	handle := int(atomic.AddInt32(&sfuNextID, 1))
	sfu := NewSFU()
	sfuRegistryMu.Lock()
	sfuRegistry[handle] = sfu
	sfuRegistryMu.Unlock()
	fmt.Printf("[GoSfu] Created SFU handle=%d\n", handle)
	return C.int(handle)
}

//export GoSfu_Destroy
func GoSfu_Destroy(handle C.int) {
	h := int(handle)
	sfuRegistryMu.Lock()
	sfu, ok := sfuRegistry[h]
	if ok {
		delete(sfuRegistry, h)
	}
	sfuRegistryMu.Unlock()
	if ok {
		sfu.Destroy()
		fmt.Printf("[GoSfu] Destroyed SFU handle=%d\n", h)
	}
}

//export GoSfu_Join
func GoSfu_Join(handle C.int, participantID C.int, joinPayloadJSON *C.char, iceControlling C.int) *C.char {
	h := int(handle)
	sfuRegistryMu.Lock()
	sfu, ok := sfuRegistry[h]
	sfuRegistryMu.Unlock()
	if !ok {
		errMsg := fmt.Sprintf(`{"error":"unknown SFU handle %d"}`, h)
		return C.CString(errMsg)
	}

	payload := C.GoString(joinPayloadJSON)
	resp, err := sfu.Join(int(participantID), payload, iceControlling != 0)
	if err != nil {
		errMsg := fmt.Sprintf(`{"error":"%s"}`, err.Error())
		return C.CString(errMsg)
	}
	return C.CString(resp)
}

//export GoSfu_Leave
func GoSfu_Leave(handle C.int, participantID C.int) C.int {
	h := int(handle)
	sfuRegistryMu.Lock()
	sfu, ok := sfuRegistry[h]
	sfuRegistryMu.Unlock()
	if !ok {
		return -1
	}
	if err := sfu.Leave(int(participantID)); err != nil {
		fmt.Printf("[GoSfu] Leave error: %v\n", err)
		return -1
	}
	return 0
}

//export GoSfu_QuerySsrc
func GoSfu_QuerySsrc(handle C.int, ssrc C.uint) C.int {
	h := int(handle)
	sfuRegistryMu.Lock()
	sfu, ok := sfuRegistry[h]
	sfuRegistryMu.Unlock()
	if !ok {
		return -1
	}
	return C.int(sfu.QuerySSRC(uint32(ssrc)))
}

//export GoSfu_QueryVideoSsrcs
func GoSfu_QueryVideoSsrcs(handle C.int, participantID C.int) *C.char {
	h := int(handle)
	sfuRegistryMu.Lock()
	sfu, ok := sfuRegistry[h]
	sfuRegistryMu.Unlock()
	if !ok {
		return C.CString("[]")
	}
	return C.CString(sfu.QueryVideoSSRCs(int(participantID)))
}

//export GoSfu_SetNetworkParams
func GoSfu_SetNetworkParams(handle C.int, participantID C.int, direction C.int, delayMs C.int, jitterMs C.int, dropRate C.double, bandwidthBps C.long) {
	h := int(handle)
	sfuRegistryMu.Lock()
	sfu, ok := sfuRegistry[h]
	sfuRegistryMu.Unlock()
	if !ok {
		return
	}
	sfu.SetNetworkParams(int(participantID), int(direction), int(delayMs), int(jitterMs), float64(dropRate), int64(bandwidthBps))
}

//export GoSfu_Free
func GoSfu_Free(ptr *C.char) {
	C.free(unsafe.Pointer(ptr))
}

//export GoSfu_Shutdown
func GoSfu_Shutdown() {
	sfuRegistryMu.Lock()
	for h, sfu := range sfuRegistry {
		sfu.Destroy()
		delete(sfuRegistry, h)
	}
	sfuRegistryMu.Unlock()
	fmt.Println("[GoSfu] Shutdown")
}

func main() {}
