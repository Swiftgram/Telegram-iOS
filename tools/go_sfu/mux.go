package main

import (
	"fmt"
	"io"
	"net"
	"sync"
	"time"
)

const (
	muxReadBufSize  = 8192
	muxChanBufSize  = 256
)

// isDTLS returns true if the first byte indicates a DTLS record (RFC 7983: 20–63).
func isDTLS(b byte) bool {
	return b >= 20 && b <= 63
}

// isRTPOrRTCP returns true if the first byte indicates an RTP/RTCP packet (RFC 7983: 128–191).
func isRTPOrRTCP(b byte) bool {
	return b >= 128 && b <= 191
}

// isRTCP returns true if the packet is RTCP (not RTP) per RFC 5761 Section 4.
// RTCP packet types (byte[1]) are 200-211. RTP with Marker=1 and dynamic PT >= 96
// gives byte[1] >= 224, so we use byte[1] >= 200 && byte[1] < 224 to exclude RTP.
// In SRTCP the fixed header is unencrypted, so byte[1] is readable.
func isRTCP(pkt []byte) bool {
	return len(pkt) >= 2 && pkt[1] >= 200 && pkt[1] < 224
}

// PacketDemux reads from a net.Conn and routes packets to separate DTLS,
// SRTP (RTP only), and RTCP channels based on RFC 7983 first-byte classification
// and RTP/RTCP payload type demux.
type PacketDemux struct {
	conn     net.Conn
	dtlsCh   chan []byte
	srtpCh   chan []byte
	rtcpCh   chan []byte
	once     sync.Once
	closed   chan struct{}
	label    string
}

func (d *PacketDemux) logf(format string, args ...interface{}) {
	fmt.Printf("[demux-%s] %s\n", d.label, fmt.Sprintf(format, args...))
}

// NewPacketDemux creates a PacketDemux and starts the read loop goroutine.
func NewPacketDemux(conn net.Conn, label string) *PacketDemux {
	d := &PacketDemux{
		conn:   conn,
		dtlsCh: make(chan []byte, muxChanBufSize),
		srtpCh: make(chan []byte, muxChanBufSize),
		rtcpCh: make(chan []byte, muxChanBufSize),
		closed: make(chan struct{}),
		label:  label,
	}
	go d.readLoop()
	return d
}

func (d *PacketDemux) readLoop() {
	buf := make([]byte, muxReadBufSize)
	dtlsCount := 0
	srtpCount := 0
	rtcpCount := 0
	otherCount := 0
	for {
		n, err := d.conn.Read(buf)
		if err != nil {
			d.Close()
			return
		}
		if n == 0 {
			continue
		}
		pkt := make([]byte, n)
		copy(pkt, buf[:n])

		switch {
		case isDTLS(pkt[0]):
			dtlsCount++
			if dtlsCount <= 5 {
				d.logf("DTLS packet #%d: %d bytes (first byte: 0x%02x)", dtlsCount, n, pkt[0])
			}
			select {
			case d.dtlsCh <- pkt:
			default:
				d.logf("DTLS channel full, dropping packet")
			}
		case isRTPOrRTCP(pkt[0]):
			if isRTCP(pkt) {
				rtcpCount++
				if rtcpCount <= 3 {
					d.logf("RTCP packet #%d: %d bytes (type byte: 0x%02x)", rtcpCount, n, pkt[1])
				}
				select {
				case d.rtcpCh <- pkt:
				default:
					// drop if channel full
				}
			} else {
				srtpCount++
				if srtpCount == 1 {
					d.logf("First SRTP packet: %d bytes", n)
				}
				select {
				case d.srtpCh <- pkt:
				default:
					// drop if channel full
				}
			}
		default:
			otherCount++
			if otherCount <= 3 {
				d.logf("Other packet: %d bytes (first byte: 0x%02x)", n, pkt[0])
			}
		}
	}
}

// Close shuts down the demuxer and the underlying connection.
func (d *PacketDemux) Close() error {
	var err error
	d.once.Do(func() {
		close(d.closed)
		err = d.conn.Close()
	})
	return err
}

// DTLSEndpoint returns a net.Conn that yields only DTLS packets.
func (d *PacketDemux) DTLSEndpoint() net.Conn {
	return &demuxEndpoint{demux: d, ch: d.dtlsCh}
}

// SRTPEndpoint returns a net.Conn that yields only SRTP (RTP) packets.
// RTCP packets are routed to RTCPChannel() instead.
func (d *PacketDemux) SRTPEndpoint() net.Conn {
	return &demuxEndpoint{demux: d, ch: d.srtpCh}
}

// RTCPChannel returns a channel that receives raw encrypted SRTCP packets.
// These must be decrypted externally (not via SessionSRTP which only handles RTP).
func (d *PacketDemux) RTCPChannel() <-chan []byte {
	return d.rtcpCh
}

// demuxEndpoint implements net.Conn for a single demux channel.
type demuxEndpoint struct {
	demux    *PacketDemux
	ch       chan []byte
	mu       sync.Mutex
	leftover []byte
}

func (e *demuxEndpoint) Read(b []byte) (int, error) {
	e.mu.Lock()
	if len(e.leftover) > 0 {
		n := copy(b, e.leftover)
		e.leftover = e.leftover[n:]
		if len(e.leftover) == 0 {
			e.leftover = nil
		}
		e.mu.Unlock()
		return n, nil
	}
	e.mu.Unlock()

	select {
	case <-e.demux.closed:
		return 0, io.EOF
	case pkt, ok := <-e.ch:
		if !ok {
			return 0, io.EOF
		}
		n := copy(b, pkt)
		if n < len(pkt) {
			e.mu.Lock()
			e.leftover = pkt[n:]
			e.mu.Unlock()
		}
		return n, nil
	}
}

func (e *demuxEndpoint) Write(b []byte) (int, error) {
	return e.demux.conn.Write(b)
}

func (e *demuxEndpoint) Close() error {
	return e.demux.Close()
}

func (e *demuxEndpoint) LocalAddr() net.Addr {
	return e.demux.conn.LocalAddr()
}

func (e *demuxEndpoint) RemoteAddr() net.Addr {
	return e.demux.conn.RemoteAddr()
}

func (e *demuxEndpoint) SetDeadline(t time.Time) error {
	return e.demux.conn.SetDeadline(t)
}

func (e *demuxEndpoint) SetReadDeadline(t time.Time) error {
	return e.demux.conn.SetReadDeadline(t)
}

func (e *demuxEndpoint) SetWriteDeadline(t time.Time) error {
	return e.demux.conn.SetWriteDeadline(t)
}

// connToPacketConn wraps a net.Conn into a net.PacketConn.
// It is used to adapt a demuxEndpoint for pion/dtls.Server(), which
// requires net.PacketConn. Since the endpoint is already bound to a
// single peer, ReadFrom returns the conn's RemoteAddr and WriteTo ignores
// the addr parameter.
type connToPacketConn struct {
	net.Conn
}

// WrapAsPacketConn adapts a net.Conn to net.PacketConn.
func WrapAsPacketConn(c net.Conn) net.PacketConn {
	return &connToPacketConn{Conn: c}
}

func (c *connToPacketConn) ReadFrom(b []byte) (int, net.Addr, error) {
	n, err := c.Conn.Read(b)
	return n, c.Conn.RemoteAddr(), err
}

func (c *connToPacketConn) WriteTo(b []byte, _ net.Addr) (int, error) {
	return c.Conn.Write(b)
}
