import Foundation

let fallbackBaseBundleId: String = "app.swiftgram.ios"

public func sgAppGroupIdentifier() -> String {
    let baseBundleId: String
    if let bundleId: String = Bundle.main.bundleIdentifier {
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            if let lastDotRange: Range<String.Index> = bundleId.range(of: ".", options: [.backwards]) {
                baseBundleId = String(bundleId[..<lastDotRange.lowerBound])
            } else {
                baseBundleId = fallbackBaseBundleId
            }
        } else {
            baseBundleId = bundleId
        }
    } else {
        baseBundleId = fallbackBaseBundleId
    }
    
    let result: String = "group.\(baseBundleId)"
    
    #if DEBUG
    print("APP_GROUP_IDENTIFIER: \(result)")
    #endif
    
    return result
}