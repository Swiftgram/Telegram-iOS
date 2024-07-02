import Foundation

func urlSafeDecode(_ urlencoded: String) -> String {
    return urlencoded.replacingOccurrences(of: "+", with: "%20").removingPercentEncoding ?? urlencoded
}

public func urlParseHashParams(_ locationHash: String) -> [String: String?] {
    var params = [String: String?]()
    var localLocationHash = locationHash.removePrefix("#") // Remove leading '#'

    if localLocationHash.isEmpty {
        return params
    }
    
    if !localLocationHash.contains("=") && !localLocationHash.contains("?") {
        params["_path"] = urlSafeDecode(localLocationHash)
        return params
    }

    let qIndex = localLocationHash.firstIndex(of: "?")
    if let qIndex = qIndex {
        let pathParam = String(localLocationHash[..<qIndex])
        params["_path"] = urlSafeDecode(pathParam)
        localLocationHash = String(localLocationHash[localLocationHash.index(after: qIndex)...])
    }

    let queryParams = urlParseQueryString(localLocationHash)
    for (k, v) in queryParams {
        params[k] = v
    }

    return params
}

func urlParseQueryString(_ queryString: String) -> [String: String?] {
    var params = [String: String?]()
    
    if queryString.isEmpty {
        return params
    }
    
    let queryStringParams = queryString.split(separator: "&")
    for param in queryStringParams {
        let parts = param.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let paramName = urlSafeDecode(String(parts[0]))
        let paramValue = parts.count > 1 ? urlSafeDecode(String(parts[1])) : nil
        params[paramName] = paramValue
    }
    
    return params
}

extension String {
    func removePrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}
