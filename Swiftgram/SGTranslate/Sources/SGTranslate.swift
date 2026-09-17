import SGGTranslate
import SGSimpleSettings
import SGTranslationLangFix

import Postbox
import SwiftSignalKit

public class QuickTranslationMessageAttribute: MessageAttribute, Equatable {
    public let originalText: String
    public let originalEntities: [MessageTextEntity]

    public var associatedPeerIds: [PeerId] {
        return []
    }

    public init(text: String, entities: [MessageTextEntity]) {
        self.originalText = text
        self.originalEntities = entities
    }

    required public init(decoder: PostboxDecoder) {
        self.originalText = decoder.decodeStringForKey("originalText", orElse: "")
        self.originalEntities = decoder.decodeObjectArrayWithDecoderForKey("originalEntities")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.originalText, forKey: "originalText")
        encoder.encodeObjectArray(self.originalEntities, forKey: "originalEntities")
    }

    public static func ==(lhs: QuickTranslationMessageAttribute, rhs: QuickTranslationMessageAttribute) -> Bool {
        if lhs.originalText != rhs.originalText {
            return false
        }
        if lhs.originalEntities != rhs.originalEntities {
            return false
        }
        return true
    }
}

func sgTranslationDebugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

func sgTranslationDebugLanguages(fromLang: String?, toLang: String) -> String {
    if let fromLang {
        return " from '\(fromLang)' to '\(toLang)'"
    }
    return " to '\(toLang)'"
}

func sgTranslationDebugSuccess(backend: SGSimpleSettings.TranslationBackend, inputLength: Int, outputLength: Int, fromLang: String?, toLang: String) {
    sgTranslationDebugLog("[SGTranslate][\(backend.rawValue)] translated \(inputLength) chars\(sgTranslationDebugLanguages(fromLang: fromLang, toLang: toLang)) \(outputLength) chars")
}

func sgTranslationDebugError(backend: SGSimpleSettings.TranslationBackend, inputLength: Int, fromLang: String?, toLang: String, error: Any) {
    sgTranslationDebugLog("[SGTranslate][\(backend.rawValue)] error translating \(inputLength) chars\(sgTranslationDebugLanguages(fromLang: fromLang, toLang: toLang)), error: \(error)")
}

func sgTranslationDebugFallback(backend: SGSimpleSettings.TranslationBackend, inputLength: Int, fromLang: String?, toLang: String) {
    sgTranslationDebugLog("[SGTranslate][\(backend.rawValue)] attempting GTranslate fallback for \(inputLength) chars\(sgTranslationDebugLanguages(fromLang: fromLang, toLang: toLang))")
}

func sgGTranslate(text: String, fromLang: String? = nil, toLang: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    return gtranslate(text, toLang)
    |> map { translatedText in
        sgTranslationDebugSuccess(backend: .gtranslate, inputLength: text.count, outputLength: translatedText.count, fromLang: fromLang, toLang: toLang)
        return (translatedText, [])
    }
    |> mapError { error in
        sgTranslationDebugError(backend: .gtranslate, inputLength: text.count, fromLang: fromLang, toLang: toLang, error: error)
        return .generic
    }
}

func sgWrappedTranslateSingle(text: String, toLang: String, `default`: Signal<(String, [MessageTextEntity])?, TranslationError>) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    let backend = SGSimpleSettings.shared.translationBackendEnum
    switch backend {
    case .gtranslate:
        return sgGTranslate(text: text, toLang: toLang)
    case .system:
        guard let engineExperimentalInternalTranslationService else {
            sgTranslationDebugError(backend: backend, inputLength: text.count, fromLang: nil, toLang: toLang, error: "unavailable")
            sgTranslationDebugFallback(backend: backend, inputLength: text.count, fromLang: nil, toLang: toLang)
            return sgGTranslate(text: text, toLang: toLang)
        }
        return engineExperimentalInternalTranslationService.translate(texts: [0: text], fromLang: "", toLang: toLang)
        |> castError(TranslationError.self)
        |> mapToSignal { result -> Signal<(String, [MessageTextEntity])?, TranslationError> in
            guard let translatedText = result?[0], !translatedText.isEmpty else {
                sgTranslationDebugError(backend: backend, inputLength: text.count, fromLang: nil, toLang: toLang, error: "incompleteResult")
                return .fail(.generic)
            }
            sgTranslationDebugSuccess(backend: backend, inputLength: text.count, outputLength: translatedText.count, fromLang: nil, toLang: toLang)
            return .single((translatedText, []))
        }
        |> `catch` { error in
            sgTranslationDebugError(backend: backend, inputLength: text.count, fromLang: nil, toLang: toLang, error: error)
            sgTranslationDebugFallback(backend: backend, inputLength: text.count, fromLang: nil, toLang: toLang)
            return sgGTranslate(text: text, toLang: toLang)
        }
    case .default:
        return `default`
        |> beforeNext { result in
            sgTranslationDebugSuccess(backend: backend, inputLength: text.count, outputLength: result?.0.count ?? 0, fromLang: nil, toLang: toLang)
        }
        |> `catch` { error in
            sgTranslationDebugError(backend: backend, inputLength: text.count, fromLang: nil, toLang: toLang, error: error)
            sgTranslationDebugFallback(backend: backend, inputLength: text.count, fromLang: nil, toLang: toLang)
            return sgGTranslate(text: text, toLang: toLang)
        }
    }
}

func sgTranslationTargetLanguage(_ language: String) -> String {
    return sgTranslationLangFix(language)
}

func sgGTranslate(texts: [(String, [MessageTextEntity])], toLang: String) -> Signal<[(String, [MessageTextEntity])], TranslationError> {
    return combineLatest(texts.map { text, _ in
        sgGTranslate(text: text, toLang: toLang)
        |> map { $0 ?? ("", []) }
    })
}

func sgWrappedTranslateMultiple(texts: [(String, [MessageTextEntity])], toLang: String, `default`: Signal<[(String, [MessageTextEntity])], TranslationError>) -> Signal<[(String, [MessageTextEntity])], TranslationError> {
    let backend = SGSimpleSettings.shared.translationBackendEnum
    switch backend {
    case .gtranslate:
        return sgGTranslate(texts: texts, toLang: toLang)
    case .system:
        guard let engineExperimentalInternalTranslationService else {
            sgTranslationDebugError(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang, error: "unavailable")
            sgTranslationDebugFallback(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang)
            return sgGTranslate(texts: texts, toLang: toLang)
        }
        let sourceTexts = Dictionary(uniqueKeysWithValues: texts.enumerated().map { (AnyHashable($0.offset), $0.element.0) })
        return engineExperimentalInternalTranslationService.translate(texts: sourceTexts, fromLang: "", toLang: toLang)
        |> castError(TranslationError.self)
        |> mapToSignal { result -> Signal<[(String, [MessageTextEntity])], TranslationError> in
            guard let result, result.count == texts.count else {
                sgTranslationDebugError(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang, error: "incompleteResult")
                return .fail(.generic)
            }
            let translated = texts.indices.compactMap { index -> (String, [MessageTextEntity])? in
                result[AnyHashable(index)].flatMap { $0.isEmpty ? nil : ($0, []) }
            }
            guard translated.count == texts.count else {
                sgTranslationDebugError(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang, error: "incompleteResult")
                return .fail(.generic)
            }
            sgTranslationDebugSuccess(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, outputLength: translated.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang)
            return .single(translated)
        }
        |> `catch` { error in
            sgTranslationDebugError(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang, error: error)
            sgTranslationDebugFallback(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang)
            return sgGTranslate(texts: texts, toLang: toLang)
        }
    case .default:
        return `default`
        |> beforeNext { translated in
            sgTranslationDebugSuccess(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, outputLength: translated.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang)
        }
        |> `catch` { error in
            sgTranslationDebugError(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang, error: error)
            sgTranslationDebugFallback(backend: backend, inputLength: texts.reduce(0) { $0 + $1.0.count }, fromLang: nil, toLang: toLang)
            return sgGTranslate(texts: texts, toLang: toLang)
        }
    }
}

func _internal_translateMessagesViaText(account: Account, messagesDict: [EngineMessage.Id: String], fromLang: String?, toLang: String, generateEntitiesFunction: @escaping (String) -> [MessageTextEntity], forceGTranslate: Bool) -> Signal<Never, TranslationError> {
    var listOfSignals: [Signal<Void, TranslationError>] = []
    for (messageId, text) in messagesDict {
        listOfSignals.append(
            sgTranslateRawText(account: account, text: text, fromLang: fromLang, toLang: toLang, forceGTranslate: forceGTranslate)
            |> mapToSignal { translated -> Signal<Void, TranslationError> in
                guard let translated, !translated.0.isEmpty else {
                    return .complete()
                }
                return account.postbox.transaction { transaction in
                    transaction.updateMessage(messageId, update: { currentMessage in
                        let entities = translated.1.isEmpty ? generateEntitiesFunction(translated.0) : translated.1
                        let updatedAttribute = TranslationMessageAttribute(text: translated.0, entities: entities, toLang: toLang)
                        let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                        var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                        attributes.append(updatedAttribute)
                        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                    })
                }
                |> castError(TranslationError.self)
            }
        )
    }
    return combineLatest(listOfSignals) |> ignoreValues
}

func sgTranslateRawText(account: Account, text: String, fromLang: String?, toLang: String, forceGTranslate: Bool = false) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    guard !text.isEmpty else {
        return .complete()
    }
    let backend = SGSimpleSettings.shared.translationBackendEnum
    if forceGTranslate || backend == .gtranslate {
        return sgGTranslate(text: text, fromLang: fromLang, toLang: toLang)
    }
    if backend == .system {
        guard let engineExperimentalInternalTranslationService else {
            sgTranslationDebugError(backend: backend, inputLength: text.count, fromLang: fromLang, toLang: toLang, error: "unavailable")
            sgTranslationDebugFallback(backend: backend, inputLength: text.count, fromLang: fromLang, toLang: toLang)
            return sgGTranslate(text: text, fromLang: fromLang, toLang: toLang)
        }
        return engineExperimentalInternalTranslationService.translate(texts: [0: text], fromLang: fromLang ?? "", toLang: toLang)
        |> castError(TranslationError.self)
        |> mapToSignal { result -> Signal<(String, [MessageTextEntity])?, TranslationError> in
            guard let translatedText = result?[0], !translatedText.isEmpty else {
                sgTranslationDebugError(backend: backend, inputLength: text.count, fromLang: fromLang, toLang: toLang, error: "incompleteResult")
                return .fail(.generic)
            }
            sgTranslationDebugSuccess(backend: backend, inputLength: text.count, outputLength: translatedText.count, fromLang: fromLang, toLang: toLang)
            return .single((translatedText, []))
        }
        |> `catch` { error in
            sgTranslationDebugError(backend: backend, inputLength: text.count, fromLang: fromLang, toLang: toLang, error: error)
            sgTranslationDebugFallback(backend: backend, inputLength: text.count, fromLang: fromLang, toLang: toLang)
            return sgGTranslate(text: text, fromLang: fromLang, toLang: toLang)
        }
    }
    return _internal_translate(network: account.network, text: text, toLang: toLang)
    |> beforeNext { result in
        sgTranslationDebugSuccess(backend: backend, inputLength: text.count, outputLength: result?.0.count ?? 0, fromLang: fromLang, toLang: toLang)
    }
    |> `catch` { error in
        sgTranslationDebugError(backend: backend, inputLength: text.count, fromLang: fromLang, toLang: toLang, error: error)
        sgTranslationDebugFallback(backend: backend, inputLength: text.count, fromLang: fromLang, toLang: toLang)
        return sgGTranslate(text: text, fromLang: fromLang, toLang: toLang)
    }
}

extension TelegramEngine.Messages {
    public func translateMessagesViaText(messagesDict: [EngineMessage.Id: String], fromLang: String?, toLang: String, generateEntitiesFunction: @escaping (String) -> [MessageTextEntity], enableLocalIfPossible: Bool, forceGTranslate: Bool = false) -> Signal<Never, TranslationError> {
        return _internal_translateMessagesViaText(account: self.account, messagesDict: messagesDict, fromLang: fromLang, toLang: toLang, generateEntitiesFunction: generateEntitiesFunction, forceGTranslate: forceGTranslate)
    }
}
