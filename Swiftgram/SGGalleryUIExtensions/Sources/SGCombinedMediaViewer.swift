import AccountContext
import Postbox
import SwiftSignalKit
import TelegramCore

/// Gallery-local ordering only: neither source's location/count describes the union.
struct SGCombinedMediaViewerHistory {
    let entries: [MessageHistoryEntry]
    let hasEarlier: Bool
    let hasLater: Bool
}

/// Keeps the existing tag indexes (including saved-message custom tags) independent.
/// Subscribe until the desired snapshot, then dispose, just as for a Postbox history view.
func sgCombinedMediaViewerHistory(
    context: AccountContext,
    location: EngineChatLocationInput,
    anchor: MessageIndex,
    namespaces: MessageIdNamespaces,
    tag: HistoryViewInputTag
) -> Signal<SGCombinedMediaViewerHistory, NoError> {
    func history(_ mediaTag: MessageTags) -> Signal<MessageHistoryView, NoError> {
        let inputTag: HistoryViewInputTag
        switch tag {
        case .tag:
            inputTag = .tag(mediaTag)
        case let .customTag(customTag, _):
            inputTag = .customTag(customTag, mediaTag)
        }
        return context.account.postbox.aroundMessageHistoryViewForLocation(
            location,
            anchor: .index(anchor),
            ignoreMessagesInTimestampRange: nil,
            ignoreMessageIds: Set(),
            count: 50,
            clipHoles: true,
            fixedCombinedReadStates: nil,
            topTaggedMessageIdNamespaces: [],
            tag: inputTag,
            appendMessagesFromTheSameGroup: false,
            namespaces: namespaces,
            orderStatistics: []
        )
        |> map { view, _, _ in
            return view
        }
    }

    // Keep the fallback live while holes fill, rather than retaining a potentially
    // deleted/edited one-shot message. Prefer a tagged history entry below.
    let anchorMessage = context.account.postbox.messageView(anchor.id)
    |> map { view in
        return view.message
    }
    return combineLatest(history(.photoOrVideo), history(.gif), anchorMessage)
    // Filter the pair, not each source: a source can re-enter loading while the
    // other updates, and its previous snapshot must not establish stale coverage.
    // Clipping makes holes observable even in nonempty views. Wait for both tag
    // windows to be hole-free: offline/unfillable holes may delay emission forever.
    // The caller owns loading UI; never emit a partial union that can skip media.
    |> filter { photoView, gifView, _ in
        return [photoView, gifView].allSatisfy { view in
            return !view.isLoading && !view.isAnchorOnlyWhileLoading
                && !view.isLoadingEarlier && !view.holeEarlier && !view.holeLater
        }
    }
    |> map { photoView, gifView, anchorMessage in
        return sgMergeCombinedMediaViewerHistory(
            views: [photoView, gifView],
            anchor: anchor,
            anchorMessage: anchorMessage,
            namespaces: namespaces
        )
    }
}

private func sgMergeCombinedMediaViewerHistory(
    views: [MessageHistoryView],
    anchor: MessageIndex,
    anchorMessage: Message?,
    namespaces: MessageIdNamespaces
) -> SGCombinedMediaViewerHistory {
    var lowerBound: MessageIndex?
    var upperBound: MessageIndex?
    var hasEarlier = false
    var hasLater = false

    for view in views {
        let earlier = view.earlierId != nil || view.holeEarlier || view.isLoadingEarlier
        let later = view.laterId != nil || view.holeLater
        hasEarlier = hasEarlier || earlier
        hasLater = hasLater || later

        // A sparse tag's 50-entry window may span thousands of dense-tag entries.
        // Only the intersection is safe to display: otherwise paging skips the
        // dense entries between the two windows' edges. Exhausted sides impose
        // no bound. The readiness gate above excludes unresolved holes; keeping
        // their directional flags here also makes the merge conservative.
        if earlier {
            let boundary = view.entries.first?.index ?? anchor
            if let current = lowerBound {
                lowerBound = max(current, boundary)
            } else {
                lowerBound = boundary
            }
        }
        if later {
            let boundary = view.entries.last?.index ?? anchor
            if let current = upperBound {
                upperBound = min(current, boundary)
            } else {
                upperBound = boundary
            }
        }
    }

    var entries: [MessageHistoryEntry] = []
    var seenIds = Set<MessageId>()
    for view in views {
        for entry in view.entries {
            let isAnchor = entry.message.id == anchor.id
            if !isAnchor {
                if let lowerBound = lowerBound, entry.index < lowerBound {
                    hasEarlier = true
                    continue
                }
                if let upperBound = upperBound, upperBound < entry.index {
                    hasLater = true
                    continue
                }
            }
            if seenIds.insert(entry.message.id).inserted {
                entries.append(MessageHistoryEntry(
                    message: entry.message,
                    isRead: entry.isRead,
                    location: nil,
                    monthLocation: nil,
                    attributes: entry.attributes
                ))
            }
        }
    }
    if !seenIds.contains(anchor.id), let anchorMessage = anchorMessage,
       namespaces.contains(anchorMessage.id.namespace) {
        entries.append(MessageHistoryEntry(
            message: anchorMessage,
            isRead: false,
            location: nil,
            monthLocation: nil,
            attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false)
        ))
    }
    entries.sort { $0.index < $1.index }
    return SGCombinedMediaViewerHistory(entries: entries, hasEarlier: hasEarlier, hasLater: hasLater)
}
