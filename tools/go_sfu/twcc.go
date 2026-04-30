package main

import (
	"encoding/binary"
	"sync"
	"time"

	"github.com/pion/rtcp"
)

// --- RTP Header Extension Parsing ---

// parseTWCCSeq extracts the transport-wide sequence number from an RTP packet.
// extID is the header extension ID to look for (typically 3).
// Returns the sequence number and true if found, or 0 and false.
func parseTWCCSeq(pkt []byte, extID int) (uint16, bool) {
	if len(pkt) < 12 {
		return 0, false
	}

	// Check extension bit (X) in RTP header byte 0.
	if pkt[0]&0x10 == 0 {
		return 0, false
	}

	// Skip fixed header (12 bytes) + CSRC list.
	cc := int(pkt[0] & 0x0F)
	offset := 12 + cc*4
	if offset+4 > len(pkt) {
		return 0, false
	}

	// Check for one-byte header extension (0xBEDE magic).
	if pkt[offset] != 0xBE || pkt[offset+1] != 0xDE {
		return 0, false
	}

	// Extension length in 32-bit words.
	extLen := int(binary.BigEndian.Uint16(pkt[offset+2:])) * 4
	offset += 4
	extEnd := offset + extLen
	if extEnd > len(pkt) {
		return 0, false
	}

	// Scan extension elements: [id:4][len:4][data...].
	for offset < extEnd {
		b := pkt[offset]
		if b == 0 {
			// Padding byte.
			offset++
			continue
		}
		id := int(b >> 4)
		dataLen := int(b&0x0F) + 1 // len field is 0-based
		offset++
		if id == extID && dataLen >= 2 && offset+2 <= extEnd {
			seq := binary.BigEndian.Uint16(pkt[offset:])
			return seq, true
		}
		offset += dataLen
	}

	return 0, false
}

// --- Transport-CC Feedback Generator ---

type twccArrival struct {
	seq       uint16
	arrivalUs int64 // microseconds since generator creation
}

// TransportCCGenerator generates RTCP transport-cc feedback for a sender.
// It tracks packet arrivals and emits feedback every 100ms.
type TransportCCGenerator struct {
	mu        sync.Mutex
	arrivals  []twccArrival
	startTime time.Time
	fbCount   uint8 // feedback packet counter

	// Callback to send the feedback RTCP packet.
	sendFeedback func(data []byte)

	stopCh chan struct{}
	done   chan struct{}
}

// NewTransportCCGenerator creates and starts a generator.
// sendFeedback is called with marshalled+encrypted RTCP data to send to the sender.
func NewTransportCCGenerator(sendFeedback func(data []byte)) *TransportCCGenerator {
	g := &TransportCCGenerator{
		startTime:    time.Now(),
		sendFeedback: sendFeedback,
		stopCh:       make(chan struct{}),
		done:         make(chan struct{}),
	}
	go g.run()
	return g
}

// RecordArrival records a packet arrival. Thread-safe.
func (g *TransportCCGenerator) RecordArrival(twccSeq uint16) {
	g.mu.Lock()
	defer g.mu.Unlock()
	arrivalUs := time.Since(g.startTime).Microseconds()
	g.arrivals = append(g.arrivals, twccArrival{seq: twccSeq, arrivalUs: arrivalUs})
}

// Stop terminates the generator.
func (g *TransportCCGenerator) Stop() {
	close(g.stopCh)
	<-g.done
}

func (g *TransportCCGenerator) run() {
	defer close(g.done)
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-g.stopCh:
			return
		case <-ticker.C:
			g.emitFeedback()
		}
	}
}

func (g *TransportCCGenerator) emitFeedback() {
	g.mu.Lock()
	if len(g.arrivals) == 0 {
		g.mu.Unlock()
		return
	}

	// Take all arrivals.
	arrivals := g.arrivals
	g.arrivals = nil
	g.fbCount++
	fbCount := g.fbCount
	g.mu.Unlock()

	// Sort by sequence number (should already be mostly sorted).
	for i := 1; i < len(arrivals); i++ {
		for j := i; j > 0 && seqBefore(arrivals[j].seq, arrivals[j-1].seq); j-- {
			arrivals[j], arrivals[j-1] = arrivals[j-1], arrivals[j]
		}
	}

	baseSeq := arrivals[0].seq
	// Number of sequence numbers covered (including gaps).
	lastSeq := arrivals[len(arrivals)-1].seq
	packetCount := seqDiff(baseSeq, lastSeq) + 1

	// Reference time: arrival of first packet in 64ms units.
	refTimeUs := arrivals[0].arrivalUs
	refTime := uint32(refTimeUs / 64000) // 64ms units, 24-bit in spec but stored as uint32

	// Build received set for gap detection.
	receivedAt := make(map[uint16]int64, len(arrivals))
	for _, a := range arrivals {
		receivedAt[a.seq] = a.arrivalUs
	}

	// Build packet chunks and recv deltas.
	var chunks []rtcp.PacketStatusChunk
	var deltas []*rtcp.RecvDelta

	// Process in runs of up to 7 (status vector chunk capacity for 2-bit symbols).
	prevArrivalUs := refTimeUs
	var statusList []uint16

	seq := baseSeq
	for i := 0; i < int(packetCount); i++ {
		arrUs, received := receivedAt[seq]
		if received {
			deltaUs := arrUs - prevArrivalUs
			if deltaUs >= 0 && deltaUs <= 63750 { // fits in small delta (0-255 * 250us)
				statusList = append(statusList, rtcp.TypeTCCPacketReceivedSmallDelta)
				deltas = append(deltas, &rtcp.RecvDelta{
					Type:  rtcp.TypeTCCPacketReceivedSmallDelta,
					Delta: deltaUs,
				})
			} else {
				statusList = append(statusList, rtcp.TypeTCCPacketReceivedLargeDelta)
				deltas = append(deltas, &rtcp.RecvDelta{
					Type:  rtcp.TypeTCCPacketReceivedLargeDelta,
					Delta: deltaUs,
				})
			}
			prevArrivalUs = arrUs
		} else {
			statusList = append(statusList, rtcp.TypeTCCPacketNotReceived)
		}
		seq++
	}

	// Encode status list as status vector chunks (7 symbols per chunk with 2-bit symbols).
	for i := 0; i < len(statusList); i += 7 {
		end := i + 7
		if end > len(statusList) {
			end = len(statusList)
		}
		chunk := statusList[i:end]

		// Check if all same status (use run-length).
		allSame := true
		for _, s := range chunk {
			if s != chunk[0] {
				allSame = false
				break
			}
		}

		if allSame && len(chunk) >= 2 {
			chunks = append(chunks, &rtcp.RunLengthChunk{
				Type:               rtcp.TypeTCCRunLengthChunk,
				PacketStatusSymbol: chunk[0],
				RunLength:          uint16(len(chunk)),
			})
		} else {
			// Status vector with 2-bit symbols.
			symbolList := make([]uint16, len(chunk))
			copy(symbolList, chunk)
			chunks = append(chunks, &rtcp.StatusVectorChunk{
				Type:       rtcp.TypeTCCStatusVectorChunk,
				SymbolSize: rtcp.TypeTCCSymbolSizeTwoBit,
				SymbolList: symbolList,
			})
		}
	}

	fb := &rtcp.TransportLayerCC{
		SenderSSRC:         1,
		MediaSSRC:          0,
		BaseSequenceNumber: baseSeq,
		PacketStatusCount:  packetCount,
		ReferenceTime:      refTime,
		FbPktCount:         fbCount,
		PacketChunks:       chunks,
		RecvDeltas:         deltas,
	}

	data, err := rtcp.Marshal([]rtcp.Packet{fb})
	if err != nil {
		return
	}

	g.sendFeedback(data)
}

// seqBefore returns true if a comes before b in the uint16 sequence space.
func seqBefore(a, b uint16) bool {
	return int16(a-b) < 0
}

// seqDiff returns the forward distance from a to b in uint16 sequence space.
func seqDiff(a, b uint16) uint16 {
	return b - a
}
