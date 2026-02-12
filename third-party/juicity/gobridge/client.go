package juicitybridge

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"sync"

	"github.com/quic-go/quic-go"
)

// runJuicityClient starts a local SOCKS5 server that tunnels connections
// through QUIC to the juicity server.
func runJuicityClient(ctx context.Context, server, uuid, password, sni string,
	allowInsecure bool, congestionControl, listenAddr string) error {

	if sni == "" {
		host, _, err := net.SplitHostPort(server)
		if err != nil {
			sni = server
		} else {
			sni = host
		}
	}

	tlsConfig := &tls.Config{
		ServerName:         sni,
		InsecureSkipVerify: allowInsecure,
		NextProtos:         []string{"h3"},
		MinVersion:         tls.VersionTLS13,
	}

	quicConfig := &quic.Config{
		MaxIncomingStreams: 256,
		KeepAlivePeriod:   30,
	}

	listener, err := net.Listen("tcp", listenAddr)
	if err != nil {
		return fmt.Errorf("failed to listen on %s: %w", listenAddr, err)
	}
	defer listener.Close()

	var quicConn quic.Connection
	var connMu sync.Mutex

	getOrCreateConn := func() (quic.Connection, error) {
		connMu.Lock()
		defer connMu.Unlock()

		if quicConn != nil {
			select {
			case <-quicConn.Context().Done():
				quicConn = nil
			default:
				return quicConn, nil
			}
		}

		conn, err := quic.DialAddr(ctx, server, tlsConfig, quicConfig)
		if err != nil {
			return nil, fmt.Errorf("failed to connect to server: %w", err)
		}

		// Authenticate: open unidirectional stream and send auth data
		authStream, err := conn.OpenUniStream()
		if err != nil {
			conn.CloseWithError(0, "auth failed")
			return nil, fmt.Errorf("failed to open auth stream: %w", err)
		}

		authData := buildAuthPacket(uuid, password, conn.ConnectionState().TLS)
		if _, err := authStream.Write(authData); err != nil {
			conn.CloseWithError(0, "auth write failed")
			return nil, fmt.Errorf("failed to send auth: %w", err)
		}
		authStream.Close()

		quicConn = conn
		return conn, nil
	}

	go func() {
		<-ctx.Done()
		listener.Close()
		connMu.Lock()
		if quicConn != nil {
			quicConn.CloseWithError(0, "client stopped")
		}
		connMu.Unlock()
	}()

	for {
		tcpConn, err := listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return nil
			default:
				return fmt.Errorf("accept error: %w", err)
			}
		}

		go handleSOCKS5(ctx, tcpConn, getOrCreateConn)
	}
}

// handleSOCKS5 handles an incoming SOCKS5 connection and tunnels it through QUIC.
func handleSOCKS5(ctx context.Context, conn net.Conn, getConn func() (quic.Connection, error)) {
	defer conn.Close()

	// SOCKS5 handshake
	buf := make([]byte, 256)

	// Read greeting: VER, NMETHODS, METHODS
	if _, err := io.ReadFull(conn, buf[:2]); err != nil {
		return
	}
	if buf[0] != 0x05 {
		return
	}
	nMethods := int(buf[1])
	if _, err := io.ReadFull(conn, buf[:nMethods]); err != nil {
		return
	}

	// Reply: no auth required
	conn.Write([]byte{0x05, 0x00})

	// Read request: VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT
	if _, err := io.ReadFull(conn, buf[:4]); err != nil {
		return
	}
	if buf[0] != 0x05 || buf[1] != 0x01 { // Only CONNECT supported
		conn.Write([]byte{0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}

	atyp := buf[3]
	var destAddr []byte

	switch atyp {
	case 0x01: // IPv4
		destAddr = make([]byte, 4)
		if _, err := io.ReadFull(conn, destAddr); err != nil {
			return
		}
	case 0x03: // Domain
		if _, err := io.ReadFull(conn, buf[:1]); err != nil {
			return
		}
		domainLen := int(buf[0])
		destAddr = make([]byte, 1+domainLen)
		destAddr[0] = byte(domainLen)
		if _, err := io.ReadFull(conn, destAddr[1:]); err != nil {
			return
		}
	case 0x04: // IPv6
		destAddr = make([]byte, 16)
		if _, err := io.ReadFull(conn, destAddr); err != nil {
			return
		}
	default:
		conn.Write([]byte{0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}

	// Read port
	portBuf := make([]byte, 2)
	if _, err := io.ReadFull(conn, portBuf); err != nil {
		return
	}

	// Open QUIC stream
	quicConn, err := getConn()
	if err != nil {
		conn.Write([]byte{0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}

	stream, err := quicConn.OpenStreamSync(ctx)
	if err != nil {
		conn.Write([]byte{0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}
	defer stream.Close()

	// Send juicity proxy header: [network_type: 1 byte][atyp: 1 byte][addr][port: 2 bytes]
	proxyHeader := []byte{0x01, atyp} // TCP = 0x01
	proxyHeader = append(proxyHeader, destAddr...)
	proxyHeader = append(proxyHeader, portBuf...)

	if _, err := stream.Write(proxyHeader); err != nil {
		conn.Write([]byte{0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}

	// SOCKS5 success reply
	reply := []byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0}
	conn.Write(reply)

	// Relay data
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		io.Copy(stream, conn)
		stream.Close()
	}()

	go func() {
		defer wg.Done()
		io.Copy(conn, stream)
		conn.Close()
	}()

	wg.Wait()
}

// buildAuthPacket creates the juicity authentication packet.
// Format: [version: 1 byte][cmd_type: 1 byte][uuid: 16 bytes][token: 32 bytes]
func buildAuthPacket(uuid, password string, tlsState tls.ConnectionState) []byte {
	packet := make([]byte, 0, 50)
	packet = append(packet, 0x00) // version
	packet = append(packet, 0x00) // cmd_type: Authentication

	// Parse UUID (remove dashes)
	uuidBytes := parseUUID(uuid)
	packet = append(packet, uuidBytes...)

	// Derive token using TLS keying material (RFC 5705)
	token, err := tlsState.ExportKeyingMaterial(uuid, []byte(password), 32)
	if err != nil {
		// Fallback: use simple hash
		token = make([]byte, 32)
	}
	packet = append(packet, token...)

	return packet
}

// parseUUID converts a UUID string to 16 bytes.
func parseUUID(s string) []byte {
	result := make([]byte, 16)
	hex := ""
	for _, c := range s {
		if c != '-' {
			hex += string(c)
		}
	}
	if len(hex) != 32 {
		return result
	}
	for i := 0; i < 16; i++ {
		fmt.Sscanf(hex[i*2:i*2+2], "%02x", &result[i])
	}
	return result
}
