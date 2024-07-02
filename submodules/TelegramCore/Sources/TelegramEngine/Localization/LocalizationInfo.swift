import Foundation
import Postbox
import TelegramApi


extension LocalizationInfo {
    init(apiLanguage: Api.LangPackLanguage) {
        switch apiLanguage {
            case let .langPackLanguage(flags, name, nativeName, langCode, baseLangCode, pluralCode, stringsCount, translatedCount, translationsUrl):
                self.init(languageCode: langCode, baseLanguageCode: baseLangCode, customPluralizationCode: pluralCode, title: name, localizedTitle: nativeName, isOfficial: (flags & (1 << 0)) != 0, totalStringCount: stringsCount, translatedStringCount: translatedCount, platformUrl: translationsUrl)
        }
    }
}

public final class SuggestedLocalizationInfo {
    public let languageCode: String
    public let extractedEntries: [LocalizationEntry]
    
    public let availableLocalizations: [LocalizationInfo]
    
    init(languageCode: String, extractedEntries: [LocalizationEntry], availableLocalizations: [LocalizationInfo]) {
        self.languageCode = languageCode
        self.extractedEntries = extractedEntries
        self.availableLocalizations = availableLocalizations
    }
}

// MARK: Swiftgram
// All the languages are "official" to prevent their deletion
public let SGLocalizations: [LocalizationInfo] = [
    LocalizationInfo(languageCode: "zhcncc", baseLanguageCode: "zh-hans-raw", customPluralizationCode: "zh", title: "Chinese (Simplified) zhcncc", localizedTitle: "简体中文 (聪聪) - 已更完", isOfficial: true, totalStringCount: 7160, translatedStringCount: 7144, platformUrl: "https://translations.telegram.org/zhcncc/"),
    LocalizationInfo(languageCode: "taiwan", baseLanguageCode: "zh-hant-raw", customPluralizationCode: "zh", title: "Chinese (zh-Hant-TW) @zh_Hant_TW", localizedTitle: "正體中文", isOfficial: true, totalStringCount: 7160, translatedStringCount: 3761, platformUrl: "https://translations.telegram.org/taiwan/"),
    LocalizationInfo(languageCode: "hongkong", baseLanguageCode: "zh-hant-raw", customPluralizationCode: "zh", title: "Chinese (Hong Kong)", localizedTitle: "中文（香港）", isOfficial: true, totalStringCount: 7358, translatedStringCount: 6083, platformUrl: "https://translations.telegram.org/hongkong/"),
    // baseLanguageCode is actually nil, since it's an "official" beta language
    LocalizationInfo(languageCode: "vi-raw", baseLanguageCode: "vi-raw", customPluralizationCode: "vi", title: "Vietnamese", localizedTitle: "Tiếng Việt (beta)", isOfficial: true, totalStringCount: 7160, translatedStringCount: 3795, platformUrl: "https://translations.telegram.org/vi/"),
    LocalizationInfo(languageCode: "hi-raw", baseLanguageCode: "hi-raw", customPluralizationCode: "hi", title: "Hindi", localizedTitle: "हिन्दी (beta)", isOfficial: true, totalStringCount: 7358, translatedStringCount: 992, platformUrl: "https://translations.telegram.org/hi/"),
    // baseLanguageCode should be changed to nil? or hy?
    LocalizationInfo(languageCode: "earmenian", baseLanguageCode: "earmenian", customPluralizationCode: "hy", title: "Armenian", localizedTitle: "Հայերեն", isOfficial: true, totalStringCount: 7358, translatedStringCount: 6384, platformUrl: "https://translations.telegram.org/earmenian/")
]
