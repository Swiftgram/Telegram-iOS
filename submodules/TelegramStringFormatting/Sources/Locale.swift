import Foundation
import TelegramPresentationData

private let systemLocaleRegionSuffix: String = {
    let identifier = Locale.current.identifier
    if let range = identifier.range(of: "_") {
        return String(identifier[range.lowerBound...])
    } else {
        return ""
    }
}()

public let usEnglishLocale = Locale(identifier: "en_US")

public func localeWithStrings(_ strings: PresentationStrings) -> Locale {
    var languageCode = strings.baseLanguageCode
    
    // MARK: - Swiftgram fix for locale bugs, like location crash
    if #available(iOS 18, *) {
        let rawSuffix = "-raw"
        if languageCode.hasSuffix(rawSuffix) {
            languageCode = String(languageCode.dropLast(rawSuffix.count))
        }
    }
    
    let code = languageCode + systemLocaleRegionSuffix
    return Locale(identifier: code)
}
