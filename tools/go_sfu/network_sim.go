package main

import (
	"math/rand"
	"sync"
	"time"
)

// NetworkSimulator models a uni-directional network pipe with delay, jitter,
// packet loss, and bandwidth cap (token bucket).
type NetworkSimulator struct {
	mu           sync.Mutex
	delayMs      int
	jitterMs     int
	dropRate     float64
	bandwidthBps int64

	// Token bucket for bandwidth cap.
	tokens       float64 // available tokens (bits)
	maxTokens    float64 // max tokens = 200ms worth of bandwidth
	lastRefill   time.Time
	rng          *rand.Rand

	closed bool
}

// NewNetworkSimulator creates a simulator with no simulation (passthrough).
func NewNetworkSimulator() *NetworkSimulator {
	return &NetworkSimulator{
		lastRefill: time.Now(),
		rng:        rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

// SetParams reconfigures the simulator at runtime. Thread-safe.
func (ns *NetworkSimulator) SetParams(delayMs, jitterMs int, dropRate float64, bandwidthBps int64) {
	ns.mu.Lock()
	defer ns.mu.Unlock()
	ns.delayMs = delayMs
	ns.jitterMs = jitterMs
	ns.dropRate = dropRate
	ns.bandwidthBps = bandwidthBps
	if bandwidthBps > 0 {
		ns.maxTokens = float64(bandwidthBps) * 0.2 // 200ms buffer
		if ns.tokens > ns.maxTokens {
			ns.tokens = ns.maxTokens
		}
	} else {
		ns.maxTokens = 0
		ns.tokens = 0
	}
}

// Send processes a packet through the simulator. deliverFn is called
// (possibly asynchronously) after simulation. The packet bytes are copied
// if delivery is deferred.
func (ns *NetworkSimulator) Send(pkt []byte, deliverFn func([]byte)) {
	ns.mu.Lock()
	if ns.closed {
		ns.mu.Unlock()
		return
	}

	// Drop check.
	if ns.dropRate > 0 && ns.rng.Float64() < ns.dropRate {
		ns.mu.Unlock()
		return
	}

	// Bandwidth cap: token bucket.
	if ns.bandwidthBps > 0 {
		ns.refillTokens()
		cost := float64(len(pkt)) * 8
		if ns.tokens < cost {
			// Queue full / no tokens — tail drop.
			ns.mu.Unlock()
			return
		}
		ns.tokens -= cost
	}

	// Calculate delay.
	delayMs := ns.delayMs
	if ns.jitterMs > 0 {
		delayMs += ns.rng.Intn(2*ns.jitterMs+1) - ns.jitterMs
		if delayMs < 0 {
			delayMs = 0
		}
	}
	ns.mu.Unlock()

	if delayMs == 0 {
		deliverFn(pkt)
		return
	}

	// Copy packet for deferred delivery.
	pktCopy := make([]byte, len(pkt))
	copy(pktCopy, pkt)
	time.AfterFunc(time.Duration(delayMs)*time.Millisecond, func() {
		deliverFn(pktCopy)
	})
}

// Close stops the simulator. Pending delayed packets may still fire.
func (ns *NetworkSimulator) Close() {
	ns.mu.Lock()
	ns.closed = true
	ns.mu.Unlock()
}

// refillTokens adds tokens based on elapsed time. Must be called with mu held.
func (ns *NetworkSimulator) refillTokens() {
	now := time.Now()
	elapsed := now.Sub(ns.lastRefill).Seconds()
	ns.lastRefill = now
	ns.tokens += float64(ns.bandwidthBps) * elapsed
	if ns.tokens > ns.maxTokens {
		ns.tokens = ns.maxTokens
	}
}

// IsPassthrough returns true if no simulation is configured.
func (ns *NetworkSimulator) IsPassthrough() bool {
	ns.mu.Lock()
	defer ns.mu.Unlock()
	return ns.delayMs == 0 && ns.jitterMs == 0 && ns.dropRate == 0 && ns.bandwidthBps == 0
}
