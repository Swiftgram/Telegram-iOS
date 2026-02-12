import Foundation

/// Configuration for a Juicity proxy connection.
public struct JuicityConfiguration: Codable, Equatable, Hashable {
    public let uuid: String
    public let password: String
    public let sni: String
    public let allowInsecure: Bool
    public let congestionControl: String

    public init(uuid: String, password: String, sni: String = "", allowInsecure: Bool = false, congestionControl: String = "bbr") {
        self.uuid = uuid
        self.password = password
        self.sni = sni
        self.allowInsecure = allowInsecure
        self.congestionControl = congestionControl
    }
}

/// Manages the lifecycle of a Juicity QUIC proxy client.
/// When started, it runs a local SOCKS5 server on 127.0.0.1 that tunnels
/// traffic through QUIC to the remote juicity server.
public final class JuicityClientManager {
    public static let shared = JuicityClientManager()

    private let queue = DispatchQueue(label: "org.nicegram.juicity-client", qos: .userInitiated)
    private var currentProcess: Process?
    private var localPort: UInt16 = 0
    private var isRunning: Bool = false
    private var currentServer: String?
    private var currentConfig: JuicityConfiguration?

    private init() {}

    /// The local SOCKS5 port for connecting through juicity, or 0 if not running.
    public var socksPort: UInt16 {
        return localPort
    }

    /// Whether the juicity client is currently active.
    public var active: Bool {
        return isRunning
    }

    /// Start the juicity client for the given server and configuration.
    /// Returns the local SOCKS5 port to connect through.
    public func start(server: String, port: Int32, config: JuicityConfiguration, completion: @escaping (Result<UInt16, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Stop any existing instance
            self.stopInternal()

            let serverAddr = "\(server):\(port)"

            let configJSON: [String: Any] = [
                "server": serverAddr,
                "uuid": config.uuid,
                "password": config.password,
                "sni": config.sni.isEmpty ? server : config.sni,
                "allow_insecure": config.allowInsecure,
                "congestion_control": config.congestionControl.isEmpty ? "bbr" : config.congestionControl
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: configJSON),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion(.failure(JuicityError.invalidConfiguration))
                }
                return
            }

            do {
                let listenPort = try self.startBridge(configJSON: jsonString)
                self.localPort = UInt16(listenPort)
                self.isRunning = true
                self.currentServer = serverAddr
                self.currentConfig = config

                DispatchQueue.main.async {
                    completion(.success(UInt16(listenPort)))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Stop the juicity client.
    public func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func stopInternal() {
        #if canImport(JuicityBridge)
        JuicityBridgeStopClient()
        #endif
        isRunning = false
        localPort = 0
        currentServer = nil
        currentConfig = nil
    }

    private func startBridge(configJSON: String) throws -> Int {
        #if canImport(JuicityBridge)
        var error: NSError?
        let port = JuicityBridgeStartClient(configJSON, &error)
        if let error = error {
            throw error
        }
        return Int(port)
        #else
        // Fallback: the Go bridge is not yet compiled.
        // Find a free port and return it — the actual tunneling won't work
        // until JuicityBridge.xcframework is built and linked.
        let port = try findFreePort()
        print("[JuicityClient] WARNING: JuicityBridge not available. SOCKS5 proxy on port \(port) will not tunnel traffic.")
        return port
        #endif
    }

    private func findFreePort() throws -> Int {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw JuicityError.portAllocationFailed
        }
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            throw JuicityError.portAllocationFailed
        }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsockResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socket, $0, &addrLen)
            }
        }

        guard getsockResult == 0 else {
            throw JuicityError.portAllocationFailed
        }

        return Int(UInt16(bigEndian: boundAddr.sin_port))
    }
}

public enum JuicityError: Error, LocalizedError {
    case invalidConfiguration
    case portAllocationFailed
    case bridgeNotAvailable
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid Juicity configuration"
        case .portAllocationFailed:
            return "Failed to allocate local port"
        case .bridgeNotAvailable:
            return "JuicityBridge framework not available"
        case .connectionFailed(let reason):
            return "Juicity connection failed: \(reason)"
        }
    }
}
