import Foundation

// Assuming NGLogging and AppBundle are custom modules, they are imported here.
import SGLogging
import AppBundle


public let SGFallbackLocale = "en"

public class SGLocalizationManager {
    
    public static let shared = SGLocalizationManager()
    
    private let appBundle: Bundle
    private var localizations: [String: [String: String]] = [:]
    private var webLocalizations: [String: [String: String]] = [:]
    private let fallbackMappings: [String: String] = [
        // "from": "to"
        "zh-hant": "zh-hans",
        "be": "ru",
        "nb": "no",
        "ckb": "ku",
        "sdh": "ku"
    ]
    
    private init(fetchLocale: String = SGFallbackLocale) {
        self.appBundle = getAppBundle()
        // Iterating over all the app languages and loading SGLocalizable.strings
        self.appBundle.localizations.forEach { locale in
            if locale != "Base" {
                localizations[locale] = loadLocalDictionary(for: locale)
            }
        }
        // Downloading one specific locale
        self.downloadLocale(fetchLocale)
    }
    
    public func localizedString(_ key: String, _ locale: String = SGFallbackLocale, args: CVarArg...) -> String {
        let sanitizedLocale = self.sanitizeLocale(locale)
        
        if let localizedString = findLocalizedString(forKey: key, inLocale: sanitizedLocale) {
            if args.isEmpty {
                return String(format: localizedString)
            } else {
                return String(format: localizedString, arguments: args)
            }
        }
        
        SGLogger.shared.log("Strings", "Missing string for key: \(key) in locale: \(locale)")
        return key
    }
    
    private func loadLocalDictionary(for locale: String) -> [String: String] {
        guard let path = self.appBundle.path(forResource: "SGLocalizable", ofType: "strings", inDirectory: nil, forLocalization: locale) else {
            // SGLogger.shared.log("Localization", "Unable to find path for locale: \(locale)")
            return [:]
        }

        guard let dictionary = NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: String] else {
            // SGLogger.shared.log("Localization", "Unable to load dictionary for locale: \(locale)")
            return [:]
        }

        return dictionary
    }
    
    public func downloadLocale(_ locale: String) {
        let sanitizedLocale = self.sanitizeLocale(locale)
        guard let url = URL(string: self.getStringsUrl(for: sanitizedLocale)) else {
            SGLogger.shared.log("Strings", "Invalid URL for locale: \(sanitizedLocale)")
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            if let localeDict = NSDictionary(contentsOf: url) as? [String: String] {
                DispatchQueue.main.async {
                    self.webLocalizations[sanitizedLocale] = localeDict
                    SGLogger.shared.log("Strings", "Successfully downloaded locale \(sanitizedLocale)")
                }
            } else {
                SGLogger.shared.log("Strings", "Failed to download \(sanitizedLocale)")
            }
        }
    }
    
    private func sanitizeLocale(_ locale: String) -> String {
        var sanitizedLocale = locale
        let rawSuffix = "-raw"
        if locale.hasSuffix(rawSuffix) {
            sanitizedLocale = String(locale.dropLast(rawSuffix.count))
        }

        if sanitizedLocale == "pt-br" {
            sanitizedLocale = "pt"
        } else if sanitizedLocale == "nb" {
            sanitizedLocale = "no"
        }

        return sanitizedLocale
    }

    private func findLocalizedString(forKey key: String, inLocale locale: String) -> String? {
        if let string = self.webLocalizations[locale]?[key], !string.isEmpty {
            return string
        }
        if let string = self.localizations[locale]?[key], !string.isEmpty {
            return string
        }
        if let fallbackLocale = self.fallbackMappings[locale] {
            return self.findLocalizedString(forKey: key, inLocale: fallbackLocale)
        }
        return self.localizations[SGFallbackLocale]?[key]
    }

    private func getStringsUrl(for locale: String) -> String {
        return "https://raw.githubusercontent.com/Swiftgram/Telegram-iOS/master/Swiftgram/SGStrings/Strings/\(locale).lproj/SGLocalizable.strings"
    }

}

public let i18n = SGLocalizationManager.shared.localizedString
