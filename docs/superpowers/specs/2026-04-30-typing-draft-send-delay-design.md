# Typing-Draft Send Delay — Design

**Date:** 2026-04-30
**Component:** `submodules/TelegramCore/Sources/State/PendingMessageManager.swift` (+ minimal Postbox additions)

## Goal

Delay outgoing messages while the peer in the same `(peerId, threadId)` is "live-typing" an incoming message (i.e. `Postbox.combinedView(keys: [.typingDrafts(...)])` reports a non-nil draft for that key). Messages park after their content is fully uploaded, then drain in `messageId.id` order once the typing-draft for that key clears.

## Behavior summary

- **Scope.** All "deliver-now" outgoing message types: regular text/media single sends, grouped media albums, and forwards. Excluded: scheduled messages, secret-chat messages, and Saved Messages (account-self peer).
- **Pipeline.** Uploads run in parallel as they do today. The gate sits between "upload complete" and the actual MTProto send call.
- **Release.** As soon as the typing-draft for the message's `(peerId, threadId)` clears (the view's set no longer contains that key) — no extra grace delay, no upper-bound timeout.
- **Keying.** Strictly per-thread. `threadId == nil` is the normal value for non-threaded chats and gates with `PeerAndThreadId(peerId: ..., threadId: nil)`. The `Message.newTopicThreadId` sentinel does not gate (already handled by `.waitingForNewTopic`).
- **Always-on.** No preference toggle.
- **Composes with paid-message postpone.** Paid postpone gates upload-start; typing-draft gate gates post-upload send. Both must be clear before send.

## Architecture

All logic lives in `PendingMessageManager`. Postbox gains one new public view; no other Postbox API changes.

### Postbox additions

1. New file `submodules/Postbox/Sources/AllTypingDraftsView.swift`:
   - `MutableAllTypingDraftsView: MutablePostboxView`
     - `init(postbox:)` seeds `keys` from `postbox.currentTypingDrafts.keys`.
     - `replay(postbox:transaction:)` diffs against `transaction.updatedTypingDrafts`: insert key when `update.value != nil`, remove when nil. Returns `true` if the set changed.
     - `refreshDueToExternalTransaction(postbox:)` reloads from `postbox.currentTypingDrafts.keys` and returns `true`.
     - `immutableView()` returns an `AllTypingDraftsView`.
   - `public final class AllTypingDraftsView: PostboxView` exposes `public let keys: Set<PeerAndThreadId>`.
2. `submodules/Postbox/Sources/Views.swift`:
   - Add `case allTypingDrafts` to `PostboxViewKey` (no associated payload).
   - Wire constant `Hashable` combine and `==` matching for the new case.
   - Add the `case .allTypingDrafts` arm to `postboxViewForKey` returning `MutableAllTypingDraftsView(postbox:)`.
3. `PostboxImpl.currentTypingDrafts` is `fileprivate(set)`, accessible from view files in the same module. No new accessor needed.

### PendingMessageManager additions

New `PendingMessageState` case:

```swift
case waitingForSendGate(groupId: Int64?, content: PendingMessageUploadedContentAndReuploadInfo)
```

Added to `PendingMessageState.groupId`'s switch. Excluded from `updatePendingMediaUploads`'s upload-progress aggregation.

New stored state on the manager:

```swift
private var liveTypingDraftKeys: Set<PeerAndThreadId> = []
private let allTypingDraftsDisposable = MetaDisposable()
private var forwardSendGateGroups: [PeerAndThreadId: [[(PendingMessageContext, Message, ForwardSourceInfoAttribute)]]] = [:]
```

In `init`, subscribe once:

```swift
self.allTypingDraftsDisposable.set(
    (postbox.combinedView(keys: [.allTypingDrafts])
    |> deliverOn(self.queue)).start(next: { [weak self] view in
        self?.handleLiveTypingDraftsUpdate(view)
    })
)
```

Dispose in `deinit`.

## Gate predicate

```swift
private func isSendGateOpen(for key: PeerAndThreadId) -> Bool {
    return !self.liveTypingDraftKeys.contains(key)
}

private func shouldGateSend(messageId: MessageId, threadId: Int64?) -> Bool {
    if messageId.namespace == Namespaces.Message.ScheduledCloud { return false }
    if messageId.peerId.namespace == Namespaces.Peer.SecretChat { return false }
    if messageId.peerId == self.accountPeerId { return false }
    if threadId == Message.newTopicThreadId { return false }
    return true
}
```

A pending context is gate-applicable if `shouldGateSend(...)` returns true. The gate is open if `isSendGateOpen(...)` returns true. Sites delay the send only when `shouldGateSend && !isSendGateOpen`.

## Gate insertion points

### (a) Single-message — `beginSendingMessage(messageContext:messageId:groupId:content:)`

Today: `groupId == nil → commitSendingSingleMessage`; otherwise `state = .waitingToBeSent(groupId: ..., content: ...)`.

New: when `groupId == nil`, additionally check the gate:

```swift
let key = PeerAndThreadId(peerId: messageId.peerId, threadId: messageContext.threadId)
if shouldGateSend(messageId: messageId, threadId: messageContext.threadId) && !isSendGateOpen(for: key) {
    messageContext.state = .waitingForSendGate(groupId: nil, content: content)
} else {
    self.commitSendingSingleMessage(messageContext: messageContext, messageId: messageId, content: content)
}
```

The grouped path (`groupId != nil`) is unchanged here; gating for albums happens in (b).

### (b) Grouped-album — `commitSendingMessageGroup(groupId:messages:)`

Today: flips every group context to `.sending(groupId:)`, fires `sendGroupMessagesContent`.

New: derive a representative key from the first message's `(peerId, threadId)`. (Group members share both by construction.) If `shouldGateSend && !isSendGateOpen`, flip every group context to `.waitingForSendGate(groupId: groupId, content: <its own content>)` and return. Otherwise unchanged.

`dataForPendingMessageGroup(_ groupId:)` is updated to recognize `.waitingForSendGate(groupId: contextGroupId, ...)` the same way it recognizes `.waitingToBeSent` — i.e. a group becomes "ready" when every member is in `.waitingToBeSent` OR `.waitingForSendGate`. This prevents partial-park deadlocks.

### (c) Forwards — inside `beginSendingMessages`, lines 714–733

Today: builds `countedMessageGroups` and immediately fires `sendGroupMessagesContent` per group.

The pre-existing `messagesToForward` bucketing is by `PeerIdAndNamespace` only — not by `threadId`. The downstream `sendGroupMessagesContent` network call requires thread homogeneity (a forward dispatch targets a single destination thread), so in practice every group already shares `threadId`. The gate uses this assumption: derive the key from `messages[0].1.threadId` of each `countedMessageGroup`. If a future caller violates the assumption, the existing dispatch path is already broken.

New: per group, derive `key = PeerAndThreadId(peerId: messages[0].1.id.peerId, threadId: messages[0].1.threadId)`. If `shouldGateSend && !isSendGateOpen`, flip every context in the group to `.waitingForSendGate(groupId: nil, content: PendingMessageUploadedContentAndReuploadInfo(content: .forward(forwardInfo), reuploadInfo: nil, cacheReferenceKey: nil))` and append the entire `[(PendingMessageContext, Message, ForwardSourceInfoAttribute)]` group to `forwardSendGateGroups[key]`. Otherwise fire as today.

Forward groups within a key drain in FIFO order.

## Drain logic

`drainSendGate(key: PeerAndThreadId)` runs on `self.queue`. Idempotent.

1. **Single-message drain.** Snapshot `messageContexts` filtering on `state == .waitingForSendGate(groupId: nil, ...)` AND `PeerAndThreadId(peerId: contextId.peerId, threadId: context.threadId) == key`. Sort by `messageId.id` ascending. For each, extract the parked `content`, call `commitSendingSingleMessage(messageContext:messageId:content:)`.
2. **Grouped-album drain.** Collect distinct `groupId`s among `.waitingForSendGate(groupId: <non-nil>, ...)` contexts whose key matches. Iterate in ascending min-`messageId.id`-in-group order. For each, call `dataForPendingMessageGroup(groupId)` (which now sees the parked members as ready) and pass the result to `commitSendingMessageGroup(groupId:messages:)`.
3. **Forward drain.** Pop `forwardSendGateGroups.removeValue(forKey: key)`. For each parked group (FIFO): flip every context to `.sending(groupId: nil)`, build the `[(MessageId, PendingMessageUploadedContentAndReuploadInfo)]` array, fire `sendGroupMessagesContent` exactly mirroring the existing forward-fire code (lines 719–731).
4. After (1)–(3), call `updateWaitingUploads(peerId: key.peerId)` and `updatePendingMediaUploads()` once.

`handleLiveTypingDraftsUpdate(_ view: CombinedView)`:

```swift
let view = (view.views[.allTypingDrafts] as? AllTypingDraftsView)
let new = view?.keys ?? []
let cleared = self.liveTypingDraftKeys.subtracting(new)
self.liveTypingDraftKeys = new
for key in cleared {
    self.drainSendGate(key: key)
}
```

Single-emission semantics: a `(false → true)` transition (key newly populated) parks future arrivals only; in-flight `.sending` continues. A `(true → false)` transition fires drain.

## Side effects on existing helpers

- `PendingMessageState.groupId` switch (line 37): add `.waitingForSendGate` case returning the case's `groupId` (forward parking uses `groupId == nil`; grouped-album parking uses the real groupId).
- `updatePendingMediaUploads()` (line 262): `.waitingForSendGate` is **not** treated as uploading. Excluded from the switch (or explicitly returns `default` early).
- `dataForPendingMessageGroup(_ groupId:)` (line 753): add `.waitingForSendGate(contextGroupId, content)` arm — if `contextGroupId == groupId`, append `(context, id, content)` to result, same as the existing `.waitingToBeSent` arm.
- `updatePendingMessageIds(_:)` (line 284): in the existing `for id in removedMessageIds` loop, additionally drop `forwardSendGateGroups[*]` entries whose contained context matches `id`. (Single/album parking is auto-cleaned because parked state lives on the context, which gets `state = .none`.) Implementation: walk the dict, filter out the removed context from each parked group, drop any group that empties out, drop any key whose value-array empties out.

## Edge cases

- **First-emit race.** `liveTypingDraftKeys` initializes to `[]`. If a send is attempted before the first view emit and a draft is actually active, that single message slips through. Tolerated.
- **Saved Messages / secret chats / scheduled / new-topic sentinel.** All explicit skip-cases in `shouldGateSend`.
- **Self-typing on another device.** A draft we authored on another device is treated like any other — our outgoing send to that chat parks until it clears. This is consistent with the design intent (drafts visibly commit before subsequent sends arrive). No author filter.
- **Removed-while-parked.** Handled by `updatePendingMessageIds(_:)` extension above.
- **Re-entrancy.** Drain helpers snapshot work-lists before iterating, so mid-iteration mutations to `messageContexts` (e.g. a fired send completes synchronously) don't corrupt the loop.
- **Paid postpone composition.** Paid postpone gates upload-start; once paid commit fires, upload runs; once upload completes, the typing-draft gate parks at `.waitingForSendGate`; once the draft clears, send fires. Stacked sequentially without interaction.
- **Subscription teardown.** `allTypingDraftsDisposable.dispose()` in `deinit`.

## Testing

This codebase has no unit tests. Verification is via full build + manual exercise:

- Build: `python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError` (prefixed with `source ~/.zshrc 2>/dev/null;`).
- Manual: in a 1:1 chat with another device, induce a live-typing draft on the peer side and confirm an outgoing text send parks (chat shows "sending" status held until draft clears or commits). Repeat for: media single send, grouped media album, forward.
- Negative manual: scheduled message — confirm not gated. Saved Messages — confirm not gated. Secret chat — confirm not gated.

## Out of scope

- Per-chat opt-in toggle.
- Upper-bound timeout / fallback send.
- Grace-delay after draft clears.
- UI affordance ("waiting for X to finish typing…").
- Filtering self-authored drafts.
