# Wave 35 — `SendAsPeer.peer` `Peer` → `EnginePeer`

Date: 2026-04-24
Status: approved design, awaiting plan
Wave shape: Peer-typed-API single atomic commit (wave 34 pattern replayed on a smaller target)

## Goal

Eliminate the Postbox-protocol `Peer` leak in the public `SendAsPeer` struct by migrating its `peer` field from `Peer` to `EnginePeer`. Apply wave 34's lessons — comprehensive pre-flight grep including `.peer as?`/`is` casts, outflow-arg patterns, and loop-body `.peer` accesses — to keep post-commit build iterations low.

## Non-goals

- `ContactListPeer.peer(peer: Peer, ...)` case-payload migration — broader blast radius, deferred.
- `canSendMessagesToPeer(_:)` parameter migration — broader blast radius, deferred.
- `makePeerInfoController` / `makeChatQrCodeScreen` / `makeChatRecentActionsController` protocol-method migrations — broader blast radius, deferred.
- `CachedSendAsPeers` cache entry — already `PeerId`-based, entirely inside TelegramCore; no change needed.
- No new engine wrappers, typealiases, or facades introduced in this wave.

## Type change

```swift
// Before
public struct SendAsPeer: Equatable {
    public let peer: Peer                    // Postbox protocol
    public let subscribers: Int32?
    public let isPremiumRequired: Bool
    public init(peer: Peer, subscribers: Int32?, isPremiumRequired: Bool) { … }
    public static func ==(lhs: SendAsPeer, rhs: SendAsPeer) -> Bool {
        return lhs.peer.isEqual(rhs.peer) && lhs.subscribers == rhs.subscribers && lhs.isPremiumRequired == rhs.isPremiumRequired
    }
}

// After
public struct SendAsPeer: Equatable {
    public let peer: EnginePeer              // TelegramCore value type
    public let subscribers: Int32?
    public let isPremiumRequired: Bool
    public init(peer: EnginePeer, subscribers: Int32?, isPremiumRequired: Bool) { … }
    // Equatable synthesized — EnginePeer is Equatable.
}
```

## In-scope files

### Category α — TelegramCore (definition + internal construction)

**`submodules/TelegramCore/Sources/TelegramEngine/Messages/SendAsPeers.swift`**
- Lines 7–21: struct definition. Change `peer: Peer` → `peer: EnginePeer`. Remove manual `==`; rely on synthesized Equatable.
- Line 64 (`_internal_cachedPeerSendAsAvailablePeers`): `SendAsPeer(peer: peer, …)` — wrap raw Postbox `Peer` with `EnginePeer(peer)`.
- Line 170 (`_internal_peerSendAsAvailablePeers`): same wrap.
- Line 236 (`_internal_cachedLiveStorySendAsAvailablePeers`): same wrap.
- Line 330 (`_internal_liveStorySendAsAvailablePeers`): same wrap.
- Lines 87, 90, 259, 262: `peer.peer.id` accesses inside the caching loop — `EnginePeer.id` returns `EnginePeer.Id` which is a typealias for `PeerId`; code keeps compiling.

No other TelegramCore files reference `SendAsPeer`.

### Category β — Pure token/init/access (no body edits expected)

**`submodules/ChatPresentationInterfaceState/Sources/ChatPresentationInterfaceState.swift`**
- Line 553: `public let sendAsPeers: [SendAsPeer]?` — field typed at collection level, no `.peer` access in this file.
- Lines 751–752 / 848 / 1068 / 1408: init parameter, assignment, equality comparison at `[SendAsPeer]?` level, and `updatedSendAsPeers(_:)` method. None reference the inner `.peer` field.
- Expected edits: zero. This file should remain untouched if the field-type migration is clean.

**`submodules/ChatPresentationInterfaceState/Sources/ChatPanelInterfaceInteraction.swift`**
- Out of scope: its `openSendAsPeer: (ASDisplayNode, ContextGesture?) -> Void` callback does NOT take a `SendAsPeer`; name-collision only.

### Category γ — Cast-downstream

**`submodules/TelegramUI/Components/Chat/ChatSendAsContextMenu/Sources/ChatSendAsPeerListContextItem.swift`**
- Lines 20, 26: `peers: [SendAsPeer]` field and constructor — no edit needed.
- Lines 68–82: iteration body.
    - Line 70: `peer.peer.id.namespace == Namespaces.Peer.CloudUser` — unchanged (EnginePeer.Id retains `.namespace`).
    - Line 73: **`if let peer = peer.peer as? TelegramChannel`** → rewrite as `if case let .channel(channelData) = peer.peer`, matching on the `EnginePeer` enum case. Downstream `channelData.info` access behaves the same; `case .broadcast = channelData.info` continues to compile because `EnginePeer.channel` wraps the same `TelegramChannel.Info` enum.
- Lines 89 / 110 / 116 / 121: `EnginePeer(peer.peer)` — drop the wrap, use `peer.peer` directly.

### Category δ — Outflow (construction and field access)

**`submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift`**
- Line 772: `SendAsPeer(peer: peer._asPeer(), …)` — drop `._asPeer()`; construction now takes `EnginePeer` directly. `peer` at this site is already an `EnginePeer` upstream.
- Lines 805, 823: `SendAsPeer(peer: channel, …)` where `channel` is a raw `TelegramChannel` — wrap with `EnginePeer(channel)`.
- Lines 792 / 826 / 835 / 844: `allPeers` array ops and `.peer.id` filter/find — unchanged.

**`submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelComponent.swift`**
- Line 847: `SendAsPeer(peer: sendAsConfiguration.currentPeer._asPeer(), …)` — drop `._asPeer()`. `sendAsConfiguration.currentPeer` is `EnginePeer` upstream.
- Line 851: `updatedSendAsPeers([…])` — unchanged.

**`submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift`**
- Line 1625: `EnginePeer(peer)` where `peer` is now `EnginePeer` → collapses to `peer`.
- Lines 1616 / 1620 / 1622 / 2948 / 5370: `.peer.id` comparisons, `sendAsPeers.first(where:)` — unchanged.

**`submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerViewSendMessage.swift`**
- Line 249: `SendAsPeer(peer: accountPeer._asPeer(), …)` — drop `._asPeer()`.
- Line 4080: `(sendAsPeer?.peer).flatMap(EnginePeer.init)` → simplifies to `sendAsPeer?.peer` (already `EnginePeer?`).
- Line 4081: `.map({ EnginePeer($0.peer) })` → `.map({ $0.peer })`.
- Line 254 / 688 / 701 / 702 / 705 / 4050 / 4068 / 4069 / 4088 / 4089 / 4327 / 4333 / 4340 / 4356 / 4372: `.peer.id` accesses, variable bindings, optional access — unchanged.
- Line 4340: `call.sendStars(fromId: sendAsPeer?.peer.id, …)` — `EnginePeer.Id == PeerId`, unchanged.

**`submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerComponent.swift`**
- Lines 3056–3072: `sendMessageContext.currentSendAsPeer` pass-through to context-menu item. Verify call-site type expectations during implementation; likely no edit needed since `ChatSendAsPeerListContextItem` keeps taking `[SendAsPeer]`.

## Out-of-scope — name collisions (do not touch)

- `submodules/TelegramUI/Components/ShareWithPeersScreen/Sources/LiveStreamSettingsScreen.swift:271-272` — `screenState.sendAsPeers` is `[EnginePeer]` (see `ShareWithPeersScreen.swift:1114`). Different type, same name.
- `submodules/TelegramUI/Components/Chat/ChatSendStarsScreen/Sources/ChatSendStarsScreen.swift:1515,2749,2958` — `availableSendAsPeers: [EnginePeer]` enum-case payload. Different type, same name.
- `submodules/TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift:7070`, `ShareWithPeersScreen.swift:39,57,74,817,1301,2352,3284,3453` — `initialSendAsPeerId: EnginePeer.Id?` / method names containing "SendAsPeer". PeerId parameter, not the struct.
- Callback declarations in `ChatPanelInterfaceInteraction.swift`, `AttachmentPanel.swift`, `PeerSelectionControllerNode.swift`, `ChatRecentActionsController.swift`, `PeerInfoSelectionPanelNode.swift` named `updateShowSendAsPeers` / `openSendAsPeer` — these take `(Bool)`/`(ASDisplayNode, ContextGesture?)`, not `SendAsPeer` values.

## Execution plan outline (for writing-plans)

Single atomic commit ordering:

1. Edit `SendAsPeers.swift` — change field type, init parameter, drop manual `==`, wrap raw `Peer` at the 4 construction sites with `EnginePeer(peer)`.
2. Edit `ChatSendAsPeerListContextItem.swift` — rewrite line 73 cast to EnginePeer case match; drop `EnginePeer(peer.peer)` wraps at 89/110/116/121.
3. Edit `ChatControllerLoadDisplayNode.swift` — drop `._asPeer()` at 772; wrap `channel` with `EnginePeer(channel)` at 805/823.
4. Edit `ChatTextInputPanelComponent.swift` — drop `._asPeer()` at 847.
5. Edit `ChatTextInputPanelNode.swift` — collapse `EnginePeer(peer)` at 1625 to `peer`.
6. Edit `StoryItemSetContainerViewSendMessage.swift` — drop `._asPeer()` at 249; simplify flatMap at 4080; simplify map at 4081.
7. Verify `ChatPresentationInterfaceState.swift` and `StoryItemSetContainerComponent.swift` need no body edits.
8. Build: `source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError`.
9. Fix any files the inventory undercounted (expect scalar `.peer` accesses in closure bodies). Commit once build is green.

## Risk register

| Risk | Mitigation |
|------|------------|
| Inventory undercount (wave 34 lost ~30%) | Pre-flight grep already includes `.peer as?`/`is`/outflow; use `--continueOnError` on first build to surface all sites in one pass. |
| Cast at `ChatSendAsPeerListContextItem:73` doesn't round-trip | `EnginePeer.channel(TelegramChannel)` wraps the exact same concrete type; the `if case let .channel(ch)` rewrite preserves all `ch.info`/`ch.flags`/etc. semantics. |
| `SendAsPeer` Equatable synthesis regression | `EnginePeer` and `Int32?` and `Bool` are all Equatable; synthesized `==` produces the same truth table modulo replacing `Peer.isEqual` with `EnginePeer ==` (which for `.channel(a)` vs `.channel(b)` compares the underlying `TelegramChannel` via its own Equatable). No behavior change expected. |
| `StoryItemSetContainerComponent.swift:3056-3072` outflow missed | Plan step 7 verifies this during implementation; if a wrap/unwrap is needed at the context-menu boundary, add it inline. |

## Validation

- Full Bazel build (`--configuration=debug_sim_arm64 --continueOnError`).
- No TelegramCore/Postbox/TelegramApi errors (scope boundary check — halt if they surface).
- Grep post-commit: `rg "SendAsPeer\(peer: .*\._asPeer" submodules/` returns empty.
- Grep post-commit: `rg "EnginePeer\(.*\.peer\b" submodules/TelegramUI/Components/Chat/ChatSendAsContextMenu` returns empty.

## Lessons to carry forward

- Wave 34's grep pattern (`<Type>`-literal token only) undercounted ~30%. This wave's Explore inventory explicitly included `.peer as?`/`is`/outflow-helper/`EnginePeer(.peer)` / `._asPeer()` patterns. Record the post-commit file count vs. pre-commit inventory to calibrate future Peer-typed-API waves.
- Name collisions (different types, same identifier) are a recurring scoping hazard — confirmed in this wave for `sendAsPeers: [EnginePeer]` and `availableSendAsPeers: [EnginePeer]`. Future Peer-typed-API waves should include a name-collision disambiguation pass during inventory.
