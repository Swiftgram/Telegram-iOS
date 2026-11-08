# Custom Swiftgram tweaks

A locally-implemented tweak pack for this Swiftgram fork. Everything lives on the device:
the tweaks never change server-side behaviour beyond the requests they deliberately suppress,
and none of the fake state (balances, gifts, tags) is ever sent to Telegram.

## Where the settings live

Settings → (Swiftgram section) → **Custom Swiftgram Tweaks**, implemented by
`Swiftgram/SGSettingsUI/Sources/SGCustomTweaksController.swift`. The entry row is added in
`submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift`
and opened from `PeerInfoScreenSettingsActions.openSettings(.customTweaks)`.

All values are persisted through `SGSimpleSettings` (`Swiftgram/SGSimpleSettings/Sources/SimpleSettings.swift`),
i.e. `UserDefaults`, under the keys `ghostMode`, `keepSecretMedia`, `phantomGifts`,
`disableLiquidGlass`, `customStarsBalance`, `customGramBalance`, `userTags`.

## Feature → code map

| Tweak | Implementation |
| --- | --- |
| Ghost mode — no online status | `submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift`: `updatePresence` always sends `account.updateStatus(offline: true)`; the settings toggle posts `.sgGhostModeChanged` so presence is re-applied at once. |
| Ghost mode — no read receipts | `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift`: `synchronizePeerReadState` confirms the queued operation locally and returns without calling `messages.readHistory` / `channels.readHistory` / `messages.readEncryptedHistory`. `MarkAllChatsAsRead.swift` skips the bulk push too. |
| Custom Stars / GRAM balance | `customStarsBalanceOverride` / `customGramBalanceOverride` are rendered in `PeerInfoSettingsItems.swift` (settings rows), `PeerInfoHeaderNode.swift` (profile wallet strip), `WalletScreen.swift` (wallet nav bar) and `StarsBalanceComponent.swift` / `StarsTransactionsScreen.swift` (Stars/TON screen). |
| Infinite view of one-time media | `SyncCore_AutoremoveTimeoutMessageAttribute.swift` stops publishing `automaticTimestampBasedAttribute` while the tweak is on; `MarkMessageContentAsConsumedInteractively.swift` neither starts the countdown nor replaces opened media with `TelegramMediaExpiredContent`. |
| Phantom GRAM gift | `GiftsListView.swift` (`SGPhantomGiftView`) draws a local "GRAM" tile above the owner's own gifts; no `StarGift` model is created and nothing is synced. |
| Local user tags | Stored in `SGSimpleSettings.userTags`; edited from the tweaks screen (contact picker + inline field); rendered by `ChatListItem.swift` (title badge pill) and `ChatTitleView.swift` (dialog navigation title). |
| Disable liquid glass | `GlassBackgroundComponent.swift` replaces `UIGlassEffect` with a flat translucent fill and takes the flag into its cached `Params`; `Display/Source/NavigationBackgroundView.swift` skips navigation/background blur and uses an opaque colour. Tab bar and navigation bar both go through `GlassBackgroundView`, so they are covered. |

## Notes and limits

- Face-ID-secured secrets, server-side expiry and remote deletion are outside the client's
  control: the local copy of a one-time media is kept, but a server that has already deleted
  it cannot be undone. Media that was already replaced with `TelegramMediaExpiredContent`
  before the tweak was enabled cannot be recovered.
- Tag changes are read during chat-list item layout; a row picks the new tag up on its next
  layout pass (theme change, chat update or reopening the list).
- The custom balances are pure display strings; they do not affect transactions, purchases or
  any server-side balance.
- A macOS/Xcode environment is required to build (`build-system/Make/Make.py`); the changes here
  were reviewed statically because the development host is Windows.
