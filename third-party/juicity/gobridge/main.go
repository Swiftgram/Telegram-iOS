// Package juicitybridge provides a gomobile-compatible bridge to the juicity client.
// Build with: gomobile bind -target=ios -o JuicityBridge.xcframework ./gobridge
package juicitybridge

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"sync"
)

// ClientConfig holds the juicity client configuration.
type ClientConfig struct {
	Server            string `json:"server"`
	UUID              string `json:"uuid"`
	Password          string `json:"password"`
	SNI               string `json:"sni,omitempty"`
	AllowInsecure     bool   `json:"allow_insecure"`
	CongestionControl string `json:"congestion_control,omitempty"`
	ListenPort        int    `json:"listen_port,omitempty"`
}

// Client manages a running juicity client instance.
type Client struct {
	mu         sync.Mutex
	cancel     context.CancelFunc
	listenPort int
	running    bool
}

var (
	globalClient *Client
	clientMu     sync.Mutex
)

// StartClient starts the juicity client with the given JSON configuration.
// Returns the local SOCKS5 listen port on success.
func StartClient(configJSON string) (int, error) {
	clientMu.Lock()
	defer clientMu.Unlock()

	if globalClient != nil && globalClient.running {
		return 0, fmt.Errorf("client already running")
	}

	var config ClientConfig
	if err := json.Unmarshal([]byte(configJSON), &config); err != nil {
		return 0, fmt.Errorf("invalid config: %w", err)
	}

	if config.Server == "" || config.UUID == "" || config.Password == "" {
		return 0, fmt.Errorf("server, uuid, and password are required")
	}

	if config.CongestionControl == "" {
		config.CongestionControl = "bbr"
	}

	listenPort := config.ListenPort
	if listenPort == 0 {
		// Find a free port
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return 0, fmt.Errorf("failed to find free port: %w", err)
		}
		listenPort = listener.Addr().(*net.TCPAddr).Port
		listener.Close()
	}

	ctx, cancel := context.WithCancel(context.Background())

	client := &Client{
		cancel:     cancel,
		listenPort: listenPort,
		running:    true,
	}

	// Start the juicity client in a goroutine.
	// This calls into the juicity library to create a QUIC tunnel
	// and expose a local SOCKS5 proxy on listenPort.
	go func() {
		listenAddr := fmt.Sprintf("127.0.0.1:%d", listenPort)
		err := runJuicityClient(ctx, config.Server, config.UUID, config.Password,
			config.SNI, config.AllowInsecure, config.CongestionControl, listenAddr)
		if err != nil {
			fmt.Printf("juicity client stopped: %v\n", err)
		}
		client.mu.Lock()
		client.running = false
		client.mu.Unlock()
	}()

	globalClient = client
	return listenPort, nil
}

// StopClient stops the running juicity client.
func StopClient() {
	clientMu.Lock()
	defer clientMu.Unlock()

	if globalClient != nil {
		if globalClient.cancel != nil {
			globalClient.cancel()
		}
		globalClient.running = false
		globalClient = nil
	}
}

// IsRunning returns true if the juicity client is currently active.
func IsRunning() bool {
	clientMu.Lock()
	defer clientMu.Unlock()
	return globalClient != nil && globalClient.running
}

// GetListenPort returns the current local SOCKS5 listen port, or 0 if not running.
func GetListenPort() int {
	clientMu.Lock()
	defer clientMu.Unlock()
	if globalClient != nil && globalClient.running {
		return globalClient.listenPort
	}
	return 0
}
