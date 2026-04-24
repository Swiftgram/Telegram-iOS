# Wave 39 — `makePeerInfoController` peer: Peer → EnginePeer migration

Date: 2026-04-24

## Context

Ring-2 cleanup of the `AccountContext` Peer-typed-API surface. Waves 34 (FoundPeer.peer), 35 (SendAsPeer.peer), 36 (ContactListPeer.peer), 37 (peerTokenTitle), and 38 (canSendMessagesToPeer) migrated adjacent Peer-typed APIs to `EnginePeer`. `makePeerInfoController` is the largest remaining Peer-typed-API surface on `AccountContext` and a natural follow-up.

Scope: only `makePeerInfoController` this wave. The sibling methods `makeChatQrCodeScreen` (4 consumer sites) and `makeChatRecentActionsController` (3 consumer sites) are deferred to a trivial follow-up wave.

## Signature change

`AccountContext` protocol declaration (`submodules/AccountContext/Sources/AccountContext.swift:1371`) and its `SharedAccountContextImpl` implementation (`submodules/TelegramUI/Sources/SharedAccountContext.swift:1937`):

```swift
// before
func makePeerInfoController(
    context: AccountContext,
    updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)?,
    peer: Peer,
    mode: PeerInfoControllerMode,
    avatarInitiallyExpanded: Bool,
    fromChat: Bool,
    requestsContext: PeerInvitationImportersContext?
) -> ViewController?

// after
func makePeerInfoController(
    context: AccountContext,
    updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)?,
    peer: EnginePeer,
    mode: PeerInfoControllerMode,
    avatarInitiallyExpanded: Bool,
    fromChat: Bool,
    requestsContext: PeerInvitationImportersContext?
) -> ViewController?
```

Implementation body adds `let peer = peer._asPeer()` shadow at body-top. `peerInfoControllerImpl` (private, same file) and all downstream Peer-typed helpers keep raw `Peer` — out of scope for this wave.

```swift
public func makePeerInfoController(... peer: EnginePeer ...) -> ViewController? {
    let peer = peer._asPeer()
    let controller = peerInfoControllerImpl(context: context, updatedPresentationData: updatedPresentationData, peer: peer, mode: mode, avatarInitiallyExpanded: avatarInitiallyExpanded, isOpenedFromChat: fromChat)
    controller?.navigationPresentation = .modalInLargeLayout
    return controller
}
```

## Consumer-side changes

**73 total consumer call sites** (75 raw occurrences minus 1 protocol declaration and 1 implementation). Classification (confirmed via full-repo grep):

- **58 Shape-A** — inline `peer: x._asPeer()` drops to `peer: x`. Mechanical edits.
- **3 Shape-A-variant** — `SettingsSearchableItems.swift` lines 1023, 1049, 1083. The upstream `guard let peer = peer?._asPeer() else` changes to `guard let peer = peer else`, making the local `peer` stay `EnginePeer`. The call-site line does not change.
- **12 Shape-C** — raw Peer local, add `EnginePeer(...)` wrap at call site.

### Shape-C site list

| File | Line | Current peer argument | New |
|---|---|---|---|
| `submodules/SettingsUI/Sources/Privacy and Security/BlockedPeersController.swift` | 270 | `peer: peer` | `peer: EnginePeer(peer)` |
| `submodules/PeerInfoUI/Sources/ChannelMembersController.swift` | 707 | `peer: participant.peer` | `peer: EnginePeer(participant.peer)` |
| `submodules/PeerInfoUI/Sources/ChannelBlacklistController.swift` | 381 | `peer: participant.peer` | `peer: EnginePeer(participant.peer)` |
| `submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsControllerNode.swift` | 1011 | `peer: peer` | `peer: EnginePeer(peer)` |
| `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift` | 4306 | `peer: peer` | `peer: EnginePeer(peer)` |
| `submodules/TelegramUI/Sources/Chat/ChatControllerNavigationButtonAction.swift` | 441 | `peer: peer` | `peer: EnginePeer(peer)` |
| `submodules/TelegramUI/Sources/Chat/ChatControllerNavigationButtonAction.swift` | 461 | `peer: peer` | `peer: EnginePeer(peer)` |
| `submodules/TelegramUI/Sources/Chat/ChatControllerNavigationButtonAction.swift` | 471 | `peer: peer` | `peer: EnginePeer(peer)` |
| `submodules/TelegramUI/Sources/Chat/ChatControllerNavigationButtonAction.swift` | 492 | `peer: channel` | `peer: EnginePeer(channel)` |
| `submodules/TelegramUI/Sources/Chat/ChatControllerOpenPeer.swift` | 218 | `peer: peer` | `peer: EnginePeer(peer)` |
| `submodules/TelegramUI/Sources/Chat/ChatControllerOpenPeer.swift` | 359 | `peer: peer` | `peer: EnginePeer(peer)` |
| `submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift` | 4362 | `peer: peer` | `peer: EnginePeer(peer)` |

Each Shape-C wrap is a future-wave drop candidate once the raw-Peer source (stored field, `participant.peer`, `renderedPeer.chatMainPeer`, etc.) migrates upstream.

### Shape-A-variant detail

`SettingsSearchableItems.swift` three sites share the same structure:

```swift
// before
let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
|> deliverOnMainQueue).start(next: { peer in        // peer: EnginePeer?
    guard let peer = peer?._asPeer() else {         // peer: Peer (shadowed)
        return
    }
    let controller = context.sharedContext.makePeerInfoController(
        context: context,
        updatedPresentationData: nil,
        peer: peer,
        mode: .myProfile,
        ...
    )
    ...
})

// after
let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
|> deliverOnMainQueue).start(next: { peer in        // peer: EnginePeer?
    guard let peer = peer else {                    // peer: EnginePeer (shadowed)
        return
    }
    let controller = context.sharedContext.makePeerInfoController(
        context: context,
        updatedPresentationData: nil,
        peer: peer,
        mode: .myProfile,
        ...
    )
    ...
})
```

## Files touched (≈50)

Inventoried from the grep output. Not exhaustive here; per-site enumeration lives in the implementation plan.

Signature files: `AccountContext/Sources/AccountContext.swift`, `TelegramUI/Sources/SharedAccountContext.swift`.

Shape-A consumer files (sample, not exhaustive): `SelectivePrivacySettingsPeersController.swift`, `InstantPageControllerNode.swift`, `CallListController.swift`, `ContactsController.swift`, `ContactContextMenus.swift`, `SecureIdAuthController.swift`, `ChannelAdminController.swift`, `ChannelMembersController.swift`, `ChannelBannedMemberController.swift`, `ChannelPermissionsController.swift`, `MessageStatsController.swift`, `GroupStatsController.swift`, `InviteRequestsController.swift`, `BrowserInstantPageContent.swift`, `WebAppController.swift`, `PeersNearbyController.swift`, `ChatSendStarsScreen.swift`, `ChatRecentActionsControllerNode.swift`, `MiniAppListScreen.swift`, `JoinSubjectScreen.swift`, `NewContactScreen.swift`, `StarsTransactionScreen.swift`, `StoryItemSetContainerViewSendMessage.swift`, `StoryItemSetContainerComponent.swift`, `GiftViewScreen.swift`, `GiftOptionsScreen.swift`, `StorageUsageScreen.swift`, `TextProcessingScreen.swift`, `PeerInfoScreen.swift`, `PeerInfoScreenOpenURL.swift`, `JoinAffiliateProgramScreen.swift`, `ChatControllerScrollToPointInHistory.swift`, `OpenUrl.swift`, `OpenResolvedUrl.swift`, `TextLinkHandling.swift`, `ChatController.swift`, `OpenAddContact.swift`, `ChatManagingBotTitlePanelNode.swift`, `NavigateToChatController.swift`, `SharedAccountContext.swift` (3 self-call sites), `OverlayAudioPlayerControllerNode.swift`, `PollResultsController.swift`, `ChatControllerOpenWebApp.swift`, `ChatControllerNavigationButtonAction.swift`, `ChatListController.swift`, `ChatListSearchListPaneNode.swift`.

Shape-A-variant file: `SettingsSearchableItems.swift`.

Shape-C-only files (other than those with mixed shapes above): `BlockedPeersController.swift`, `ChannelBlacklistController.swift`, `ChatControllerOpenPeer.swift`, `ChatControllerLoadDisplayNode.swift`.

## Build/verification plan

1. Apply all edits atomically. Mechanical Edit-tool string replaces for the 58 Shape-A drops; focused Edits for the 3 Shape-A-variants (guard line) and 12 Shape-C wraps.
2. Full project build: `source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError`.
3. Fix any iteration-surfaced errors. Budget 2–4 iterations.
4. Clean build → atomic commit with wave-39 message.
5. Update `project_postbox_refactor_next_wave.md` memory, `docs/superpowers/postbox-refactor-log.md`, and `CLAUDE.md` wave tally.
6. No test runs (project has no unit tests).

## Risks / watch-out

- **Destructure/binding cascades.** Locals named `peer` declared as `Peer` somewhere in a call chain and fed to `makePeerInfoController`. The body-shadow pattern contains divergence at the public API boundary, but transient Swift inference errors may surface at intermediate points.
- **`chatMainPeer` / `renderedPeer.peer` property types.** Shape-C sites at `ChatControllerNavigationButtonAction.swift:441/461/471/492` and `ChatControllerLoadDisplayNode.swift:4362` assume these properties return raw `Peer`. If they already return `EnginePeer` in the current repo (unlikely but possible after earlier waves), the wrap should be `peer: peer` with no wrap. Verify in plan phase.
- **Outflow sites in Shape-C files.** Some Shape-C files may have additional `peer: Peer` flows elsewhere that are unrelated to this wave. Do not chase — only touch the listed sites.

## Abandonment criteria

- Iteration count exceeds 5.
- A cascade requires editing `peerInfoControllerImpl` (violates body-shadow boundary).
- Any non-consumer file (e.g., anything in `TelegramCore`, `Postbox`, `TelegramApi`) surfaces an error.

## Net effect

- Public API: `AccountContext.makePeerInfoController` takes `EnginePeer` instead of raw `Peer`.
- Bridges: -58 inline `_asPeer()` + -3 upstream-guard `_asPeer()` + 12 new `EnginePeer(...)` wraps = **net -49 bridges**.
- Ratchet: 12 Shape-C wraps become future-wave drop candidates (e.g., `RenderedPeer → EngineRenderedPeer` migration, participant-object migrations).

## Out of scope

- `makeChatQrCodeScreen` (4 sites), `makeChatRecentActionsController` (3 sites) — deferred to a trivial follow-up wave.
- `peerInfoControllerImpl` and downstream Peer-typed helpers.
- Shape-C source migrations (participant objects, `renderedPeer.chatMainPeer`, etc.).
