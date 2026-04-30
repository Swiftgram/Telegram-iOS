# Typing-Draft Send Delay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Park outgoing messages in `PendingMessageManager` after their content is uploaded, releasing them only when the typing-draft for the matching `(peerId, threadId)` clears.

**Architecture:** Add a per-account Postbox view (`.allTypingDrafts`) that exposes the live `Set<PeerAndThreadId>` of currently-active typing drafts. Subscribe once at `PendingMessageManager.init`. Add a parked state (`.waitingForSendGate`) to `PendingMessageState` and a forward parking lot dictionary on the manager. Gate at three sites (single-send, album-send, forward-send); drain on view updates that remove keys.

**Tech Stack:** Swift, Bazel, Postbox view system, SwiftSignalKit.

**Spec:** `docs/superpowers/specs/2026-04-30-typing-draft-send-delay-design.md`

**Build verification command (used by every task that compiles code):**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

This codebase has **no unit tests** (per `CLAUDE.md`). Verification is "full build green" at each step plus manual exercise after final task.

---

## File Structure

**Files created:**
- `submodules/Postbox/Sources/AllTypingDraftsView.swift` — new Postbox view tracking the set of active typing-draft keys.

**Files modified:**
- `submodules/Postbox/Sources/Views.swift` — register the new view key.
- `submodules/TelegramCore/Sources/State/PendingMessageManager.swift` — gate insertion, drain, subscription, parked-state plumbing.

**No BUILD edits needed:** Postbox `BUILD` uses `glob(["Sources/**/*.swift"])`, so the new file is auto-picked up.

---

## Task 1: Add `MutableAllTypingDraftsView` / `AllTypingDraftsView`

**Files:**
- Create: `submodules/Postbox/Sources/AllTypingDraftsView.swift`

This task adds the Postbox view file. It is **not yet wired** into `PostboxViewKey` (Task 2), so this commit alone will not change behavior.

- [ ] **Step 1: Create `AllTypingDraftsView.swift`**

```swift
import Foundation

final class MutableAllTypingDraftsView: MutablePostboxView {
    fileprivate var keys: Set<PeerAndThreadId>

    init(postbox: PostboxImpl) {
        self.keys = Set(postbox.currentTypingDrafts.keys)
    }

    func replay(postbox: PostboxImpl, transaction: PostboxTransaction) -> Bool {
        if transaction.updatedTypingDrafts.isEmpty {
            return false
        }
        var updated = false
        for (key, update) in transaction.updatedTypingDrafts {
            if update.value != nil {
                if self.keys.insert(key).inserted {
                    updated = true
                }
            } else {
                if self.keys.remove(key) != nil {
                    updated = true
                }
            }
        }
        return updated
    }

    func refreshDueToExternalTransaction(postbox: PostboxImpl) -> Bool {
        let new = Set(postbox.currentTypingDrafts.keys)
        if new == self.keys {
            return false
        }
        self.keys = new
        return true
    }

    func immutableView() -> PostboxView {
        return AllTypingDraftsView(self)
    }
}

public final class AllTypingDraftsView: PostboxView {
    public let keys: Set<PeerAndThreadId>

    init(_ view: MutableAllTypingDraftsView) {
        self.keys = view.keys
    }
}
```

- [ ] **Step 2: Verify the build (file is unwired, so it must compile standalone)**

Run the build command from the header. Expected: **success**. Common failure modes: `currentTypingDrafts` access scope (already `fileprivate(set)`, accessible from same-module file); `transaction.updatedTypingDrafts` shape (already `[PeerAndThreadId: PostboxImpl.TypingDraftUpdate]` per `PostboxTransaction.swift:59`).

- [ ] **Step 3: Commit**

```bash
git add submodules/Postbox/Sources/AllTypingDraftsView.swift
git commit -m "Postbox: add AllTypingDraftsView tracking Set<PeerAndThreadId> of active typing drafts"
```

---

## Task 2: Register `.allTypingDrafts` in `PostboxViewKey`

**Files:**
- Modify: `submodules/Postbox/Sources/Views.swift`

- [ ] **Step 1: Add the case to the enum**

In `submodules/Postbox/Sources/Views.swift` line 105, append `.allTypingDrafts` after `.typingDrafts(...)`:

```swift
    case typingDrafts(PeerAndThreadId)
    case allTypingDrafts
```

- [ ] **Step 2: Add hash arm**

In the `hash(into:)` switch (the new arm goes alongside the existing `case let .typingDrafts(peerId):` arm at line 232–233):

```swift
        case let .typingDrafts(peerId):
            hasher.combine(peerId)
        case .allTypingDrafts:
            hasher.combine(22)
```

The constant `22` is the next free hash-tag (existing tags use 0–21).

- [ ] **Step 3: Add `==` arm**

In the `==(lhs:rhs:)` switch (line 551–556 area):

```swift
        case let .typingDrafts(peerId):
            if case .typingDrafts(peerId) = rhs {
                return true
            } else {
                return false
            }
        case .allTypingDrafts:
            if case .allTypingDrafts = rhs {
                return true
            } else {
                return false
            }
```

- [ ] **Step 4: Wire `postboxViewForKey`**

In the `postboxViewForKey(postbox:key:)` switch (line 684–685 area):

```swift
    case let .typingDrafts(peerId):
        return MutableTypingDraftsView(postbox: postbox, peerAndThreadId: peerId)
    case .allTypingDrafts:
        return MutableAllTypingDraftsView(postbox: postbox)
    }
}
```

- [ ] **Step 5: Verify the build**

Run the build command. Expected: **success**. The view is now constructible but no consumer subscribes yet.

- [ ] **Step 6: Commit**

```bash
git add submodules/Postbox/Sources/Views.swift
git commit -m "Postbox: wire .allTypingDrafts view key into PostboxViewKey"
```

---

## Task 3: Add `.waitingForSendGate` state and update related switches

**Files:**
- Modify: `submodules/TelegramCore/Sources/State/PendingMessageManager.swift`

This task introduces the new `PendingMessageState` case and extends every switch that needs to know about it. No gate insertion happens yet — the new case is unreachable, so behavior is unchanged.

- [ ] **Step 1: Add the case to `PendingMessageState`**

Edit `private enum PendingMessageState` (line 28). After the `.waitingToBeSent` case, add:

```swift
    case waitingToBeSent(groupId: Int64?, content: PendingMessageUploadedContentAndReuploadInfo)
    case waitingForSendGate(groupId: Int64?, content: PendingMessageUploadedContentAndReuploadInfo)
```

- [ ] **Step 2: Extend the `groupId` computed property**

In the same `var groupId: Int64?` switch (line 37–54), add an arm right after the `.waitingToBeSent` arm:

```swift
        case let .waitingToBeSent(groupId, _):
            return groupId
        case let .waitingForSendGate(groupId, _):
            return groupId
```

- [ ] **Step 3: Extend `dataForPendingMessageGroup` to accept parked members as ready**

Find `private func dataForPendingMessageGroup(_ groupId: Int64)` (line 753). After the `.waitingToBeSent` arm, add a parallel arm:

```swift
            case let .waitingToBeSent(contextGroupId, content):
                if contextGroupId == groupId {
                    result.append((context, id, content))
                }
            case let .waitingForSendGate(contextGroupId, content):
                if contextGroupId == groupId {
                    result.append((context, id, content))
                }
```

This lets a partially-parked album drain correctly once the gate opens.

- [ ] **Step 4: Exclude parked state from `updatePendingMediaUploads`**

Find `private func updatePendingMediaUploads()` (line 262). Inside its `switch context.state { ... }`, the existing arms cover `.waitingForUploadToStart` and `.uploading`. Parked state is post-upload and should NOT report progress. The switch already has a `default: break` — `.waitingForSendGate` falls through it automatically. **No edit required**, but verify by re-reading the function after the previous edits compile.

- [ ] **Step 5: Verify the build**

Run the build command. Expected: **success**. Swift will reject the build if any `switch context.state { ... }` becomes non-exhaustive — fix any such switches by adding a `case .waitingForSendGate: ...` arm matching the closest existing parallel state. Likely candidates:

- `private enum PendingMessageState`'s `groupId` switch — handled in Step 2.
- `dataForPendingMessageGroup` switch — handled in Step 3.
- The forward branch in `beginSendingMessages` (line ~614, doesn't switch directly).
- Any other `switch <context>.state` blocks (search with `grep -n "switch.*\.state" submodules/TelegramCore/Sources/State/PendingMessageManager.swift`).

If the compiler reports a non-exhaustive switch elsewhere, add an arm that mirrors the `.waitingToBeSent` arm in that switch, or `case .waitingForSendGate: break` if the new state is irrelevant to that site.

- [ ] **Step 6: Commit**

```bash
git add submodules/TelegramCore/Sources/State/PendingMessageManager.swift
git commit -m "PendingMessageManager: add .waitingForSendGate state and update related switches"
```

---

## Task 4: Add manager-level subscription and parked-state fields

**Files:**
- Modify: `submodules/TelegramCore/Sources/State/PendingMessageManager.swift`

Adds the dictionary, the disposable, the subscription in `init`, the disposal in `deinit`, and a stub `handleLiveTypingDraftsUpdate` that only stores the set (drain is wired in Task 5).

- [ ] **Step 1: Add stored fields**

In `public final class PendingMessageManager` (line 205), after the existing `private var pendingMessageIds = Set<MessageId>()` (line 232), add:

```swift
    private var pendingMessageIds = Set<MessageId>()
    private var liveTypingDraftKeys: Set<PeerAndThreadId> = []
    private let allTypingDraftsDisposable = MetaDisposable()
    private var forwardSendGateGroups: [PeerAndThreadId: [[(PendingMessageContext, Message, ForwardSourceInfoAttribute)]]] = [:]
    private let beginSendingMessagesDisposables = DisposableSet()
```

(The first and last lines are already present; the three new lines insert between them.)

- [ ] **Step 2: Subscribe in `init`**

In `init(network:postbox:accountPeerId:auxiliaryMethods:stateManager:localInputActivityManager:messageMediaPreuploadManager:revalidationContext:)` (line 243), after the field assignments (line 252), add:

```swift
        self.revalidationContext = revalidationContext

        let queue = self.queue
        self.allTypingDraftsDisposable.set(
            (postbox.combinedView(keys: [.allTypingDrafts])
            |> deliverOn(queue)).start(next: { [weak self] view in
                self?.handleLiveTypingDraftsUpdate(view)
            })
        )
    }
```

- [ ] **Step 3: Dispose in `deinit`**

In `deinit` (line 255–260), append:

```swift
    deinit {
        self.beginSendingMessagesDisposables.dispose()
        for (_, disposable) in self.newTopicDisposables {
            disposable.dispose()
        }
        self.allTypingDraftsDisposable.dispose()
    }
```

- [ ] **Step 4: Add the handler (no drain yet)**

Add this new private method anywhere in the class (e.g. just before `private func updatePendingMediaUploads()` at line 262):

```swift
    private func handleLiveTypingDraftsUpdate(_ combined: CombinedView) {
        assert(self.queue.isCurrent())

        let new: Set<PeerAndThreadId>
        if let view = combined.views[.allTypingDrafts] as? AllTypingDraftsView {
            new = view.keys
        } else {
            new = []
        }
        self.liveTypingDraftKeys = new
    }
```

This handler is functional — it tracks the live key set correctly. Task 5 augments it to also fire `drainSendGate` for keys that just cleared.

- [ ] **Step 5: Verify the build**

Run the build command. Expected: **success**. `CombinedView` is in scope because `Postbox` is already imported at the top of the file. `MetaDisposable` and `Queue` come from `SwiftSignalKit` (already imported).

- [ ] **Step 6: Commit**

```bash
git add submodules/TelegramCore/Sources/State/PendingMessageManager.swift
git commit -m "PendingMessageManager: subscribe to .allTypingDrafts and add parking-lot fields"
```

---

## Task 5: Add gate predicates, drain, and wire the single-message gate

**Files:**
- Modify: `submodules/TelegramCore/Sources/State/PendingMessageManager.swift`

Combined task: introduces the predicates, the `drainSendGate` body, augments `handleLiveTypingDraftsUpdate` to call drain, and wires the **first** insertion site (single-message). After this task, single non-grouped messages park correctly when the peer is live-typing and unpark when the draft clears.

- [ ] **Step 1: Add `shouldGateSend` and `isSendGateOpen` private helpers**

Anywhere in the `PendingMessageManager` class (group them next to `handleLiveTypingDraftsUpdate` from Task 4):

```swift
    private func shouldGateSend(messageId: MessageId, threadId: Int64?) -> Bool {
        if messageId.namespace == Namespaces.Message.ScheduledCloud {
            return false
        }
        if messageId.peerId.namespace == Namespaces.Peer.SecretChat {
            return false
        }
        if messageId.peerId == self.accountPeerId {
            return false
        }
        if threadId == Message.newTopicThreadId {
            return false
        }
        return true
    }

    private func isSendGateOpen(for key: PeerAndThreadId) -> Bool {
        return !self.liveTypingDraftKeys.contains(key)
    }
```

- [ ] **Step 2: Augment `handleLiveTypingDraftsUpdate` to call drain**

Replace the body of `handleLiveTypingDraftsUpdate(_:)` (added in Task 4) with the cleared-key drain logic:

```swift
    private func handleLiveTypingDraftsUpdate(_ combined: CombinedView) {
        assert(self.queue.isCurrent())

        let new: Set<PeerAndThreadId>
        if let view = combined.views[.allTypingDrafts] as? AllTypingDraftsView {
            new = view.keys
        } else {
            new = []
        }
        let cleared = self.liveTypingDraftKeys.subtracting(new)
        self.liveTypingDraftKeys = new
        for key in cleared {
            self.drainSendGate(key: key)
        }
    }
```

- [ ] **Step 3: Add the `drainSendGate` body**

Add this new private method next to `handleLiveTypingDraftsUpdate`:

```swift
    private func drainSendGate(key: PeerAndThreadId) {
        assert(self.queue.isCurrent())

        // (1) Single-message drain: snapshot then commit in messageId.id order.
        var singleDrains: [(context: PendingMessageContext, messageId: MessageId, content: PendingMessageUploadedContentAndReuploadInfo)] = []
        for (id, context) in self.messageContexts {
            if id.peerId != key.peerId {
                continue
            }
            if context.threadId != key.threadId {
                continue
            }
            if case let .waitingForSendGate(groupId, content) = context.state, groupId == nil {
                singleDrains.append((context, id, content))
            }
        }
        singleDrains.sort(by: { $0.messageId.id < $1.messageId.id })
        for entry in singleDrains {
            self.commitSendingSingleMessage(messageContext: entry.context, messageId: entry.messageId, content: entry.content)
        }

        // (2) Grouped-album drain: collect distinct groupIds whose members match the key,
        // iterate ascending by min messageId.id, fire commitSendingMessageGroup.
        var groupKeys: [(groupId: Int64, minMessageId: Int32)] = []
        var seenGroupIds = Set<Int64>()
        for (id, context) in self.messageContexts {
            if id.peerId != key.peerId {
                continue
            }
            if context.threadId != key.threadId {
                continue
            }
            if case let .waitingForSendGate(groupId, _) = context.state, let groupId = groupId {
                if !seenGroupIds.contains(groupId) {
                    seenGroupIds.insert(groupId)
                    groupKeys.append((groupId, id.id))
                } else {
                    if let index = groupKeys.firstIndex(where: { $0.groupId == groupId }), id.id < groupKeys[index].minMessageId {
                        groupKeys[index].minMessageId = id.id
                    }
                }
            }
        }
        groupKeys.sort(by: { $0.minMessageId < $1.minMessageId })
        for (groupId, _) in groupKeys {
            if let data = self.dataForPendingMessageGroup(groupId) {
                self.commitSendingMessageGroup(groupId: groupId, messages: data)
            }
        }

        // (3) Forward drain: pop parked groups for this key in FIFO order; fire each.
        if let parkedGroups = self.forwardSendGateGroups.removeValue(forKey: key) {
            for messages in parkedGroups {
                for (context, _, _) in messages {
                    context.state = .sending(groupId: nil)
                }
                let sendMessage: Signal<PendingMessageResult, NoError> = self.sendGroupMessagesContent(network: self.network, postbox: self.postbox, stateManager: self.stateManager, accountPeerId: self.accountPeerId, group: messages.map { data in
                    let (_, message, forwardInfo) = data
                    return (message.id, PendingMessageUploadedContentAndReuploadInfo(content: .forward(forwardInfo), reuploadInfo: nil, cacheReferenceKey: nil))
                })
                |> map { _ -> PendingMessageResult in
                    return .progress(1.0)
                }
                messages[0].0.sendDisposable.set((sendMessage
                |> deliverOn(self.queue)).start())
            }
        }

        self.updateWaitingUploads(peerId: key.peerId)
        self.updatePendingMediaUploads()
    }
```

The forward dispatch block mirrors the existing forward-fire code at lines 719–731 of `PendingMessageManager.swift`. Keep them in sync if either changes.

- [ ] **Step 4: Wire the single-message gate at `beginSendingMessage`**

Replace `private func beginSendingMessage(messageContext:messageId:groupId:content:)` (line 738) with:

```swift
    private func beginSendingMessage(messageContext: PendingMessageContext, messageId: MessageId, groupId: Int64?, content: PendingMessageUploadedContentAndReuploadInfo) {
        if let groupId = groupId {
            messageContext.state = .waitingToBeSent(groupId: groupId, content: content)
        } else {
            let key = PeerAndThreadId(peerId: messageId.peerId, threadId: messageContext.threadId)
            if self.shouldGateSend(messageId: messageId, threadId: messageContext.threadId) && !self.isSendGateOpen(for: key) {
                messageContext.state = .waitingForSendGate(groupId: nil, content: content)
            } else {
                self.commitSendingSingleMessage(messageContext: messageContext, messageId: messageId, content: content)
            }
        }
        self.updatePendingMediaUploads()
    }
```

- [ ] **Step 5: Verify the build**

Run the build command. Expected: **success**.

- [ ] **Step 6: Commit**

```bash
git add submodules/TelegramCore/Sources/State/PendingMessageManager.swift
git commit -m "PendingMessageManager: wire typing-draft gate at single-message send + drain"
```

---

## Task 6: Wire the album-send gate at `commitSendingMessageGroup`

**Files:**
- Modify: `submodules/TelegramCore/Sources/State/PendingMessageManager.swift`

- [ ] **Step 1: Replace `commitSendingMessageGroup`**

Replace `private func commitSendingMessageGroup(groupId:messages:)` (line 794) with:

```swift
    private func commitSendingMessageGroup(groupId: Int64, messages: [(messageContext: PendingMessageContext, messageId: MessageId, content: PendingMessageUploadedContentAndReuploadInfo)]) {
        let firstMessageId = messages[0].messageId
        let firstThreadId = messages[0].messageContext.threadId
        let key = PeerAndThreadId(peerId: firstMessageId.peerId, threadId: firstThreadId)
        if self.shouldGateSend(messageId: firstMessageId, threadId: firstThreadId) && !self.isSendGateOpen(for: key) {
            for entry in messages {
                entry.messageContext.state = .waitingForSendGate(groupId: groupId, content: entry.content)
            }
            return
        }

        for (context, _, _) in messages {
            context.state = .sending(groupId: groupId)
        }
        let sendMessage: Signal<PendingMessageResult, NoError> = self.sendGroupMessagesContent(network: self.network, postbox: self.postbox, stateManager: self.stateManager, accountPeerId: self.accountPeerId, group: messages.map { ($0.1, $0.2) })
        |> map { next -> PendingMessageResult in
            return .progress(1.0)
        }
        messages[0].0.sendDisposable.set((sendMessage
        |> deliverOn(self.queue)).start())
    }
```

Album members share `(peerId, threadId)` by construction (the album fires once every member is post-upload in the same `groupId`).

- [ ] **Step 2: Verify the build**

Run the build command. Expected: **success**.

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCore/Sources/State/PendingMessageManager.swift
git commit -m "PendingMessageManager: wire typing-draft gate at album send"
```

---

## Task 7: Wire the forward-send gate inside `beginSendingMessages`

**Files:**
- Modify: `submodules/TelegramCore/Sources/State/PendingMessageManager.swift`

- [ ] **Step 1: Replace the forward-dispatch loop**

The existing forward-dispatch loop is at lines 714–733 inside `beginSendingMessages`. Replace exactly the body of `for messages in countedMessageGroups { ... }` with the gate-aware version:

```swift
                    for messages in countedMessageGroups {
                        if messages.isEmpty {
                            continue
                        }

                        let firstMessage = messages[0].1
                        let key = PeerAndThreadId(peerId: firstMessage.id.peerId, threadId: firstMessage.threadId)
                        if strongSelf.shouldGateSend(messageId: firstMessage.id, threadId: firstMessage.threadId) && !strongSelf.isSendGateOpen(for: key) {
                            for (context, _, forwardInfo) in messages {
                                context.state = .waitingForSendGate(groupId: nil, content: PendingMessageUploadedContentAndReuploadInfo(content: .forward(forwardInfo), reuploadInfo: nil, cacheReferenceKey: nil))
                            }
                            if strongSelf.forwardSendGateGroups[key] == nil {
                                strongSelf.forwardSendGateGroups[key] = []
                            }
                            strongSelf.forwardSendGateGroups[key]!.append(messages)
                            continue
                        }

                        for (context, _, _) in messages {
                            context.state = .sending(groupId: nil)
                        }

                        let sendMessage: Signal<PendingMessageResult, NoError> = strongSelf.sendGroupMessagesContent(network: strongSelf.network, postbox: strongSelf.postbox, stateManager: strongSelf.stateManager, accountPeerId: strongSelf.accountPeerId, group: messages.map { data in
                            let (_, message, forwardInfo) = data
                            return (message.id, PendingMessageUploadedContentAndReuploadInfo(content: .forward(forwardInfo), reuploadInfo: nil, cacheReferenceKey: nil))
                        })
                        |> map { next -> PendingMessageResult in
                            return .progress(1.0)
                        }
                        messages[0].0.sendDisposable.set((sendMessage
                        |> deliverOn(strongSelf.queue)).start())
                    }
```

The non-gated branch is the existing code, copied verbatim. The gated branch parks every context in `.waitingForSendGate` and appends the whole tuple-array onto `forwardSendGateGroups[key]`. The drain in `Task 5` reads from this dict.

- [ ] **Step 2: Verify the build**

Run the build command. Expected: **success**.

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCore/Sources/State/PendingMessageManager.swift
git commit -m "PendingMessageManager: wire typing-draft gate at forward send"
```

---

## Task 8: Clean up parked forwards in `updatePendingMessageIds` removal loop

**Files:**
- Modify: `submodules/TelegramCore/Sources/State/PendingMessageManager.swift`

When a message is removed from `pendingMessageIds` (e.g. user discarded it, or it was force-deleted), the existing loop disposes context-level state. Parked single/album state lives on the `PendingMessageContext` and gets reset when `state = .none`. Parked forwards live in `forwardSendGateGroups`, which the existing loop does not touch — patch that here.

- [ ] **Step 1: Add cleanup for `forwardSendGateGroups` in `updatePendingMessageIds`**

In `updatePendingMessageIds(_:)` (line 284), after the `for id in removedMessageIds { ... }` loop (closes around line 323), add a forward-cleanup pass before `if !addedMessageIds.isEmpty { ... }`:

```swift
            if !removedMessageIds.isEmpty && !self.forwardSendGateGroups.isEmpty {
                for (key, parkedGroups) in self.forwardSendGateGroups {
                    var rebuilt: [[(PendingMessageContext, Message, ForwardSourceInfoAttribute)]] = []
                    for group in parkedGroups {
                        let filtered = group.filter { entry in
                            return !removedMessageIds.contains(entry.1.id)
                        }
                        if !filtered.isEmpty {
                            rebuilt.append(filtered)
                        }
                    }
                    if rebuilt.isEmpty {
                        self.forwardSendGateGroups.removeValue(forKey: key)
                    } else {
                        self.forwardSendGateGroups[key] = rebuilt
                    }
                }
            }
```

- [ ] **Step 2: Verify the build**

Run the build command. Expected: **success**.

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCore/Sources/State/PendingMessageManager.swift
git commit -m "PendingMessageManager: cleanup parked forwards on pending-message removal"
```

---

## Task 9: Manual verification

**Files:** None (verification-only).

This codebase has no unit tests, so the final acceptance gate is a manual exercise on a debug simulator build. Skip if you don't have a working two-device test setup; in that case, re-confirm only the build is green.

- [ ] **Step 1: Confirm full build is still green**

Run the build command from the header. Expected: **success**.

- [ ] **Step 2: 1:1 chat, text-send delay**

Setup: log in to two real Telegram accounts on two devices/simulators (account A and account B). Open the A↔B 1:1 chat on both.

- On B, begin live-typing a draft (Telegram clients with the live-typing-drafts feature emit the typing-draft updates; if B doesn't expose live drafts, simulate by triggering whatever flow populates `transaction.combineTypingDrafts(...)` in your test environment).
- On A, immediately type and send a text message. Confirm: the message appears with a "sending" indicator and does **not** complete until B's draft clears or commits. Once B's draft is cleared, A's message sends within ~1 second.

- [ ] **Step 3: Album / grouped-media delay**

Repeat Step 2 with an album of two photos sent from A while B is live-typing. Expected: all album members upload (you can see progress finish), then all sit parked at "sending" until the gate opens.

- [ ] **Step 4: Forward delay**

Repeat with a forwarded message (forward a message from a third chat into A↔B while B is live-typing). Expected: forward parks until the gate opens.

- [ ] **Step 5: Negative — Saved Messages skip**

In Saved Messages (chat with self), send any message. Confirm: never delays, regardless of typing-draft state. There should be no typing draft for the self peer in the first place — this is just an existence check that the skip-rule does its job.

- [ ] **Step 6: Negative — secret chat skip**

In a secret chat, send a message. Confirm: never delays. Server-side, secret chats don't emit typing-draft updates — this verifies the explicit skip-check.

- [ ] **Step 7: Negative — scheduled message skip (defensive)**

The `Namespaces.Message.ScheduledCloud` skip in `shouldGateSend` is defensive — in practice, scheduled messages are stored in the scheduled queue and only enter `PendingMessageManager` at delivery time, by which point they've been re-created with cloud namespace. Verifying the defensive branch directly is awkward and not strictly required. If you have an instrumentation path that forces a scheduled-namespace message through `beginSendingMessages`, confirm it doesn't park.

- [ ] **Step 8: Multi-thread — gate is per-thread**

In a forum/topic group, on B begin live-typing in topic 1 only. On A, send a message to topic 2 of the same group. Expected: A's message to topic 2 is **not** delayed.

---

## Self-review notes (already applied inline)

- **Spec coverage:** every section of `2026-04-30-typing-draft-send-delay-design.md` maps to a task — Postbox view (Tasks 1–2), state machine extension (Task 3), subscription (Task 4), predicates + drain + single-send (Task 5), album (Task 6), forwards (Task 7), removal cleanup (Task 8), manual verification (Task 9).
- **Type names verified against actual code:** `PendingMessageState`, `PendingMessageContext`, `PendingMessageUploadedContentAndReuploadInfo`, `ForwardSourceInfoAttribute`, `PendingMessageResult`, `Signal`, `MetaDisposable`, `Queue`, `CombinedView`, `Namespaces.Message.ScheduledCloud`, `Namespaces.Peer.SecretChat`, `Message.newTopicThreadId`, `PeerAndThreadId`, `combineTypingDrafts`, `currentTypingDrafts`, `transaction.updatedTypingDrafts`, `update.value`. All names match the source.
- **`postponeSending` (paid-message) interaction:** untouched. Composes via state-machine ordering (paid postpone gates upload-start; this gate sits post-upload).
- **No unused-private-function warnings:** every helper is introduced together with its first caller (predicates + drain + first call site combined in Task 5).
