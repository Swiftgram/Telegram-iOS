public func sgTranslationLangFix(_ language: String) -> String {
    if language.hasPrefix("de-") {
        return "de"
    } else if language.hasPrefix("zh-") {
        return "zh"
    } else {
        return language
    }
}