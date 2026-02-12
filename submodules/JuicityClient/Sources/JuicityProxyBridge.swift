import Foundation

/// Bridges the Juicity client with the Telegram networking layer.
/// When a Juicity proxy is activated, this bridge starts the local SOCKS5 proxy
/// and provides the local address/port that MTProto should connect through.
public final class JuicityProxyBridge {
    public static let shared = JuicityProxyBridge()

    private let manager = JuicityClientManager.shared
    private let queue = DispatchQueue(label: "org.nicegram.juicity-bridge")
    private var activeServerKey: String?

    private init() {}

    /// Activates a Juicity proxy for the given server settings.
    /// On success, calls the completion with the local SOCKS5 host ("127.0.0.1") and port.
    public func activate(host: String, port: Int32, uuid: String, password: String,
                         sni: String, allowInsecure: Bool, congestionControl: String,
                         completion: @escaping (String, UInt16) -> Void,
                         onError: @escaping (Error) -> Void) {
        let serverKey = "\(host):\(port):\(uuid)"

        queue.async { [weak self] in
            guard let self = self else { return }

            // If already running for the same server, return existing port
            if self.activeServerKey == serverKey, self.manager.active {
                let socksPort = self.manager.socksPort
                if socksPort > 0 {
                    DispatchQueue.main.async {
                        completion("127.0.0.1", socksPort)
                    }
                    return
                }
            }

            let config = JuicityConfiguration(
                uuid: uuid,
                password: password,
                sni: sni,
                allowInsecure: allowInsecure,
                congestionControl: congestionControl
            )

            self.activeServerKey = serverKey

            self.manager.start(server: host, port: port, config: config) { result in
                switch result {
                case .success(let localPort):
                    completion("127.0.0.1", localPort)
                case .failure(let error):
                    onError(error)
                }
            }
        }
    }

    /// Deactivates the running Juicity proxy.
    public func deactivate() {
        queue.async { [weak self] in
            self?.manager.stop()
            self?.activeServerKey = nil
        }
    }

    /// Whether a Juicity proxy is currently active.
    public var isActive: Bool {
        return manager.active
    }

    /// The current local SOCKS5 port, or 0 if not active.
    public var currentLocalPort: UInt16 {
        return manager.socksPort
    }
}
