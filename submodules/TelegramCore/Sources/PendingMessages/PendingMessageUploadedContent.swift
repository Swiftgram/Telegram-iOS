import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit
import CryptoUtils

enum PendingMessageUploadedContent {
    case text(String)
    case media(Api.InputMedia, String)
    case forward(ForwardSourceInfoAttribute)
    case chatContextResult(OutgoingChatContextResultMessageAttribute)
    case secretMedia(Api.InputEncryptedFile, Int64, SecretFileEncryptionKey)
    case messageScreenshot
}

enum PendingMessageReuploadInfo {
    case reuploadFile(FileMediaReference)
}

struct PendingMessageUploadedContentAndReuploadInfo {
    let content: PendingMessageUploadedContent
    let reuploadInfo: PendingMessageReuploadInfo?
    let cacheReferenceKey: CachedSentMediaReferenceKey?
}

struct PendingMessageUploadedContentProgress {
    let progress: Float
    let mediaProgress: [MediaId: Float]
    
    init(progress: Float, mediaProgress: [MediaId: Float] = [:]) {
        self.progress = progress
        self.mediaProgress = mediaProgress
    }
}

enum PendingMessageUploadedContentResult {
    case progress(PendingMessageUploadedContentProgress)
    case content(PendingMessageUploadedContentAndReuploadInfo)
}

enum PendingMessageUploadedContentType {
    case none
    case text
    case media
}

enum PendingMessageUploadError {
    case generic
}

enum MessageContentToUpload {
    case signal(Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>, PendingMessageUploadedContentType)
    case immediate(PendingMessageUploadedContentResult, PendingMessageUploadedContentType)
    
    var type: PendingMessageUploadedContentType {
        switch self {
        case let .signal(_, type):
            return type
        case let .immediate(_, type):
            return type
        }
    }
}

func messageContentToUpload(accountPeerId: PeerId, network: Network, postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, revalidationContext: MediaReferenceRevalidationContext, forceReupload: Bool, isGrouped: Bool, passFetchProgress: Bool = false, message: Message) -> MessageContentToUpload {
    return messageContentToUpload(accountPeerId: accountPeerId, network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, revalidationContext: revalidationContext, forceReupload: forceReupload, isGrouped: isGrouped, passFetchProgress: passFetchProgress, forceNoBigParts: false, peerId: message.id.peerId, messageId: message.id, attributes: message.attributes, text: message.text, media: message.media)
}

func messageContentToUpload(accountPeerId: PeerId, network: Network, postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, revalidationContext: MediaReferenceRevalidationContext, forceReupload: Bool, isGrouped: Bool, passFetchProgress: Bool, forceNoBigParts: Bool, peerId: PeerId, messageId: MessageId?, attributes: [MessageAttribute], text: String, media: [Media], mediaReference: AnyMediaReference? = nil) -> MessageContentToUpload {
    var contextResult: OutgoingChatContextResultMessageAttribute?
    var autoremoveMessageAttribute: AutoremoveTimeoutMessageAttribute?
    var autoclearMessageAttribute: AutoclearTimeoutMessageAttribute?
    for attribute in attributes {
        if let attribute = attribute as? OutgoingChatContextResultMessageAttribute {
            if peerId.namespace != Namespaces.Peer.SecretChat {
                contextResult = attribute
            }
        } else if let attribute = attribute as? AutoremoveTimeoutMessageAttribute {
            autoremoveMessageAttribute = attribute
        } else if let attribute = attribute as? AutoclearTimeoutMessageAttribute {
            autoclearMessageAttribute = attribute
        }
    }
    
    var forwardInfo: ForwardSourceInfoAttribute?
    for attribute in attributes {
        if let attribute = attribute as? ForwardSourceInfoAttribute {
            if peerId.namespace != Namespaces.Peer.SecretChat {
                forwardInfo = attribute
            }
        }
    }
    
    if let media = media.first as? TelegramMediaAction, media.action == .historyScreenshot {
        return .immediate(.content(PendingMessageUploadedContentAndReuploadInfo(content: .messageScreenshot, reuploadInfo: nil, cacheReferenceKey: nil)), .none)
    } else if let forwardInfo = forwardInfo {
        return .immediate(.content(PendingMessageUploadedContentAndReuploadInfo(content: .forward(forwardInfo), reuploadInfo: nil, cacheReferenceKey: nil)), .text)
    } else if let contextResult = contextResult {
        return .immediate(.content(PendingMessageUploadedContentAndReuploadInfo(content: .chatContextResult(contextResult), reuploadInfo: nil, cacheReferenceKey: nil)), .text)
    } else if let media = media.first as? TelegramMediaStory {
        return .signal(postbox.transaction { transaction -> PendingMessageUploadedContentResult in
            guard let inputPeer = transaction.getPeer(media.storyId.peerId).flatMap(apiInputPeer) else {
                return .progress(PendingMessageUploadedContentProgress(progress: 0.0))
            }
            return .content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaStory(peer: inputPeer, id: media.storyId.id), ""), reuploadInfo: nil, cacheReferenceKey: nil))
        }
        |> castError(PendingMessageUploadError.self), .text)
    } else if let media = media.first as? TelegramMediaWebpage, case let .Loaded(content) = media.content {
        return .signal(postbox.transaction { transaction -> PendingMessageUploadedContentResult in
            var flags: Int32 = 0
            flags |= 1 << 2
            if let attribute = attributes.first(where: { $0 is WebpagePreviewMessageAttribute }) as? WebpagePreviewMessageAttribute {
                if let forceLargeMedia = attribute.forceLargeMedia {
                    if forceLargeMedia {
                        flags |= 1 << 0
                    } else {
                        flags |= 1 << 1
                    }
                }
            }
            return .content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaWebPage(flags: flags, url: content.url), text), reuploadInfo: nil, cacheReferenceKey: nil))
        }
        |> castError(PendingMessageUploadError.self), .text)
    } else if let media = media.first, let mediaResult = mediaContentToUpload(accountPeerId: accountPeerId, network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, revalidationContext: revalidationContext, forceReupload: forceReupload, isGrouped: isGrouped, passFetchProgress: passFetchProgress, forceNoBigParts: forceNoBigParts, peerId: peerId, media: media, text: text, autoremoveMessageAttribute: autoremoveMessageAttribute, autoclearMessageAttribute: autoclearMessageAttribute, messageId: messageId, attributes: attributes, mediaReference: mediaReference) {
        return .signal(mediaResult, .media)
    } else {
        return .signal(.single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .text(text), reuploadInfo: nil, cacheReferenceKey: nil))), .text)
    }
}

func mediaContentToUpload(accountPeerId: PeerId, network: Network, postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, revalidationContext: MediaReferenceRevalidationContext, forceReupload: Bool, isGrouped: Bool, passFetchProgress: Bool, forceNoBigParts: Bool, peerId: PeerId, media: Media, text: String, autoremoveMessageAttribute: AutoremoveTimeoutMessageAttribute?, autoclearMessageAttribute: AutoclearTimeoutMessageAttribute?, messageId: MessageId?, attributes: [MessageAttribute], mediaReference: AnyMediaReference?) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>? {
    if let paidContent = media as? TelegramMediaPaidContent {
        var signals: [Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>] = []
        var mediaIds: [MediaId] = []
        let isGrouped = paidContent.extendedMedia.count > 1
        for case let .full(media) in paidContent.extendedMedia {
            guard let id = media.id else {
                continue
            }
            mediaIds.append(id)
            if let image = media as? TelegramMediaImage {
                signals.append(uploadedMediaImageContent(network: network, postbox: postbox, transformOutgoingMessageMedia: transformOutgoingMessageMedia, forceReupload: forceReupload, isGrouped: isGrouped, peerId: peerId, image: image, messageId: messageId, text: "", attributes: [], autoremoveMessageAttribute: nil, autoclearMessageAttribute: nil, auxiliaryMethods: auxiliaryMethods))
            } else if let file = media as? TelegramMediaFile {
                signals.append(uploadedMediaFileContent(network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, forceReupload: forceReupload, isGrouped: isGrouped, isPaid: true, passFetchProgress: false, forceNoBigParts: false, peerId: peerId, messageId: messageId, text: "", attributes: [], autoremoveMessageAttribute: nil, autoclearMessageAttribute: nil, file: file))
            }
        }
        return combineLatest(signals)
        |> map { results -> PendingMessageUploadedContentResult in
            var currentProgress: Float = 0.0
            var media: [Api.InputMedia] = []
            var mediaProgress: [MediaId: Float] = [:]
            for (mediaId, result) in zip(mediaIds, results) {
                switch result {
                case let .progress(progress):
                    currentProgress += progress.progress
                    mediaProgress[mediaId] = progress.progress
                case let .content(content):
                    if case let .media(resultMedia, _) = content.content {
                        media.append(resultMedia)
                        mediaProgress[mediaId] = 1.0
                    }
                }
            }
            let normalizedProgress = currentProgress / Float(results.count)
            if media.count == results.count {
                return .content(PendingMessageUploadedContentAndReuploadInfo(
                    content: .media(.inputMediaPaidMedia(
                        flags: 0,
                        starsAmount: paidContent.amount,
                        extendedMedia: media,
                        payload: nil
                    ), text),
                    reuploadInfo: nil,
                    cacheReferenceKey: nil
                ))
            } else {
                return .progress(PendingMessageUploadedContentProgress(progress: normalizedProgress, mediaProgress: mediaProgress))
            }
        }
    }
    if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
        if peerId.namespace == Namespaces.Peer.SecretChat, let resource = largest.resource as? SecretFileMediaResource {
            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .secretMedia(.inputEncryptedFile(id: resource.fileId, accessHash: resource.accessHash), resource.decryptedSize, resource.key), reuploadInfo: nil, cacheReferenceKey: nil)))
        }
        if peerId.namespace != Namespaces.Peer.SecretChat, let reference = image.reference, case let .cloud(id, accessHash, maybeFileReference) = reference, let fileReference = maybeFileReference {
            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(Api.InputMedia.inputMediaPhoto(flags: 0, id: Api.InputPhoto.inputPhoto(id: id, accessHash: accessHash, fileReference: Buffer(data: fileReference)), ttlSeconds: nil), text), reuploadInfo: nil, cacheReferenceKey: nil)))
        } else {
            return uploadedMediaImageContent(network: network, postbox: postbox, transformOutgoingMessageMedia: transformOutgoingMessageMedia, forceReupload: forceReupload, isGrouped: isGrouped, peerId: peerId, image: image, messageId: messageId, text: text, attributes: attributes, autoremoveMessageAttribute: autoremoveMessageAttribute, autoclearMessageAttribute: autoclearMessageAttribute, auxiliaryMethods: auxiliaryMethods)
        }
    } else if let file = media as? TelegramMediaFile {
        if let resource = file.resource as? CloudDocumentMediaResource {
            if peerId.namespace == Namespaces.Peer.SecretChat {
                for attribute in file.attributes {
                    if case let .Sticker(_, packReferenceValue, _) = attribute {
                        if let _ = packReferenceValue {
                            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: PendingMessageUploadedContent.text(text), reuploadInfo: nil, cacheReferenceKey: nil)))
                        }
                    }
                }
                return uploadedMediaFileContent(network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, forceReupload: true, isGrouped: isGrouped, isPaid: false, passFetchProgress: false, forceNoBigParts: false, peerId: peerId, messageId: messageId, text: text, attributes: attributes, autoremoveMessageAttribute: autoremoveMessageAttribute, autoclearMessageAttribute: autoclearMessageAttribute, file: file)
            } else {
                if forceReupload {
                    let finalMediaReference: Signal<AnyMediaReference, NoError>
                    if let mediaReference = mediaReference {
                        finalMediaReference = .single(mediaReference)
                    } else if file.isSticker || file.isCustomEmoji {
                        if let partialReference = file.partialReference {
                            finalMediaReference = .single(partialReference.mediaReference(file))
                        } else {
                            finalMediaReference = postbox.transaction { transaction -> AnyMediaReference in
                                if transaction.getOrderedItemListItem(collectionId: Namespaces.OrderedItemList.CloudRecentStickers, itemId: RecentMediaItemId(file.fileId).rawValue) != nil {
                                    return .recentSticker(media: file)
                                } else if transaction.getOrderedItemListItem(collectionId: Namespaces.OrderedItemList.CloudSavedStickers, itemId: RecentMediaItemId(file.fileId).rawValue) != nil {
                                    return .savedSticker(media: file)
                                }
                                
                                return .standalone(media: file)
                            }
                        }
                    } else {
                        finalMediaReference = .single(.savedGif(media: file))
                    }
                    return finalMediaReference
                    |> castError(PendingMessageUploadError.self)
                    |> mapToSignal { finalMediaReference in
                        return revalidateMediaResourceReference(accountPeerId: accountPeerId, postbox: postbox, network: network, revalidationContext: revalidationContext, info: TelegramCloudMediaResourceFetchInfo(reference: finalMediaReference.resourceReference(file.resource), preferBackgroundReferenceRevalidation: false, continueInBackground: false), resource: resource)
                        |> mapError { _ -> PendingMessageUploadError in
                            return .generic
                        }
                        |> mapToSignal { validatedResource -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                            if let validatedResource = validatedResource.updatedResource as? TelegramCloudMediaResourceWithFileReference, let reference = validatedResource.fileReference {
                                var flags: Int32 = 0
                                
                                var videoTimestamp: Int32?
                                for attribute in attributes {
                                    if let attribute = attribute as? ForwardVideoTimestampAttribute {
                                        videoTimestamp = attribute.timestamp
                                    }
                                }
                                if videoTimestamp != nil {
                                    flags |= 1 << 4
                                }
                                
                                return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(Api.InputMedia.inputMediaDocument(flags: flags, id: Api.InputDocument.inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: reference)), videoCover: nil, videoTimestamp: videoTimestamp, ttlSeconds: nil, query: nil), text), reuploadInfo: nil, cacheReferenceKey: nil)))
                            } else {
                                return .fail(.generic)
                            }
                        }
                    }
                }
                
                var flags: Int32 = 0
                var emojiSearchQuery: String?
                var videoTimestamp: Int32?
                for attribute in attributes {
                    if let attribute = attribute as? EmojiSearchQueryMessageAttribute {
                        emojiSearchQuery = attribute.query
                        flags |= (1 << 1)
                    } else if let attribute = attribute as? ForwardVideoTimestampAttribute {
                        flags |= (1 << 4)
                        videoTimestamp = attribute.timestamp
                    }
                }
                
                return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(Api.InputMedia.inputMediaDocument(flags: flags, id: Api.InputDocument.inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: resource.fileReference ?? Data())), videoCover: nil, videoTimestamp: videoTimestamp, ttlSeconds: nil, query: emojiSearchQuery), text), reuploadInfo: nil, cacheReferenceKey: nil)))
            }
        } else {
            return uploadedMediaFileContent(network: network, postbox: postbox, auxiliaryMethods: auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, forceReupload: forceReupload, isGrouped: isGrouped, isPaid: false, passFetchProgress: passFetchProgress, forceNoBigParts: forceNoBigParts, peerId: peerId, messageId: messageId, text: text, attributes: attributes, autoremoveMessageAttribute: autoremoveMessageAttribute, autoclearMessageAttribute: autoclearMessageAttribute, file: file)
        }
    } else if let contact = media as? TelegramMediaContact {
        let input = Api.InputMedia.inputMediaContact(phoneNumber: contact.phoneNumber, firstName: contact.firstName, lastName: contact.lastName, vcard: contact.vCardData ?? "")
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(input, text), reuploadInfo: nil, cacheReferenceKey: nil)))
    } else if let map = media as? TelegramMediaMap {
        let input: Api.InputMedia
        var flags: Int32 = 1 << 1
        if let _ = map.heading {
            flags |= 1 << 2
        }
        if let _ = map.liveProximityNotificationRadius {
            flags |= 1 << 3
        }
        var geoFlags: Int32 = 0
        if let _ = map.accuracyRadius {
            geoFlags |= 1 << 0
        }
        if let liveBroadcastingTimeout = map.liveBroadcastingTimeout {
            input = .inputMediaGeoLive(flags: flags, geoPoint: Api.InputGeoPoint.inputGeoPoint(flags: geoFlags, lat: map.latitude, long: map.longitude, accuracyRadius: map.accuracyRadius.flatMap({ Int32($0) })), heading: map.heading, period: liveBroadcastingTimeout, proximityNotificationRadius: map.liveProximityNotificationRadius.flatMap({ Int32($0) }))
        } else if let venue = map.venue {
            input = .inputMediaVenue(geoPoint: Api.InputGeoPoint.inputGeoPoint(flags: geoFlags, lat: map.latitude, long: map.longitude, accuracyRadius: map.accuracyRadius.flatMap({ Int32($0) })), title: venue.title, address: venue.address ?? "", provider: venue.provider ?? "", venueId: venue.id ?? "", venueType: venue.type ?? "")
        } else {
            input = .inputMediaGeoPoint(geoPoint: Api.InputGeoPoint.inputGeoPoint(flags: geoFlags, lat: map.latitude, long: map.longitude, accuracyRadius: map.accuracyRadius.flatMap({ Int32($0) })))
        }
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(input, text), reuploadInfo: nil, cacheReferenceKey: nil)))
    } else if let poll = media as? TelegramMediaPoll {
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return .fail(.generic)
        }
        var pollFlags: Int32 = 0
        switch poll.kind {
        case let .poll(multipleAnswers):
            if multipleAnswers {
                pollFlags |= 1 << 2
            }
        case .quiz:
            pollFlags |= 1 << 3
        }
        switch poll.publicity {
        case .anonymous:
            break
        case .public:
            pollFlags |= 1 << 1
        }
        var pollMediaFlags: Int32 = 0
        var correctAnswers: [Buffer]?
        if let correctAnswersValue = poll.correctAnswers {
            pollMediaFlags |= 1 << 0
            correctAnswers = correctAnswersValue.map { Buffer(data: $0) }
        }
        if poll.deadlineTimeout != nil {
            pollFlags |= 1 << 4
        }
        
        var mappedSolution: String?
        var mappedSolutionEntities: [Api.MessageEntity]?
        if let solution = poll.results.solution {
            mappedSolution = solution.text
            mappedSolutionEntities = apiTextAttributeEntities(TextEntitiesMessageAttribute(entities: solution.entities), associatedPeers: SimpleDictionary())
            pollMediaFlags |= 1 << 1
        }
        let inputPoll = Api.InputMedia.inputMediaPoll(flags: pollMediaFlags, poll: Api.Poll.poll(id: 0, flags: pollFlags, question: .textWithEntities(text: poll.text, entities: apiEntitiesFromMessageTextEntities(poll.textEntities, associatedPeers: SimpleDictionary())), answers: poll.options.map({ $0.apiOption }), closePeriod: poll.deadlineTimeout, closeDate: nil), correctAnswers: correctAnswers, solution: mappedSolution, solutionEntities: mappedSolutionEntities)
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(inputPoll, text), reuploadInfo: nil, cacheReferenceKey: nil)))
    } else if let todo = media as? TelegramMediaTodo {
        var flags: Int32 = 0
        if todo.flags.contains(.othersCanAppend) {
            flags |= 1 << 0
        }
        if todo.flags.contains(.othersCanComplete) {
            flags |= 1 << 1
        }
        let inputTodo = Api.InputMedia.inputMediaTodo(todo: .todoList(flags: flags, title: .textWithEntities(text: todo.text, entities: apiEntitiesFromMessageTextEntities(todo.textEntities, associatedPeers: SimpleDictionary())), list: todo.items.map { $0.apiItem }))
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(inputTodo, text), reuploadInfo: nil, cacheReferenceKey: nil)))
    } else if let dice = media as? TelegramMediaDice {
        let inputDice = Api.InputMedia.inputMediaDice(emoticon: dice.emoji)
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(inputDice, text), reuploadInfo: nil, cacheReferenceKey: nil)))
    } else if let webPage = media as? TelegramMediaWebpage, case let .Loaded(content) = webPage.content {
        var flags: Int32 = 0
        flags |= 1 << 2
        if let attribute = attributes.first(where: { $0 is WebpagePreviewMessageAttribute }) as? WebpagePreviewMessageAttribute {
            if let forceLargeMedia = attribute.forceLargeMedia {
                if forceLargeMedia {
                    flags |= 1 << 0
                } else {
                    flags |= 1 << 1
                }
            }
        }
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaWebPage(flags: flags, url: content.url), text), reuploadInfo: nil, cacheReferenceKey: nil)))
    } else {
        return nil
    }
}

private enum PredownloadedResource {
    case localReference(CachedSentMediaReferenceKey?)
    case media(Media, CachedSentMediaReferenceKey?)
    case none
}

private func maybePredownloadedImageResource(postbox: Postbox, peerId: PeerId, resource: MediaResource, forceRefresh: Bool) -> Signal<PredownloadedResource, PendingMessageUploadError> {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return .single(.none)
    }
    
    return Signal<Signal<PredownloadedResource, PendingMessageUploadError>, PendingMessageUploadError> { subscriber in
        let data = postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false)).start(next: { data in
            if data.complete {
                if data.size < 5 * 1024 * 1024, let fileData = try? Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedRead) {
                    let md5 = IncrementalMD5()
                    fileData.withUnsafeBytes { rawBytes -> Void in
                        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)

                        var offset = 0
                        let bufferSize = 32 * 1024
                        
                        while offset < fileData.count {
                            let partSize = min(fileData.count - offset, bufferSize)
                            md5.update(bytes.advanced(by: offset), count: Int32(partSize))
                            offset += bufferSize
                        }
                    }
                    
                    let res = md5.complete()
                    
                    let reference: CachedSentMediaReferenceKey = .image(hash: res)
                    if forceRefresh {
                        subscriber.putNext(.single(.localReference(reference)))
                    } else {
                        subscriber.putNext(cachedSentMediaReference(postbox: postbox, key: reference)
                            |> mapError { _ -> PendingMessageUploadError in } |> map { media -> PredownloadedResource in
                            if let media = media {
                                return .media(media, reference)
                            } else {
                                return .localReference(reference)
                            }
                        })
                    }
                    subscriber.putCompletion()
                } else {
                    subscriber.putNext(.single(.localReference(nil)))
                    subscriber.putCompletion()
                }
            }
        })
        let fetched = postbox.mediaBox.fetchedResource(resource, parameters: nil).start(error: { _ in
            subscriber.putError(.generic)
        })
        
        return ActionDisposable {
            data.dispose()
            fetched.dispose()
        }
    }
    |> switchToLatest
}

private func maybePredownloadedFileResource(postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, peerId: PeerId, resource: MediaResource, autoRemove: Bool, forceRefresh: Bool) -> Signal<PredownloadedResource, PendingMessageUploadError> {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return .single(.none)
    }
    
    if autoRemove {
        return .single(.none)
    }
    
    #if DEBUG
    if !"".isEmpty {
        return .single(.none)
    }
    #endif
    
    return auxiliaryMethods.fetchResourceMediaReferenceHash(resource)
    |> mapToSignal { hash -> Signal<PredownloadedResource, NoError> in
        if let hash = hash {
            let reference: CachedSentMediaReferenceKey = .file(hash: hash)
            if forceRefresh {
                return .single(.localReference(reference))
            }
            return cachedSentMediaReference(postbox: postbox, key: reference) |> map { media -> PredownloadedResource in
                if let media = media {
                    return .media(media, reference)
                } else {
                    return .localReference(reference)
                }
            }
        } else {
            return .single(.localReference(nil))
        }
    }
    |> mapError { _ -> PendingMessageUploadError in }
}

private func maybeCacheUploadedResource(postbox: Postbox, key: CachedSentMediaReferenceKey?, result: PendingMessageUploadedContentResult, media: Media) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> {
    if let key = key {
        return postbox.transaction { transaction -> PendingMessageUploadedContentResult in
            storeCachedSentMediaReference(transaction: transaction, key: key, media: media)
            return result
        } |> mapError { _ -> PendingMessageUploadError in }
    } else {
        return .single(result)
    }
}

private func uploadedMediaImageContent(network: Network, postbox: Postbox, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, forceReupload: Bool, isGrouped: Bool, peerId: PeerId, image: TelegramMediaImage, messageId: MessageId?, text: String, attributes: [MessageAttribute], autoremoveMessageAttribute: AutoremoveTimeoutMessageAttribute?, autoclearMessageAttribute: AutoclearTimeoutMessageAttribute?, auxiliaryMethods: AccountAuxiliaryMethods) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> {
    guard let largestRepresentation = largestImageRepresentation(image.representations) else {
        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .text(text), reuploadInfo: nil, cacheReferenceKey: nil)))
    }
    
/*#if DEBUG
if "".isEmpty {
    return auxiliaryMethods.backgroundUpload(postbox, network, largestRepresentation.resource)
    |> castError(PendingMessageUploadError.self)
    |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
        if let result = result {
            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(
                content: .text(result),
                reuploadInfo: nil,
                cacheReferenceKey: nil
            )))
        } else {
            return .fail(.generic)
        }
    }
}
#endif*/
    
    let predownloadedResource: Signal<PredownloadedResource, PendingMessageUploadError> = maybePredownloadedImageResource(postbox: postbox, peerId: peerId, resource: largestRepresentation.resource, forceRefresh: forceReupload)
    return predownloadedResource
    |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
        var referenceKey: CachedSentMediaReferenceKey?
        switch result {
            case let .media(media, key):
                if !forceReupload, let image = media as? TelegramMediaImage, let reference = image.reference, case let .cloud(id, accessHash, maybeFileReference) = reference, let fileReference = maybeFileReference {
                    var flags: Int32 = 0
                    var ttlSeconds: Int32?
                    if let autoclearMessageAttribute = autoclearMessageAttribute {
                        flags |= 1 << 0
                        ttlSeconds = autoclearMessageAttribute.timeout
                    }
                    
                    for attribute in attributes {
                        if let _ = attribute as? MediaSpoilerMessageAttribute {
                            flags |= 1 << 1
                        }
                    }
                    return .single(.progress(PendingMessageUploadedContentProgress(progress: 1.0)))
                    |> then(
                        .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaPhoto(flags: flags, id: .inputPhoto(id: id, accessHash: accessHash, fileReference: Buffer(data: fileReference)), ttlSeconds: ttlSeconds), text), reuploadInfo: nil, cacheReferenceKey: nil)))
                    )
                }
                referenceKey = key
            case let .localReference(key):
                referenceKey = key
            case .none:
                referenceKey = nil
        }
        
        var alreadyTransformed = false
        for attribute in attributes {
            if let attribute = attribute as? OutgoingMessageInfoAttribute {
                if attribute.flags.contains(.transformedMedia) {
                    alreadyTransformed = true
                }
            }
        }
        let transform: Signal<UploadedMediaTransform, NoError>
        if let transformOutgoingMessageMedia = transformOutgoingMessageMedia, let messageId = messageId, !alreadyTransformed {
            transform = .single(.pending)
            |> then(
                transformOutgoingMessageMedia(postbox, network, .standalone(media: image), false)
                |> mapToSignal { mediaReference -> Signal<UploadedMediaTransform, NoError> in
                    return postbox.transaction { transaction -> UploadedMediaTransform in
                        if let media = mediaReference?.media {
                            if let id = media.id {
                                let _ = transaction.updateMedia(id, update: media)
                                transaction.updateMessage(messageId, update: { currentMessage in
                                    var storeForwardInfo: StoreMessageForwardInfo?
                                    if let forwardInfo = currentMessage.forwardInfo {
                                        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: nil, psaType: nil, flags: [])
                                    }
                                    var updatedAttributes = currentMessage.attributes
                                    
                                    var markTransformedMedia = true
                                    var updatedMedia = currentMessage.media
                                    if let paidContent = updatedMedia.first(where: { $0 is TelegramMediaPaidContent }) as? TelegramMediaPaidContent {
                                        var extendedMedia = paidContent.extendedMedia
                                        if let index = extendedMedia.firstIndex(where: { media in
                                            if case let .full(fullMedia) = media, fullMedia.id == id {
                                                return true
                                            } else {
                                                return false
                                            }
                                        }) {
                                            extendedMedia[index] = .full(media: media)
                                        }
                                        updatedMedia = [TelegramMediaPaidContent(amount: paidContent.amount, extendedMedia: extendedMedia)]
                                        
                                        if extendedMedia.contains(where: { media in
                                            if case .preview = media {
                                                return true
                                            } else {
                                                return false
                                            }
                                        }) {
                                            markTransformedMedia = false
                                        }
                                    }
                                    
                                    if markTransformedMedia {
                                        if let index = updatedAttributes.firstIndex(where: { $0 is OutgoingMessageInfoAttribute }){
                                            let attribute = updatedAttributes[index] as! OutgoingMessageInfoAttribute
                                            updatedAttributes[index] = attribute.withUpdatedFlags(attribute.flags.union([.transformedMedia]))
                                        } else {
                                            updatedAttributes.append(OutgoingMessageInfoAttribute(uniqueId: Int64.random(in: Int64.min ... Int64.max), flags: [.transformedMedia], acknowledged: false, correlationId: nil, bubbleUpEmojiOrStickersets: []))
                                        }
                                    }
                                    
                                    return .update(StoreMessage(id: currentMessage.id, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: updatedMedia))
                                })
                            }
                            return .done(media)
                        } else {
                            return .done(image)
                        }
                    }
                }
            )
        } else {
            transform = .single(.done(image))
        }
        
        return transform
        |> mapError { _ -> PendingMessageUploadError in
        }
        |> mapToSignal { transformResult -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
            switch transformResult {
            case .pending:
                return .single(.progress(PendingMessageUploadedContentProgress(progress: 0.0)))
            case let .done(transformedMedia):
                let transformedImage = (transformedMedia as? TelegramMediaImage) ?? image
                guard let largestRepresentation = largestImageRepresentation(transformedImage.representations) else {
                    return .fail(.generic)
                }
                let imageReference: AnyMediaReference
                if let partialReference = transformedImage.partialReference {
                    imageReference = partialReference.mediaReference(transformedImage)
                } else {
                    imageReference = .standalone(media: transformedImage)
                }
                return multipartUpload(network: network, postbox: postbox, source: .resource(imageReference.resourceReference(largestRepresentation.resource)), encrypt: peerId.namespace == Namespaces.Peer.SecretChat, tag: TelegramMediaResourceFetchTag(statsCategory: .image, userContentType: .image), hintFileSize: nil, hintFileIsLarge: false, forceNoBigParts: false)
                |> mapError { _ -> PendingMessageUploadError in return .generic }
                |> mapToSignal { next -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                    switch next {
                        case let .progress(progress):
                            return .single(.progress(PendingMessageUploadedContentProgress(progress: progress)))
                        case let .inputFile(file):
                            var flags: Int32 = 0
                            var ttlSeconds: Int32?
                            if let autoclearMessageAttribute = autoclearMessageAttribute {
                                flags |= 1 << 1
                                ttlSeconds = autoclearMessageAttribute.timeout
                            }
                            var stickers: [Api.InputDocument]?
                            var hasSpoiler = false
                            for attribute in attributes {
                                if let attribute = attribute as? EmbeddedMediaStickersMessageAttribute {
                                    var stickersValue: [Api.InputDocument] = []
                                    for file in attribute.files {
                                        if let resource = file.resource as? CloudDocumentMediaResource, let fileReference = resource.fileReference {
                                            stickersValue.append(Api.InputDocument.inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: fileReference)))
                                        }
                                    }
                                    if !stickersValue.isEmpty {
                                        stickers = stickersValue
                                        flags |= 1 << 0
                                    }
                                } else if let _ = attribute as? MediaSpoilerMessageAttribute {
                                    flags |= 1 << 2
                                    hasSpoiler = true
                                }
                            }
                            return postbox.transaction { transaction -> Api.InputPeer? in
                                return transaction.getPeer(peerId).flatMap(apiInputPeer)
                            }
                            |> mapError { _ -> PendingMessageUploadError in }
                            |> mapToSignal { inputPeer -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                                if let inputPeer = inputPeer {
                                    if autoclearMessageAttribute != nil {
                                        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaUploadedPhoto(flags: flags, file: file, stickers: stickers, ttlSeconds: ttlSeconds), text), reuploadInfo: nil, cacheReferenceKey: nil)))
                                    }
                                    
                                    return network.request(Api.functions.messages.uploadMedia(flags: 0, businessConnectionId: nil, peer: inputPeer, media: Api.InputMedia.inputMediaUploadedPhoto(flags: flags, file: file, stickers: stickers, ttlSeconds: ttlSeconds)))
                                    |> mapError { _ -> PendingMessageUploadError in return .generic }
                                    |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                                        switch result {
                                            case let .messageMediaPhoto(_, photo, _):
                                                if let photo = photo, let mediaImage = telegramMediaImageFromApiPhoto(photo), let reference = mediaImage.reference, case let .cloud(id, accessHash, maybeFileReference) = reference, let fileReference = maybeFileReference {
                                                    var flags: Int32 = 0
                                                    var ttlSeconds: Int32?
                                                    if let autoclearMessageAttribute = autoclearMessageAttribute {
                                                        flags |= 1 << 0
                                                        ttlSeconds = autoclearMessageAttribute.timeout
                                                    }
                                                    if hasSpoiler {
                                                        flags |= 1 << 1
                                                    }
                                                    
                                                    let result: PendingMessageUploadedContentResult = .content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaPhoto(flags: flags, id: .inputPhoto(id: id, accessHash: accessHash, fileReference: Buffer(data: fileReference)), ttlSeconds: ttlSeconds), text), reuploadInfo: nil, cacheReferenceKey: nil))
                                                    if let _ = ttlSeconds {
                                                        return .single(result)
                                                    } else {
                                                        return maybeCacheUploadedResource(postbox: postbox, key: referenceKey, result: result, media: mediaImage)
                                                    }
                                                }
                                            default:
                                                break
                                        }
                                        return .fail(.generic)
                                    }
                                } else {
                                    return .fail(.generic)
                                }
                            }
                        case let .inputSecretFile(file, size, key):
                            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .secretMedia(file, size, key), reuploadInfo: nil, cacheReferenceKey: nil)))
                    }
                }
            }
        }
    }
}

func inputDocumentAttributesFromFileAttributes(_ fileAttributes: [TelegramMediaFileAttribute]) -> [Api.DocumentAttribute] {
    var attributes: [Api.DocumentAttribute] = []
    for attribute in fileAttributes {
        switch attribute {
            case .Animated:
                attributes.append(.documentAttributeAnimated)
            case let .FileName(fileName):
                attributes.append(.documentAttributeFilename(fileName: fileName))
            case let .ImageSize(size):
                attributes.append(.documentAttributeImageSize(w: Int32(size.width), h: Int32(size.height)))
            case let .Sticker(displayText, packReference, maskCoords):
                var stickerSet: Api.InputStickerSet = .inputStickerSetEmpty
                var flags: Int32 = 0
                if let packReference = packReference {
                    switch packReference {
                        case let .id(id, accessHash):
                            stickerSet = .inputStickerSetID(id: id, accessHash: accessHash)
                        case let .name(name):
                            stickerSet = .inputStickerSetShortName(shortName: name)
                        default:
                            stickerSet = .inputStickerSetEmpty
                    }
                }
                var inputMaskCoords: Api.MaskCoords?
                if let maskCoords = maskCoords {
                    flags |= 1 << 0
                    inputMaskCoords = .maskCoords(n: maskCoords.n, x: maskCoords.x, y: maskCoords.y, zoom: maskCoords.zoom)
                }
                attributes.append(.documentAttributeSticker(flags: flags, alt: displayText, stickerset: stickerSet, maskCoords: inputMaskCoords))
            case .HasLinkedStickers:
                attributes.append(.documentAttributeHasStickers)
            case let .Video(duration, size, videoFlags, preloadSize, coverTime, videoCodec):
                var flags: Int32 = 0
                if videoFlags.contains(.instantRoundVideo) {
                    flags |= (1 << 0)
                }
                if videoFlags.contains(.supportsStreaming) {
                    flags |= (1 << 1)
                }
                if preloadSize != nil {
                    flags |= (1 << 2)
                }
                if videoFlags.contains(.isSilent) {
                    flags |= (1 << 3)
                }
                if let coverTime = coverTime, coverTime > 0.0 {
                    flags |= (1 << 4)
                }
                if videoCodec != nil {
                    flags |= (1 << 5)
                }
                attributes.append(.documentAttributeVideo(flags: flags, duration: duration, w: Int32(size.width), h: Int32(size.height), preloadPrefixSize: preloadSize, videoStartTs: coverTime, videoCodec: videoCodec))
            case let .Audio(isVoice, duration, title, performer, waveform):
                var flags: Int32 = 0
                if isVoice {
                    flags |= Int32(1 << 10)
                }
                if let _ = title {
                    flags |= Int32(1 << 0)
                }
                if let _ = performer {
                    flags |= Int32(1 << 1)
                }
                var waveformBuffer: Buffer?
                if let waveform = waveform {
                    flags |= Int32(1 << 2)
                    waveformBuffer = Buffer(data: waveform)
                }
                attributes.append(.documentAttributeAudio(flags: flags, duration: Int32(duration), title: title, performer: performer, waveform: waveformBuffer))
            case .hintFileIsLarge:
                break
            case .hintIsValidated:
                break
            case .NoPremium:
                break
        case .CustomEmoji:
                break
        }
    }
    return attributes
}

private enum UploadedMediaTransform {
    case pending
    case done(Media?)
}

private enum UploadedMediaThumbnailResult {
    case file(Api.InputFile)
    case photo(Api.InputPhoto)
    case none
}

private enum UploadedMediaFileAndThumbnail {
    case pending
    case done(TelegramMediaFile, UploadedMediaThumbnailResult, UploadedMediaThumbnailResult)
}

private func uploadedThumbnail(network: Network, postbox: Postbox, resourceReference: MediaResourceReference, forceNoBigParts: Bool = false) -> Signal<Api.InputFile?, PendingMessageUploadError> {
    return multipartUpload(network: network, postbox: postbox, source: .resource(resourceReference), encrypt: false, tag: TelegramMediaResourceFetchTag(statsCategory: .image, userContentType: .image), hintFileSize: nil, hintFileIsLarge: false, forceNoBigParts: forceNoBigParts)
    |> mapError { _ -> PendingMessageUploadError in return .generic }
    |> mapToSignal { result -> Signal<Api.InputFile?, PendingMessageUploadError> in
        switch result {
            case .progress:
                return .complete()
            case let .inputFile(inputFile):
                return .single(inputFile)
            case .inputSecretFile:
                return .single(nil)
        }
    }
}

private func uploadedVideoCover(network: Network, postbox: Postbox, resourceReference: MediaResourceReference, peerId: PeerId) -> Signal<Api.InputPhoto?, PendingMessageUploadError> {
    return postbox.transaction { transaction -> Api.InputPeer? in
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> castError(PendingMessageUploadError.self)
    |> mapToSignal { inputPeer -> Signal<Api.InputPhoto?, PendingMessageUploadError> in
        guard let inputPeer else {
            return .single(.inputPhotoEmpty)
        }
        return multipartUpload(network: network, postbox: postbox, source: .resource(resourceReference), encrypt: false, tag: TelegramMediaResourceFetchTag(statsCategory: .image, userContentType: .image), hintFileSize: nil, hintFileIsLarge: false, forceNoBigParts: true)
        |> mapError { _ -> PendingMessageUploadError in return .generic }
        |> mapToSignal { result -> Signal<Api.InputPhoto?, PendingMessageUploadError> in
            switch result {
            case .progress:
                return .complete()
            case let .inputFile(file):
                return network.request(Api.functions.messages.uploadMedia(flags: 0, businessConnectionId: nil, peer: inputPeer, media: Api.InputMedia.inputMediaUploadedPhoto(flags: 0, file: file, stickers: [], ttlSeconds: nil)))
                |> mapError { _ -> PendingMessageUploadError in return .generic }
                |> map { uploadResult in
                    switch uploadResult {
                    case let .messageMediaPhoto(_, photo, _):
                        if case let .photo(_, id, accessHash, fileReference, _, _, _, _) = photo {
                            return .inputPhoto(id: id, accessHash: accessHash, fileReference: fileReference)
                        } else {
                            return .inputPhotoEmpty
                        }
                    default:
                        return .inputPhotoEmpty
                    }
                }
            case .inputSecretFile:
                return .single(nil)
            }
        }
    }
}

public func statsCategoryForFileWithAttributes(_ attributes: [TelegramMediaFileAttribute]) -> MediaResourceStatsCategory {
    for attribute in attributes {
        switch attribute {
            case let .Audio(isVoice, _, _, _, _):
                if isVoice {
                    return .voiceMessages
                } else {
                    return .audio
                }
            case let .Video(_, _, flags, _, _, _):
                if flags.contains(TelegramMediaVideoFlags.instantRoundVideo) {
                    return .voiceMessages
                } else {
                    return .video
                }
            default:
                break
        }
    }
    return .file
}

private func uploadedMediaFileContent(network: Network, postbox: Postbox, auxiliaryMethods: AccountAuxiliaryMethods, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, forceReupload: Bool, isGrouped: Bool, isPaid: Bool, passFetchProgress: Bool, forceNoBigParts: Bool, peerId: PeerId, messageId: MessageId?, text: String, attributes: [MessageAttribute], autoremoveMessageAttribute: AutoremoveTimeoutMessageAttribute?, autoclearMessageAttribute: AutoclearTimeoutMessageAttribute?, file: TelegramMediaFile) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> {
    return maybePredownloadedFileResource(postbox: postbox, auxiliaryMethods: auxiliaryMethods, peerId: peerId, resource: file.resource, autoRemove: autoremoveMessageAttribute != nil || autoclearMessageAttribute != nil, forceRefresh: forceReupload)
    |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
        var referenceKey: CachedSentMediaReferenceKey?
        switch result {
            case let .media(media, key):
                if !forceReupload, let file = media as? TelegramMediaFile, let resource = file.resource as? CloudDocumentMediaResource, let fileReference = resource.fileReference {
                    var videoCoverSignal: Signal<UploadedMediaThumbnailResult, PendingMessageUploadError> = .single(.none)
                    if let cover = file.videoCover, let resource = cover.representations.first?.resource {
                        let fileReference: AnyMediaReference
                        if let partialReference = file.partialReference {
                            fileReference = partialReference.mediaReference(media)
                        } else {
                            fileReference = .standalone(media: media)
                        }
                        videoCoverSignal = uploadedVideoCover(network: network, postbox: postbox, resourceReference: fileReference.resourceReference(resource), peerId: peerId)
                        |> mapError { _ -> PendingMessageUploadError in return .generic }
                        |> map { result in
                            if let result = result {
                                return .photo(result)
                            } else {
                                return .none
                            }
                        }
                    }
                    
                    return videoCoverSignal
                    |> mapToSignal { videoCover -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                        var flags: Int32 = 0
                        var ttlSeconds: Int32?
                        var videoTimestamp: Int32?
                        if let autoclearMessageAttribute = autoclearMessageAttribute {
                            flags |= 1 << 0
                            ttlSeconds = autoclearMessageAttribute.timeout
                        }
                        
                        for attribute in attributes {
                            if let _ = attribute as? MediaSpoilerMessageAttribute {
                                flags |= 1 << 2
                            } else if let attribute = attribute as? ForwardVideoTimestampAttribute {
                                flags |= (1 << 4)
                                videoTimestamp = attribute.timestamp
                            }
                        }
                        
                        var videoCoverPhoto: Api.InputPhoto?
                        if case let .photo(photo) = videoCover {
                            videoCoverPhoto = photo
                        }
                        if let _ = videoCoverPhoto {
                            flags |= 1 << 3
                        }
                        
                        return .single(.progress(PendingMessageUploadedContentProgress(progress: 1.0)))
                        |> then(
                            .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(Api.InputMedia.inputMediaDocument(flags: flags, id: Api.InputDocument.inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: fileReference)), videoCover: videoCoverPhoto, videoTimestamp: videoTimestamp, ttlSeconds: ttlSeconds, query: nil), text), reuploadInfo: nil, cacheReferenceKey: nil)))
                        )
                    }
                }
                referenceKey = key
            case let .localReference(key):
                referenceKey = key
            case .none:
                referenceKey = nil
        }
        
        var hintFileIsLarge = false
        var hintSize: Int64?
        if let size = file.size {
            hintSize = size
        } else if let resource = file.resource as? LocalFileReferenceMediaResource, let size = resource.size {
            hintSize = size
        }
        
        loop: for attribute in file.attributes {
            switch attribute {
                case .hintFileIsLarge:
                    hintFileIsLarge = true
                    break loop
                default:
                    break
            }
        }
        
        let fileReference: AnyMediaReference
        if let partialReference = file.partialReference {
            fileReference = partialReference.mediaReference(file)
        } else {
            fileReference = .standalone(media: file)
        }
        let upload: Signal<MultipartUploadResult?, PendingMessageUploadError> = .single(nil)
        |> then(
            messageMediaPreuploadManager.upload(network: network, postbox: postbox, source: .resource(fileReference.resourceReference(file.resource)), encrypt: peerId.namespace == Namespaces.Peer.SecretChat, tag: TelegramMediaResourceFetchTag(statsCategory: statsCategoryForFileWithAttributes(file.attributes), userContentType: nil), hintFileSize: hintSize, hintFileIsLarge: hintFileIsLarge, forceNoBigParts: forceNoBigParts)
            |> mapError { _ -> PendingMessageUploadError in return .generic }
            |> map(Optional.init)
        )
        let resourceStatus: Signal<MediaResourceStatus?, PendingMessageUploadError>
        if passFetchProgress {
            resourceStatus = postbox.mediaBox.resourceStatus(file.resource)
            |> castError(PendingMessageUploadError.self)
            |> map(Optional.init)
        } else {
            resourceStatus = .single(nil)
        }
        var alreadyTransformed = false
        for attribute in attributes {
            if let attribute = attribute as? OutgoingMessageInfoAttribute {
                if attribute.flags.contains(.transformedMedia) {
                    alreadyTransformed = true
                }
            }
        }
    
        let transform: Signal<UploadedMediaTransform, NoError>
        if let transformOutgoingMessageMedia = transformOutgoingMessageMedia, let messageId = messageId, !alreadyTransformed {
            transform = .single(.pending)
            |> then(transformOutgoingMessageMedia(postbox, network, .standalone(media: file), false)
            |> mapToSignal { mediaReference -> Signal<UploadedMediaTransform, NoError> in
                return postbox.transaction { transaction -> UploadedMediaTransform in
                    if let media = mediaReference?.media {
                        if let id = media.id {
                            let _ = transaction.updateMedia(id, update: media)
                            transaction.updateMessage(messageId, update: { currentMessage in
                                var storeForwardInfo: StoreMessageForwardInfo?
                                if let forwardInfo = currentMessage.forwardInfo {
                                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: nil, psaType: nil, flags: [])
                                }
                                var updatedAttributes = currentMessage.attributes
                                
                                var markTransformedMedia = true
                                var updatedMedia = currentMessage.media
                                if let paidContent = updatedMedia.first(where: { $0 is TelegramMediaPaidContent }) as? TelegramMediaPaidContent {
                                    var extendedMedia = paidContent.extendedMedia
                                    if let index = extendedMedia.firstIndex(where: { media in
                                        if case let .full(fullMedia) = media, fullMedia.id == id {
                                            return true
                                        } else {
                                            return false
                                        }
                                    }) {
                                        extendedMedia[index] = .full(media: media)
                                    }
                                    updatedMedia = [TelegramMediaPaidContent(amount: paidContent.amount, extendedMedia: extendedMedia)]
                                    
                                    if extendedMedia.contains(where: { media in
                                        if case .preview = media {
                                            return true
                                        } else {
                                            return false
                                        }
                                    }) {
                                        markTransformedMedia = false
                                    }
                                }
                                
                                if markTransformedMedia {
                                    if let index = updatedAttributes.firstIndex(where: { $0 is OutgoingMessageInfoAttribute }){
                                        let attribute = updatedAttributes[index] as! OutgoingMessageInfoAttribute
                                        updatedAttributes[index] = attribute.withUpdatedFlags(attribute.flags.union([.transformedMedia]))
                                    } else {
                                        updatedAttributes.append(OutgoingMessageInfoAttribute(uniqueId: Int64.random(in: Int64.min ... Int64.max), flags: [.transformedMedia], acknowledged: false, correlationId: nil, bubbleUpEmojiOrStickersets: []))
                                    }
                                }
                                
                                return .update(StoreMessage(id: currentMessage.id, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: updatedMedia))
                            })
                        }
                        return .done(media)
                    } else {
                        return .done(file)
                    }
                }
            })
        } else {
            transform = .single(.done(file))
        }
    
        let transformedFileAndThumbnail: Signal<UploadedMediaFileAndThumbnail, PendingMessageUploadError> = .single(.pending)
        |> then(transform
        |> mapToSignalPromotingError { media -> Signal<UploadedMediaFileAndThumbnail, PendingMessageUploadError> in
            switch media {
                case .pending:
                    return .single(.pending)
                case let .done(media):
                    if peerId.namespace == Namespaces.Peer.SecretChat {
                        return .single(.done(file, .none, .none))
                    } else {
                        var thumbnailSignal: Signal<UploadedMediaThumbnailResult, PendingMessageUploadError> = .single(.none)
                        var videoCoverSignal: Signal<UploadedMediaThumbnailResult, PendingMessageUploadError> = .single(.none)
                        
                        if let media = media as? TelegramMediaFile {
                            if let smallestThumbnail = smallestImageRepresentation(media.previewRepresentations) {
                                let fileReference: AnyMediaReference
                                if let partialReference = media.partialReference {
                                    fileReference = partialReference.mediaReference(media)
                                } else {
                                    fileReference = .standalone(media: media)
                                }
                                thumbnailSignal = uploadedThumbnail(network: network, postbox: postbox, resourceReference: fileReference.resourceReference(smallestThumbnail.resource), forceNoBigParts: forceNoBigParts)
                                |> mapError { _ -> PendingMessageUploadError in return .generic }
                                |> map { result in
                                    if let result = result {
                                        return .file(result)
                                    } else {
                                        return .none
                                    }
                                }
                            }
                            if let cover = media.videoCover, let resource = cover.representations.first?.resource {
                                let fileReference: AnyMediaReference
                                if let partialReference = media.partialReference {
                                    fileReference = partialReference.mediaReference(media)
                                } else {
                                    fileReference = .standalone(media: media)
                                }
                                videoCoverSignal = uploadedVideoCover(network: network, postbox: postbox, resourceReference: fileReference.resourceReference(resource), peerId: peerId)
                                |> mapError { _ -> PendingMessageUploadError in return .generic }
                                |> map { result in
                                    if let result = result {
                                        return .photo(result)
                                    } else {
                                        return .none
                                    }
                                }
                            }
                            return combineLatest(
                                thumbnailSignal,
                                videoCoverSignal
                            )
                            |> map { thumbnail, videoCover in
                                return .done(media, thumbnail, videoCover)
                            }
                        } else {
                            return .single(.done(file, .none, .none))
                        }
                    }
            }
        })
            
        return combineLatest(upload, transformedFileAndThumbnail, resourceStatus)
        |> mapToSignal { content, fileAndThumbnailResult, resourceStatus -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
            guard let content = content else {
                if let resourceStatus = resourceStatus, case let .Fetching(_, progress) = resourceStatus {
                    return .single(.progress(PendingMessageUploadedContentProgress(progress: progress * 0.33)))
                }
                return .complete()
            }
            switch content {
                case let .progress(progress):
                    var progress = progress
                    if passFetchProgress {
                        progress = 0.33 + progress * 0.67
                    }
                    return .single(.progress(PendingMessageUploadedContentProgress(progress: progress)))
                case let .inputFile(inputFile):
                    if case let .done(file, thumbnail, videoCover) = fileAndThumbnailResult {
                        var flags: Int32 = 0
                        
                        var hasSpoiler = false
                        var thumbnailFile: Api.InputFile?
                        var videoCoverPhoto: Api.InputPhoto?
                        if case let .file(file) = thumbnail {
                            thumbnailFile = file
                        }
                        if case let .photo(photo) = videoCover {
                            videoCoverPhoto = photo
                        }
                        
                        if let _ = thumbnailFile {
                            flags |= 1 << 2
                        }
                        if let _ = videoCoverPhoto {
                            flags |= 1 << 6
                        }
                        
                        var ttlSeconds: Int32?
                        var videoTimestamp: Int32?
                        for attribute in attributes {
                            if let attribute = attribute as? AutoclearTimeoutMessageAttribute {
                                flags |= 1 << 1
                                ttlSeconds = attribute.timeout
                            } else if let _ = attribute as? MediaSpoilerMessageAttribute {
                                flags |= 1 << 5
                                hasSpoiler = true
                            } else if let attribute = attribute as? ForwardVideoTimestampAttribute {
                                videoTimestamp = attribute.timestamp
                            }
                        }
                        
                        if !file.isAnimated || isPaid {
                            flags |= 1 << 3
                        }
                        
                        if !file.isVideo && file.mimeType.hasPrefix("video/") {
                            flags |= 1 << 4
                        }
                        
                        var stickers: [Api.InputDocument]?
                        for attribute in attributes {
                            if let attribute = attribute as? EmbeddedMediaStickersMessageAttribute {
                                var stickersValue: [Api.InputDocument] = []
                                for file in attribute.files {
                                    if let resource = file.resource as? CloudDocumentMediaResource, let fileReference = resource.fileReference {
                                        stickersValue.append(Api.InputDocument.inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: fileReference)))
                                    }
                                }
                                if !stickersValue.isEmpty {
                                    stickers = stickersValue
                                    flags |= 1 << 0
                                }
                                break
                            }
                        }
                        
                        if videoTimestamp != nil {
                            flags |= 1 << 7
                        }
                        
                        if ttlSeconds != nil {
                            return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaUploadedDocument(flags: flags, file: inputFile, thumb: thumbnailFile, mimeType: file.mimeType, attributes: inputDocumentAttributesFromFileAttributes(file.attributes), stickers: stickers, videoCover: videoCoverPhoto, videoTimestamp: videoTimestamp, ttlSeconds: ttlSeconds), text), reuploadInfo: nil, cacheReferenceKey: referenceKey)))
                        }
                        
                        if !isGrouped {
                            let resultInfo = PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaUploadedDocument(flags: flags, file: inputFile, thumb: thumbnailFile, mimeType: file.mimeType, attributes: inputDocumentAttributesFromFileAttributes(file.attributes), stickers: stickers, videoCover: videoCoverPhoto, videoTimestamp: videoTimestamp, ttlSeconds: ttlSeconds), text), reuploadInfo: nil, cacheReferenceKey: referenceKey)
                            
                            return .single(.content(resultInfo))
                        }
                        
                        return postbox.transaction { transaction -> Api.InputPeer? in
                            return transaction.getPeer(peerId).flatMap(apiInputPeer)
                        }
                        |> mapError { _ -> PendingMessageUploadError in }
                        |> mapToSignal { inputPeer -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                            if let inputPeer = inputPeer {
                                return network.request(Api.functions.messages.uploadMedia(flags: 0, businessConnectionId: nil, peer: inputPeer, media: .inputMediaUploadedDocument(flags: flags, file: inputFile, thumb: thumbnailFile, mimeType: file.mimeType, attributes: inputDocumentAttributesFromFileAttributes(file.attributes), stickers: stickers, videoCover: videoCoverPhoto, videoTimestamp: videoTimestamp, ttlSeconds: ttlSeconds)))
                                |> mapError { _ -> PendingMessageUploadError in return .generic }
                                |> mapToSignal { result -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> in
                                    switch result {
                                        case let .messageMediaDocument(_, document, altDocuments, _, _, _):
                                        if let document = document, let mediaFile = telegramMediaFileFromApiDocument(document, altDocuments: altDocuments), let resource = mediaFile.resource as? CloudDocumentMediaResource, let fileReference = resource.fileReference {
                                                var flags: Int32 = 0
                                                var ttlSeconds: Int32?
                                                if let autoclearMessageAttribute = autoclearMessageAttribute {
                                                    flags |= 1 << 0
                                                    ttlSeconds = autoclearMessageAttribute.timeout
                                                }
                                                if hasSpoiler {
                                                    flags |= (1 << 2)
                                                }
                                                if let _ = videoCoverPhoto {
                                                    flags |= (1 << 3)
                                                }
                                                if videoTimestamp != nil {
                                                    flags |= (1 << 4)
                                                }
                                            
                                                let result: PendingMessageUploadedContentResult = .content(PendingMessageUploadedContentAndReuploadInfo(content: .media(.inputMediaDocument(flags: flags, id: .inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: fileReference)), videoCover: videoCoverPhoto, videoTimestamp: videoTimestamp, ttlSeconds: ttlSeconds, query: nil), text), reuploadInfo: nil, cacheReferenceKey: nil))
                                                if let _ = ttlSeconds {
                                                    return .single(result)
                                                } else {
                                                    return maybeCacheUploadedResource(postbox: postbox, key: referenceKey, result: result, media: mediaFile)
                                                }
                                            }
                                        default:
                                            break
                                    }
                                    return .fail(.generic)
                                }
                            } else {
                                return .fail(.generic)
                            }
                        }
                    } else {
                        return .complete()
                    }
                case let .inputSecretFile(file, size, key):
                    if case .done = fileAndThumbnailResult {
                        return .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .secretMedia(file, size, key), reuploadInfo: nil, cacheReferenceKey: nil)))
                    } else {
                        return .complete()
                    }
            }
        }
        |> take(until: { result in
            var complete = false
            switch result {
            case .content:
                complete = true
            case .progress:
                complete = false
            }
            return SignalTakeAction(passthrough: true, complete: complete)
        })
    }
}
