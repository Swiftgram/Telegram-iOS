package main

import (
	"sync"
	"time"
)

// --- Bandwidth Estimation ---

const (
	ewmaAlpha    = 0.3
	safetyFactor = 0.85
	stalenessTTL = 5 * time.Second
)

// BandwidthEstimator maintains an EWMA-smoothed REMB estimate for a receiver.
type BandwidthEstimator struct {
	mu          sync.Mutex
	lastREMBBps float64
	smoothedBps float64
	lastREMBAt  time.Time
}

// OnREMB feeds a new REMB value (in bits per second) into the estimator.
func (e *BandwidthEstimator) OnREMB(bps float64) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.lastREMBBps = bps
	e.lastREMBAt = time.Now()
	if e.smoothedBps == 0 {
		e.smoothedBps = bps
	} else {
		e.smoothedBps = ewmaAlpha*bps + (1-ewmaAlpha)*e.smoothedBps
	}
}

// EffectiveBps returns the safe bandwidth estimate in bps.
// Returns -1 if the estimate is stale (no REMB for stalenessTTL).
func (e *BandwidthEstimator) EffectiveBps() float64 {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.lastREMBAt.IsZero() || time.Since(e.lastREMBAt) > stalenessTTL {
		return -1
	}
	return e.smoothedBps * safetyFactor
}

// SmoothedBps returns the raw EWMA value (for logging).
func (e *BandwidthEstimator) SmoothedBps() float64 {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.smoothedBps
}

// LastREMBBps returns the last raw REMB value (for logging).
func (e *BandwidthEstimator) LastREMBBps() float64 {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.lastREMBBps
}

// --- Layer Bitrate Model ---

// LayerBitrate holds the thresholds for one simulcast layer.
type LayerBitrate struct {
	Nominal    float64 // typical sustained bitrate (bps)
	UpThresh   float64 // effective BW must exceed this to upswitch TO this layer
	DownThresh float64 // effective BW must drop below this to downswitch FROM this layer
}

// layerBitrates defines the 3 simulcast layers matching tgcalls adjustVideoSendParams().
// Layer 0 has no downThresh (always viable) and no upThresh (start here).
var layerBitrates = [3]LayerBitrate{
	{Nominal: 60_000, UpThresh: 0, DownThresh: 0},                // layer 0: 160x90
	{Nominal: 110_000, UpThresh: 132_000, DownThresh: 77_000},    // layer 1: 320x180
	{Nominal: 900_000, UpThresh: 1_080_000, DownThresh: 630_000}, // layer 2: 640x360
}

// --- RTX Ring Buffer ---

// RtxEntry stores one video RTP packet for potential retransmission as RTX padding.
type RtxEntry struct {
	Payload   []byte
	SeqNum    uint16
	Timestamp uint32
}

// RtxRingBuffer is a per-sender circular buffer of recent video RTP packets.
type RtxRingBuffer struct {
	mu      sync.Mutex
	entries []RtxEntry
	head    int
	count   int
	cap     int
}

// NewRtxRingBuffer creates a ring buffer with the given capacity.
func NewRtxRingBuffer(capacity int) *RtxRingBuffer {
	return &RtxRingBuffer{
		entries: make([]RtxEntry, capacity),
		cap:     capacity,
	}
}

// Push adds a video RTP packet to the ring buffer.
// payload is copied so the caller can reuse their buffer.
func (r *RtxRingBuffer) Push(payload []byte, seqNum uint16, timestamp uint32) {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry := &r.entries[r.head]
	if cap(entry.Payload) >= len(payload) {
		entry.Payload = entry.Payload[:len(payload)]
	} else {
		entry.Payload = make([]byte, len(payload))
	}
	copy(entry.Payload, payload)
	entry.SeqNum = seqNum
	entry.Timestamp = timestamp
	r.head = (r.head + 1) % r.cap
	if r.count < r.cap {
		r.count++
	}
}

// Get returns up to n most recent packets (oldest first).
func (r *RtxRingBuffer) Get(n int) []RtxEntry {
	r.mu.Lock()
	defer r.mu.Unlock()
	if n > r.count {
		n = r.count
	}
	if n == 0 {
		return nil
	}
	result := make([]RtxEntry, n)
	start := (r.head - r.count + r.cap) % r.cap       // oldest entry
	readFrom := (start + r.count - n + r.cap) % r.cap  // start of the n most recent
	for i := 0; i < n; i++ {
		idx := (readFrom + i) % r.cap
		src := &r.entries[idx]
		entry := RtxEntry{
			Payload:   make([]byte, len(src.Payload)),
			SeqNum:    src.SeqNum,
			Timestamp: src.Timestamp,
		}
		copy(entry.Payload, src.Payload)
		result[i] = entry
	}
	return result
}

// rtxEncapsulate wraps an original RTP payload into an RTX packet payload per RFC 4588.
// The RTX payload is: [2-byte original sequence number] + [original RTP payload (after header)].
// The caller is responsible for setting the RTX SSRC and incrementing RTX sequence number
// on the outer RTP header.
func rtxEncapsulate(originalPayload []byte, originalSeqNum uint16) []byte {
	out := make([]byte, 2+len(originalPayload))
	out[0] = byte(originalSeqNum >> 8)
	out[1] = byte(originalSeqNum)
	copy(out[2:], originalPayload)
	return out
}

// --- Layer Selector State Machine ---

type selectorState int

const (
	stateStable    selectorState = iota
	stateProbingUp
	stateGraceDown
)

func (s selectorState) String() string {
	switch s {
	case stateStable:
		return "STABLE"
	case stateProbingUp:
		return "PROBING_UP"
	case stateGraceDown:
		return "GRACE_DOWN"
	default:
		return "UNKNOWN"
	}
}

const (
	probeDuration    = 2 * time.Second
	graceDownTimeout = 500 * time.Millisecond
	cooldownDuration = 5 * time.Second
	tickInterval     = 100 * time.Millisecond
)

// LayerSelectorCallbacks provides the hooks the state machine needs into the SFU.
type LayerSelectorCallbacks struct {
	// GetEffectiveBW returns the receiver's current effective bandwidth (bps), or -1 if stale.
	GetEffectiveBW func() float64
	// SetSelectedLayer updates the forwarding layer for this (receiver, sender) pair.
	SetSelectedLayer func(layer int)
	// SendPLI sends a PLI to the sender for the given SSRC.
	SendPLI func(ssrc uint32)
	// GetSenderVideoLayers returns the sender's simulcast layers.
	GetSenderVideoLayers func() []SimulcastLayer
	// GetRtxBuffer returns the sender's RTX ring buffer.
	GetRtxBuffer func() *RtxRingBuffer
	// SendRtxPadding sends an RTX padding packet to the receiver.
	// rtxSSRC is the FID SSRC, seqNum is the RTX sequence number.
	SendRtxPadding func(rtxPayload []byte, rtxSSRC uint32, seqNum uint16, timestamp uint32)
	// Log emits a log message.
	Log func(level string, format string, args ...interface{})
}

// LayerSelector manages the state machine for one (receiver, sender) pair.
type LayerSelector struct {
	mu           sync.Mutex
	receiverID   int
	senderID     int
	currentLayer int
	maxLayer     int // max layer the receiver requested
	state        selectorState
	callbacks    LayerSelectorCallbacks

	// Probing state
	probeTarget    int       // layer we're probing toward
	probeStartTime time.Time
	probeRtxSeq    uint16 // incrementing RTX sequence number for padding

	// Grace-down state
	graceStartTime time.Time

	// Cooldown
	lastSwitchTime time.Time

	// Control
	stopCh chan struct{}
	done   chan struct{}
}

// NewLayerSelector creates and starts a new LayerSelector.
// initialLayer is the layer to start forwarding (typically = requestedLayer).
func NewLayerSelector(receiverID, senderID, initialLayer, maxLayer int, cb LayerSelectorCallbacks) *LayerSelector {
	ls := &LayerSelector{
		receiverID:   receiverID,
		senderID:     senderID,
		currentLayer: initialLayer,
		maxLayer:     maxLayer,
		state:        stateStable,
		callbacks:    cb,
		stopCh:       make(chan struct{}),
		done:         make(chan struct{}),
	}
	go ls.run()
	return ls
}

// Stop terminates the selector's tick loop.
func (ls *LayerSelector) Stop() {
	close(ls.stopCh)
	<-ls.done
}

// SetMaxLayer updates the maximum layer the receiver wants (from ReceiverVideoConstraints).
func (ls *LayerSelector) SetMaxLayer(maxLayer int) {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	ls.maxLayer = maxLayer
	// If current layer exceeds new max, downswitch immediately.
	if ls.currentLayer > maxLayer {
		ls.switchLayer(maxLayer)
	}
}

// OnMaxActiveLayerIncreased is called when the sender starts producing a
// higher simulcast layer than previously observed. If the BW estimate is
// stale (no REMB arriving — common when clients use transport-cc exclusively
// and the SFU hasn't generated REMB), upshift immediately up to maxLayer so
// the receiver gets the best available layer. When REMB is fresh, the state
// machine is in charge and this is a no-op.
func (ls *LayerSelector) OnMaxActiveLayerIncreased(maxActive int) {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	if ls.callbacks.GetEffectiveBW() >= 0 {
		// BW estimate available — state machine decides.
		return
	}
	target := maxActive
	if target > ls.maxLayer {
		target = ls.maxLayer
	}
	if target > ls.currentLayer {
		ls.switchLayer(target)
	}
}

// CurrentLayer returns the currently selected layer.
func (ls *LayerSelector) CurrentLayer() int {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	return ls.currentLayer
}

func (ls *LayerSelector) run() {
	defer close(ls.done)
	ticker := time.NewTicker(tickInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ls.stopCh:
			return
		case <-ticker.C:
			ls.tick()
		}
	}
}

func (ls *LayerSelector) tick() {
	ls.mu.Lock()
	defer ls.mu.Unlock()

	effectiveBW := ls.callbacks.GetEffectiveBW()
	if effectiveBW < 0 {
		// Stale estimate — do nothing.
		return
	}

	switch ls.state {
	case stateStable:
		ls.tickStable(effectiveBW)
	case stateProbingUp:
		ls.tickProbingUp(effectiveBW)
	case stateGraceDown:
		ls.tickGraceDown(effectiveBW)
	}
}

func (ls *LayerSelector) tickStable(effectiveBW float64) {
	// Check for upswitch opportunity.
	nextLayer := ls.currentLayer + 1
	if nextLayer <= ls.maxLayer && nextLayer <= 2 {
		if !ls.inCooldown() && effectiveBW > layerBitrates[nextLayer].UpThresh {
			ls.state = stateProbingUp
			ls.probeTarget = nextLayer
			ls.probeStartTime = time.Now()
			ls.callbacks.Log("INFO", "Participant %d<-%d: STABLE->PROBING_UP (BW=%.0fkbps, target=layer%d@%.0fkbps)",
				ls.receiverID, ls.senderID, effectiveBW/1000, nextLayer, layerBitrates[nextLayer].UpThresh/1000)
			return
		}
	}

	// Check for downswitch need.
	if ls.currentLayer > 0 {
		if effectiveBW < layerBitrates[ls.currentLayer].DownThresh {
			ls.state = stateGraceDown
			ls.graceStartTime = time.Now()
			ls.callbacks.Log("INFO", "Participant %d<-%d: STABLE->GRACE_DOWN (BW=%.0fkbps, thresh=%.0fkbps)",
				ls.receiverID, ls.senderID, effectiveBW/1000, layerBitrates[ls.currentLayer].DownThresh/1000)
			return
		}
	}
}

func (ls *LayerSelector) tickProbingUp(effectiveBW float64) {
	elapsed := time.Since(ls.probeStartTime)

	// Abort if bandwidth dropped below current layer's nominal bitrate.
	if effectiveBW < layerBitrates[ls.currentLayer].Nominal {
		ls.state = stateStable
		ls.lastSwitchTime = time.Now() // enter cooldown
		ls.callbacks.Log("INFO", "Participant %d<-%d: PROBING_UP->STABLE (abort, BW=%.0fkbps < nominal=%.0fkbps)",
			ls.receiverID, ls.senderID, effectiveBW/1000, layerBitrates[ls.currentLayer].Nominal/1000)
		return
	}

	// Probe complete — switch up.
	if elapsed >= probeDuration {
		if effectiveBW > layerBitrates[ls.probeTarget].Nominal {
			ls.callbacks.Log("INFO", "Participant %d<-%d: PROBING_UP->STABLE (success, switching to layer %d)",
				ls.receiverID, ls.senderID, ls.probeTarget)
			ls.switchLayer(ls.probeTarget)
			return
		}
		// BW not sufficient at end of probe — abort.
		ls.state = stateStable
		ls.lastSwitchTime = time.Now()
		ls.callbacks.Log("INFO", "Participant %d<-%d: PROBING_UP->STABLE (probe done but BW=%.0fkbps insufficient)",
			ls.receiverID, ls.senderID, effectiveBW/1000)
		return
	}

	// Send RTX padding during probe.
	ls.sendProbePadding(elapsed)
}

func (ls *LayerSelector) tickGraceDown(effectiveBW float64) {
	// If bandwidth recovered, cancel grace period.
	if effectiveBW >= layerBitrates[ls.currentLayer].DownThresh {
		ls.state = stateStable
		ls.callbacks.Log("INFO", "Participant %d<-%d: GRACE_DOWN->STABLE (recovered, BW=%.0fkbps)",
			ls.receiverID, ls.senderID, effectiveBW/1000)
		return
	}

	// Grace period expired — downswitch.
	if time.Since(ls.graceStartTime) >= graceDownTimeout {
		targetLayer := ls.currentLayer - 1
		if targetLayer < 0 {
			targetLayer = 0
		}
		ls.callbacks.Log("INFO", "Participant %d<-%d: GRACE_DOWN->STABLE (downswitch to layer %d)",
			ls.receiverID, ls.senderID, targetLayer)
		ls.switchLayer(targetLayer)
	}
}

func (ls *LayerSelector) switchLayer(newLayer int) {
	oldLayer := ls.currentLayer
	ls.currentLayer = newLayer
	ls.state = stateStable
	ls.lastSwitchTime = time.Now()
	ls.callbacks.SetSelectedLayer(newLayer)

	// Request keyframe at the new layer.
	layers := ls.callbacks.GetSenderVideoLayers()
	if newLayer < len(layers) {
		ls.callbacks.SendPLI(layers[newLayer].SSRC)
		ls.callbacks.Log("INFO", "Participant %d<-%d: switched layer %d->%d (PLI sent for SSRC=%d)",
			ls.receiverID, ls.senderID, oldLayer, newLayer, layers[newLayer].SSRC)
	}
}

func (ls *LayerSelector) inCooldown() bool {
	return !ls.lastSwitchTime.IsZero() && time.Since(ls.lastSwitchTime) < cooldownDuration
}

func (ls *LayerSelector) sendProbePadding(elapsed time.Duration) {
	// Calculate target padding rate: ramp from 0 to gap over probeDuration.
	gap := layerBitrates[ls.probeTarget].Nominal - layerBitrates[ls.currentLayer].Nominal
	progress := float64(elapsed) / float64(probeDuration)
	targetBps := gap * progress

	// How many bytes to send in this 100ms tick.
	bytesPerTick := targetBps / 8 / (float64(time.Second) / float64(tickInterval))

	rtxBuf := ls.callbacks.GetRtxBuffer()
	if rtxBuf == nil {
		return
	}

	// Pull packets from the ring buffer to fill the target bytes.
	entries := rtxBuf.Get(20) // enough for one tick
	if len(entries) == 0 {
		return
	}

	layers := ls.callbacks.GetSenderVideoLayers()
	if ls.currentLayer >= len(layers) {
		return
	}
	rtxSSRC := layers[ls.currentLayer].FidSSRC
	if rtxSSRC == 0 {
		return
	}

	var sentBytes float64
	entryIdx := 0
	for sentBytes < bytesPerTick && entryIdx < len(entries) {
		entry := entries[entryIdx]
		entryIdx++
		rtxPayload := rtxEncapsulate(entry.Payload, entry.SeqNum)
		ls.probeRtxSeq++
		ls.callbacks.SendRtxPadding(rtxPayload, rtxSSRC, ls.probeRtxSeq, entry.Timestamp)
		sentBytes += float64(len(rtxPayload))
	}
}
