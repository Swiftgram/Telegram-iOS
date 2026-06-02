# Gate Rich Text messages behind Premium — design

**Date:** 2026-06-02
**Status:** Approved (design); ready for implementation plan.

## Problem

Rich Text messages (`RichTextMessageAttribute` carrying an `InstantPage` — headings, lists,
tables, formulas) are auto-produced from typed markdown on send/edit (see
[`docs/instantpage-richtext.md`](../../instantpage-richtext.md), "Markdown send: entity vs. rich
detection"). We want sending/creating a Rich Text message to be a **Telegram Premium** feature:
non-premium users are blocked at the point of sending or editing-into-rich and offered the Premium
upsell, mirroring how the existing **todo/checklist** message type is gated.

## Scope

**In scope — gating message *creation* (the markdown → rich path):**

- Compose + send.
- Editing a message whose new markdown would produce rich.
- The long-press "Send options" sheet (its preview, and — transitively — its send).

**Out of scope (explicit non-goals):**

- **Rendering / receiving** rich messages. Non-premium users must still *see* formatted messages
  others send. Only the create/send side is gated.
- No new `PremiumSource` enum case — the paywall reuses the generic `.settings` source.
- No server promo-content / `premiumPromoConfiguration` changes.

## Behavior

When a non-premium user composes or edits markdown that the classifier
(`richMarkdownAttributeIfNeeded`) would turn into a Rich Text message, the action is **blocked**
and a `.premiumPaywall` toast is shown. Tapping the toast's info action opens the Premium intro
screen. The user's typed text is **preserved** in the input/edit field (the send/edit simply does
not proceed).

This matches the todo gate precedent at `ChatController.swift:5668` and
`ChatControllerOpenTodoContextMenu.swift:71`.

### Gate conditions

The gate fires **iff all** of the following hold:

1. The text would produce a rich message (`richMarkdownAttributeIfNeeded(...) != nil`).
2. The account is **not** premium.
3. The chat is **not** the user's own Saved Messages (`peerId != context.account.peerId`).
   — "notes to self" carve-out, matching the premium-emoji gate
   (`ChatControllerNode.swift:4742`).
4. Premium is **not** disabled in this region/build
   (`!PremiumConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 }).isPremiumDisabled`).
   — so rich text isn't permanently blocked where Premium can't be purchased. (Note: the todo gate
   does **not** do this; we deliberately add it here.)

If premium is disabled, rich text behaves exactly as today (free for everyone).

## Design

### 1. Gate-decision helper (shared free function)

New file `submodules/TelegramUI/Sources/Chat/ChatRichTextPremiumGate.swift`:

```swift
func isRichTextMessageGated(context: AccountContext, peerId: EnginePeer.Id?, isPremium: Bool) -> Bool {
    if isPremium {
        return false
    }
    if let peerId, peerId == context.account.peerId {
        return false // Saved Messages carve-out
    }
    let premiumConfiguration = PremiumConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    if premiumConfiguration.isPremiumDisabled {
        return false // premium-disabled regions
    }
    return true
}
```

Used by all three sites (Sites 1 & 2 to decide whether to block; Site 3 to decide whether to build
the preview). It does **not** itself call the classifier — each site already has (or computes) the
`richMarkdownAttributeIfNeeded` result and combines it with this decision.

### 2. Paywall-presentation helper (method on `ChatControllerImpl`)

The toast is presented from the controller, which already owns `present`/`push`/`presentationData`.
A new method on `ChatControllerImpl` (the same type the todo gate at `ChatController.swift:5668`
lives on):

```swift
func presentRichTextPremiumPaywall() {
    let controller = UndoOverlayController(
        presentationData: self.presentationData,
        content: .premiumPaywall(title: nil, text: self.presentationData.strings.Chat_RichText_PremiumRequired, customUndoText: nil, timeout: nil, linkAction: nil),
        action: { [weak self] action in
            guard let self else {
                return false
            }
            if case .info = action {
                let controller = self.context.sharedContext.makePremiumIntroController(context: self.context, source: .settings, forceDark: false, dismissed: nil)
                self.push(controller)
            }
            return false
        }
    )
    self.present(controller, in: .current)
}
```

- New localized string `Chat_RichText_PremiumRequired`, e.g. *"Subscribe to Telegram Premium to
  send formatted messages with headings, lists and tables."* Added to the strings infra alongside
  the existing `Chat_Todo_PremiumRequired`.
- `source: .settings` (generic) per the design decision — no dedicated enum case.

### 3. Wiring at the three entry points

**Site 1 — Send.** `ChatControllerNode.sendCurrentMessage` (~`ChatControllerNode.swift:4864`),
the rich branch. After `richMarkdownAttributeIfNeeded` returns non-nil:

```swift
if !isSpecialChatContents, let attribute = richMarkdownAttributeIfNeeded(context: self.context, attributedText: effectiveInputText) {
    if isRichTextMessageGated(context: self.context, peerId: self.chatPresentationInterfaceState.chatLocation.peerId, isPremium: self.chatPresentationInterfaceState.isPremium) {
        self.controller?.presentRichTextPremiumPaywall()
        return
    }
    // ... existing rich-send code unchanged ...
}
```

`ChatControllerNode` reaches the controller via `self.controller` (a `ChatControllerImpl`). The
early `return` aborts the whole send. **This site also covers the long-press send-options sheet's
*send***: `ChatMessageDisplaySendMessageOptions`'s `.generic`/`.silently` modes call
`controllerInteraction?.sendCurrentMessage` → `ChatController.swift:2228` → `chatDisplayNode.sendCurrentMessage`,
and `.whenOnline` calls `chatDisplayNode.sendCurrentMessage` directly — all land in Site 1.

**Site 2 — Edit save.** `ChatControllerLoadDisplayNode` editMessage (~`:2224`). After computing
`richTextAttribute`:

```swift
if let richTextAttribute, isRichTextMessageGated(context: strongSelf.context, peerId: strongSelf.chatLocation.peerId, isPremium: strongSelf.presentationInterfaceState.isPremium) {
    strongSelf.presentRichTextPremiumPaywall()
    return
}
```

`ChatControllerLoadDisplayNode` is an extension of `ChatControllerImpl`, so `strongSelf` calls the
helper directly. A **rich→plain** edit produces `richTextAttribute == nil`, so it is not gated and
still saves normally.

**Site 3 — Send-options preview.** `ChatMessageDisplaySendMessageOptions` (~`:219`). Build the
rich preview **only when not gated**:

```swift
} else if mediaPreview == nil,
          let attributedText = textInputView.attributedText,
          let attribute = richMarkdownAttributeIfNeeded(context: selfController.context, attributedText: attributedText),
          !isRichTextMessageGated(context: selfController.context, peerId: selfController.presentationInterfaceState.chatLocation.peerId, isPremium: selfController.presentationInterfaceState.isPremium) {
    richTextPreview = ChatSendMessageRichTextPreview(context: selfController.context, instantPage: attribute.instantPage)
}
```

A gated user sees the **plain** preview in the options sheet (consistent with the block), and the
actual send is stopped by Site 1's gate. No separate toast is presented here.

## Edge cases

- **Editing an already-rich message as non-premium.** Only reachable if the user was formerly
  premium (or in Saved Messages, which is exempt). Site 2 blocks re-saving it as rich; a
  rich→plain edit still works.
- **Premium disabled.** Gate 4 short-circuits everywhere → rich text is free, as today.
- **`isSpecialChatContents` (business links / quick replies).** Already bypassed before the gate at
  Sites 1 & 3; unchanged.

## Files touched

| File | Change |
|---|---|
| `submodules/TelegramUI/Sources/Chat/ChatRichTextPremiumGate.swift` (new) | `isRichTextMessageGated(...)` free function. |
| `submodules/TelegramUI/Sources/ChatController.swift` | `presentRichTextPremiumPaywall()` method on `ChatControllerImpl`. |
| `submodules/TelegramUI/Sources/ChatControllerNode.swift` (~4864) | Site 1 gate. |
| `submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift` (~2224) | Site 2 gate. |
| `submodules/TelegramUI/Sources/Chat/ChatMessageDisplaySendMessageOptions.swift` (~219) | Site 3 preview suppression. |
| Localizable strings | New `Chat_RichText_PremiumRequired`. |

## Verification

No unit tests in this project. Verify via the full Bazel build, then manual two-account smoke test:

1. Non-premium account, regular chat: type `# Heading\n- a\n- b`, send → paywall toast; tapping it
   opens Premium intro; text remains in input; nothing sent.
2. Same, edit an existing plain message into a table → paywall on save; original message unchanged.
3. Same, long-press send button on rich markdown → options sheet shows **plain** preview; sending
   from it → paywall.
4. Non-premium account, **Saved Messages**: same rich markdown sends normally (carve-out).
5. Premium account: rich markdown sends/edits normally (no toast).
6. Non-premium account, plain markdown (e.g. `**bold**`, `---`): sends normally (not a rich
   trigger).
