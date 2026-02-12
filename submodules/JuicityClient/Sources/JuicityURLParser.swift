import Foundation

/// Parsed result from a juicity:// URL.
public struct JuicityParsedURL {
    public let host: String
    public let port: Int32
    public let uuid: String
    public let password: String
    public let sni: String
    public let allowInsecure: Bool
    public let congestionControl: String
}

/// Parses juicity:// share URLs.
///
/// Format: juicity://uuid:password@host:port?congestion_control=bbr&sni=example.com&allow_insecure=0
public func parseJuicityURL(_ urlString: String) -> JuicityParsedURL? {
    guard urlString.lowercased().hasPrefix("juicity://") else {
        return nil
    }

    // Replace juicity:// with http:// for URL parsing
    let httpURL = "http://" + String(urlString.dropFirst("juicity://".count))

    guard let components = URLComponents(string: httpURL) else {
        return nil
    }

    guard let host = components.host, !host.isEmpty else {
        return nil
    }

    guard let port = components.port, port > 0, port <= 65535 else {
        return nil
    }

    // UUID is in the user field, password in the password field
    guard let uuid = components.user, !uuid.isEmpty else {
        return nil
    }

    guard let password = components.password, !password.isEmpty else {
        return nil
    }

    var sni = ""
    var allowInsecure = false
    var congestionControl = "bbr"

    if let queryItems = components.queryItems {
        for item in queryItems {
            switch item.name {
            case "sni":
                sni = item.value ?? ""
            case "allow_insecure":
                allowInsecure = item.value == "1" || item.value?.lowercased() == "true"
            case "congestion_control":
                congestionControl = item.value ?? "bbr"
            default:
                break
            }
        }
    }

    return JuicityParsedURL(
        host: host,
        port: Int32(port),
        uuid: uuid,
        password: password,
        sni: sni,
        allowInsecure: allowInsecure,
        congestionControl: congestionControl
    )
}

/// Generates a juicity:// share URL from proxy settings.
public func generateJuicityURL(host: String, port: Int32, uuid: String, password: String,
                                sni: String = "", allowInsecure: Bool = false,
                                congestionControl: String = "bbr") -> String {
    var url = "juicity://\(uuid):\(password)@\(host):\(port)"

    var queryParts: [String] = []
    if !congestionControl.isEmpty && congestionControl != "bbr" {
        queryParts.append("congestion_control=\(congestionControl)")
    }
    if !sni.isEmpty {
        queryParts.append("sni=\(sni.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sni)")
    }
    if allowInsecure {
        queryParts.append("allow_insecure=1")
    }

    if !queryParts.isEmpty {
        url += "?" + queryParts.joined(separator: "&")
    }

    return url
}
