import Foundation

public func sgActionRequestHandlerSanitizer(_ url: URL) -> URL {
    var url = url
    if let scheme = url.scheme {
        let openInPrefix = "\(scheme)://parseurl?url="
        let urlString = url.absoluteString
        if urlString.hasPrefix(openInPrefix) {
            if let unwrappedUrlString = String(urlString.dropFirst(openInPrefix.count)).removingPercentEncoding, let newUrl = URL(string: unwrappedUrlString) {
                url = newUrl
            }
        }
    }
    return url
}
