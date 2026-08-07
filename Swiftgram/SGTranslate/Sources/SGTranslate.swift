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

func sgWrappedTranslateSingle(text: String, toLang: String, `default`: Signal<(String, [MessageTextEntity])?, TranslationError>) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    if SGSimpleSettings.shared.translationBackend == SGSimpleSettings.TranslationBackend.gtranslate.rawValue {
        return gtranslate(text, toLang)
        |> map { ($0, []) }
        |> mapError { _ in .generic }
    }

    return `default`
    |> `catch` { originalError in
        gtranslate(text, toLang)
        |> map { ($0, []) }
        |> mapError { _ in originalError }
    }
}

func sgTranslationTargetLanguage(_ language: String) -> String {
    return sgTranslationLangFix(language)
}

func sgWrappedTranslateMultiple(texts: [(String, [MessageTextEntity])], toLang: String, `default`: Signal<[(String, [MessageTextEntity])], TranslationError>) -> Signal<[(String, [MessageTextEntity])], TranslationError> {
    if SGSimpleSettings.shared.translationBackend == SGSimpleSettings.TranslationBackend.gtranslate.rawValue {
        let translatedSignals: [Signal<(String, [MessageTextEntity]), TranslationError>] = texts.map { (text, _) in
            gtranslate(text, toLang)
            |> map { ($0, []) }
            |> mapError { _ in .generic }
        }
        return combineLatest(translatedSignals)
    }

    return `default`
    |> `catch` { originalError in
        let translatedSignals: [Signal<(String, [MessageTextEntity]), TranslationError>] = texts.map { (text, _) in
            gtranslate(text, toLang)
            |> map { ($0, []) }
            |> mapError { _ in originalError }
        }
        return combineLatest(translatedSignals)
    }
}

func _internal_translateMessagesViaText(account: Account, messagesDict: [EngineMessage.Id: String], fromLang: String?, toLang: String, enableLocalIfPossible: Bool, generateEntitiesFunction: @escaping (String) -> [MessageTextEntity]) -> Signal<Never, TranslationError> {
    var listOfSignals: [Signal<Void, TranslationError>] = []
    for (messageId, text) in messagesDict {
        listOfSignals.append(
            gtranslate(text, toLang)
            |> mapError { _ -> TranslationError in
                return .generic
            }
            |> mapToSignal { translatedText -> Signal<Void, TranslationError> in
                return account.postbox.transaction { transaction in
                    transaction.updateMessage(messageId, update: { currentMessage in
                        let updatedAttribute: TranslationMessageAttribute = TranslationMessageAttribute(text: translatedText, entities: generateEntitiesFunction(translatedText), toLang: toLang)
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

extension TelegramEngine.Messages {
    public func translateMessagesViaText(messagesDict: [EngineMessage.Id: String], fromLang: String?, toLang: String, generateEntitiesFunction: @escaping (String) -> [MessageTextEntity], enableLocalIfPossible: Bool) -> Signal<Never, TranslationError> {
        return _internal_translateMessagesViaText(account: self.account, messagesDict: messagesDict, fromLang: fromLang, toLang: toLang, enableLocalIfPossible: enableLocalIfPossible, generateEntitiesFunction: generateEntitiesFunction)
    }
}
