package main

import (
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// mockCallbacks is a test harness for driving the LayerSelector. BW is
// atomic so the selector's run() goroutine can read while the test writes.
type mockCallbacks struct {
	bw            atomic.Int64 // current effective bandwidth in bps; negative = stale
	layers        []SimulcastLayer
	selectedLayer atomic.Int32
	pliCount      atomic.Int32
	probePaddings atomic.Int32

	logMu  sync.Mutex
	logBuf []string
}

func newMockCallbacks(layers []SimulcastLayer, initialBW float64) *mockCallbacks {
	m := &mockCallbacks{layers: layers}
	m.bw.Store(int64(initialBW))
	m.selectedLayer.Store(-1)
	return m
}

func (m *mockCallbacks) setBW(bps float64) { m.bw.Store(int64(bps)) }

func (m *mockCallbacks) currentSelected() int { return int(m.selectedLayer.Load()) }

func (m *mockCallbacks) toCallbacks() LayerSelectorCallbacks {
	return LayerSelectorCallbacks{
		GetEffectiveBW: func() float64 {
			v := float64(m.bw.Load())
			if v < 0 {
				return -1
			}
			return v
		},
		SetSelectedLayer: func(layer int) {
			m.selectedLayer.Store(int32(layer))
		},
		SendPLI: func(ssrc uint32) {
			m.pliCount.Add(1)
		},
		GetSenderVideoLayers: func() []SimulcastLayer {
			return m.layers
		},
		GetRtxBuffer: func() *RtxRingBuffer {
			return nil // probing padding no-ops without a buffer
		},
		SendRtxPadding: func(rtxPayload []byte, rtxSSRC uint32, seqNum uint16, timestamp uint32) {
			m.probePaddings.Add(1)
		},
		Log: func(level string, format string, args ...interface{}) {
			m.logMu.Lock()
			m.logBuf = append(m.logBuf, fmt.Sprintf("["+level+"] "+format, args...))
			m.logMu.Unlock()
		},
	}
}

// waitForLayer polls the selector's currentLayer up to timeout for a change
// to `want`. Returns true if reached, false on timeout.
func waitForLayer(ls *LayerSelector, want int, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if ls.CurrentLayer() == want {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return false
}

func testLayers() []SimulcastLayer {
	return []SimulcastLayer{
		{SSRC: 1001, FidSSRC: 1002},
		{SSRC: 1003, FidSSRC: 1004},
		{SSRC: 1005, FidSSRC: 1006},
	}
}

// TestLayerSelectorUpswitch verifies L0 -> L1 -> L2 based on rising BW.
//
// Thresholds (from layerBitrates):
//
//	L1 UpThresh = 132 kbps → needs REMB > ~155 kbps (with 0.85 safety factor)
//	L2 UpThresh = 1080 kbps → needs REMB > ~1271 kbps
//
// The selector's state machine enforces a 5s cooldown after each switch, so
// the whole test runs in ~8-10 seconds.
func TestLayerSelectorUpswitch(t *testing.T) {
	m := newMockCallbacks(testLayers(), 200_000) // > L1 UpThresh
	ls := NewLayerSelector(1, 0, 0, 2, m.toCallbacks())
	defer ls.Stop()

	// L0 -> L1: should enter PROBING_UP within 150ms (one tick), then
	// complete the 2s probe and switch to L1.
	if !waitForLayer(ls, 1, 3*time.Second) {
		t.Fatalf("L0->L1 upswitch timed out; currentLayer=%d selected=%d", ls.CurrentLayer(), m.currentSelected())
	}
	if got := m.currentSelected(); got != 1 {
		t.Fatalf("after L1 upswitch, SetSelectedLayer was not called with 1 (got %d)", got)
	}
	if pli := m.pliCount.Load(); pli < 1 {
		t.Fatalf("expected at least 1 PLI on layer switch, got %d", pli)
	}

	// L1 -> L2: raise BW above L2 UpThresh. Wait out the 5s cooldown and
	// then the 2s probe (total ~7-8s).
	m.setBW(1_500_000)
	if !waitForLayer(ls, 2, 10*time.Second) {
		t.Fatalf("L1->L2 upswitch timed out; currentLayer=%d", ls.CurrentLayer())
	}
	if got := m.currentSelected(); got != 2 {
		t.Fatalf("after L2 upswitch, SetSelectedLayer was not called with 2 (got %d)", got)
	}
}

// TestLayerSelectorDownswitch verifies L2 -> L1 -> L0 based on falling BW.
// Starts the selector pre-positioned at L2 by setting its state directly
// via `switchLayer`-equivalent initial-layer argument, then drives BW down.
//
// Thresholds:
//
//	L2 DownThresh = 630 kbps → needs REMB < ~741 kbps
//	L1 DownThresh = 77 kbps  → needs REMB < ~91 kbps
//
// Downswitches are governed by a 500ms grace period, no cooldown, so this
// test runs in ~1.5 seconds.
func TestLayerSelectorDownswitch(t *testing.T) {
	m := newMockCallbacks(testLayers(), 1_500_000) // high BW, at L2
	ls := NewLayerSelector(1, 0, 2, 2, m.toCallbacks())
	defer ls.Stop()

	// Drop BW below L2 downswitch threshold. Effective = 500k * 0.85 = 425k
	// is NOT below 630k effective threshold directly. Use 600k raw so
	// effective = 510k, well below 630k.
	m.setBW(600_000)
	if !waitForLayer(ls, 1, 2*time.Second) {
		t.Fatalf("L2->L1 downswitch timed out; currentLayer=%d", ls.CurrentLayer())
	}
	if got := m.currentSelected(); got != 1 {
		t.Fatalf("after L1 downswitch, SetSelectedLayer was not called with 1 (got %d)", got)
	}

	// Drop below L1 downswitch threshold (77k effective → raw < 91k).
	// Use 50k raw → effective 42k.
	m.setBW(50_000)
	if !waitForLayer(ls, 0, 2*time.Second) {
		t.Fatalf("L1->L0 downswitch timed out; currentLayer=%d", ls.CurrentLayer())
	}
	if got := m.currentSelected(); got != 0 {
		t.Fatalf("after L0 downswitch, SetSelectedLayer was not called with 0 (got %d)", got)
	}
}

// TestLayerSelectorGraceDownRecovery verifies that a transient BW dip that
// recovers within the 500ms grace window does NOT cause a downswitch.
func TestLayerSelectorGraceDownRecovery(t *testing.T) {
	m := newMockCallbacks(testLayers(), 1_500_000)
	ls := NewLayerSelector(1, 0, 2, 2, m.toCallbacks())
	defer ls.Stop()

	// Dip below downthresh, then recover before grace expires.
	m.setBW(500_000) // below L2 downthresh
	time.Sleep(300 * time.Millisecond)
	m.setBW(1_500_000) // recovered
	time.Sleep(500 * time.Millisecond)

	if got := ls.CurrentLayer(); got != 2 {
		t.Fatalf("transient dip should not have downswitched; currentLayer=%d", got)
	}
}

// TestLayerSelectorStaleBW verifies that with no REMB data (BW=-1), the
// state machine does not transition.
func TestLayerSelectorStaleBW(t *testing.T) {
	m := newMockCallbacks(testLayers(), -1) // stale
	ls := NewLayerSelector(1, 0, 1, 2, m.toCallbacks())
	defer ls.Stop()

	time.Sleep(1 * time.Second)
	if got := ls.CurrentLayer(); got != 1 {
		t.Fatalf("stale BW should not trigger a transition; currentLayer=%d", got)
	}
}

// TestLayerSelectorOnMaxActiveLayerIncreasedWhenStale verifies the fallback
// path: when BW is stale (clients don't send REMB), discovery of a higher
// active layer from the sender causes an immediate upswitch.
func TestLayerSelectorOnMaxActiveLayerIncreasedWhenStale(t *testing.T) {
	m := newMockCallbacks(testLayers(), -1)
	ls := NewLayerSelector(1, 0, 1, 2, m.toCallbacks())
	defer ls.Stop()

	// Nothing has happened yet.
	if got := ls.CurrentLayer(); got != 1 {
		t.Fatalf("unexpected initial layer %d", got)
	}

	// Sender starts producing L2. With stale BW, we should upshift
	// immediately up to the receiver's requested maxLayer.
	ls.OnMaxActiveLayerIncreased(2)
	if got := ls.CurrentLayer(); got != 2 {
		t.Fatalf("expected upshift to L2 on maxActive increase with stale BW; got %d", got)
	}
	if got := m.currentSelected(); got != 2 {
		t.Fatalf("SetSelectedLayer should have been called with 2; got %d", got)
	}
}

// TestLayerSelectorOnMaxActiveLayerIncreasedWhenFresh verifies that when BW
// is fresh, OnMaxActiveLayerIncreased is a no-op — the state machine is in
// charge of layer selection.
func TestLayerSelectorOnMaxActiveLayerIncreasedWhenFresh(t *testing.T) {
	m := newMockCallbacks(testLayers(), 200_000) // fresh, enough for L1 only
	ls := NewLayerSelector(1, 0, 1, 2, m.toCallbacks())
	defer ls.Stop()

	ls.OnMaxActiveLayerIncreased(2)
	if got := ls.CurrentLayer(); got != 1 {
		t.Fatalf("fresh BW should leave state machine in charge; current=%d", got)
	}
}

// TestLayerSelectorRespectsMaxLayer verifies that upswitches never exceed
// the receiver's requested maxLayer.
func TestLayerSelectorRespectsMaxLayer(t *testing.T) {
	m := newMockCallbacks(testLayers(), 2_000_000) // way more than needed for L2
	ls := NewLayerSelector(1, 0, 0, 1, m.toCallbacks())
	defer ls.Stop()

	// Wait long enough for an L0->L1 upswitch (~2.2s). Then wait past the
	// cooldown (5s) plus another probe window (2s) to ensure the selector
	// does NOT attempt to probe beyond maxLayer=1.
	if !waitForLayer(ls, 1, 3*time.Second) {
		t.Fatalf("L0->L1 upswitch timed out")
	}
	time.Sleep(8 * time.Second)
	if got := ls.CurrentLayer(); got != 1 {
		t.Fatalf("selector upshifted beyond maxLayer=1; got %d", got)
	}
}
