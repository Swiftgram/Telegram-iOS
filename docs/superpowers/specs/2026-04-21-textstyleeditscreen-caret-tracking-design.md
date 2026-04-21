# TextStyleEditScreen caret-tracking auto-scroll — design

## Background

`submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextStyleEditScreen.swift` hosts a sheet built on `ResizableSheetComponent` with two `ListMultilineTextFieldItemComponent` fields (a title and a multi-line prompt). The sheet's `inputHeight` plumbing and scroll-content sizing have already been wired up:

- `TextStyleEditSheetComponent.View.update` passes `environmentValue.inputHeight` into `ResizableSheetComponentEnvironment(inputHeight:)` instead of a hardcoded `0.0`.
- `ResizableSheetComponent` now subtracts `inputHeight` from `topInset` and adds it to `scrollContentHeight` so the scroll view has enough room to pan past the keyboard.

What remains: when the user types, the caret in the focused field must be scrolled into the visible area above the soft keyboard. Without this, typing near the bottom of the prompt field hides the caret under the keyboard.

## Goal

Whenever a text edit occurs in either `ListMultilineTextFieldItemComponent` inside `TextStyleEditContentComponent`, adjust the enclosing scroll view's `bounds.origin.y` so that the caret rect sits comfortably above the keyboard and bottom action button.

## Scope

All changes live in `submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextStyleEditScreen.swift`. No changes to `ResizableSheetComponent`, `ListMultilineTextFieldItemComponent`, or `TextFieldComponent` — their existing public surfaces are sufficient:

- `ListMultilineTextFieldItemComponent.Tag` (constructor param `tag:`, plus `matches(tag:)` on the view).
- `ListMultilineTextFieldItemComponent.View.textFieldView: TextFieldComponent.View?`.
- `TextFieldComponent.View.inputTextView: UITextView`.
- `TextFieldComponent.AnimationHint` attached as `userData` on the transition whenever `TextFieldComponent` fires a state update on text change (`TextFieldComponent.swift:471/491/504/542/620/1077`).

## Non-goals

- No scroll on focus change alone (user requirement — text-change only).
- No scroll on selection change without an edit.
- No scroll-triggering on keyboard show/hide independently of text changes.
- No changes to shared infrastructure (`ResizableSheetComponent` stays as-is after the user's sizing work).

## Design

### 1. Field tagging

`TextStyleEditContentComponent.View` stores two tags created once at init:

```swift
private let titleFieldTag = ListMultilineTextFieldItemComponent.Tag()
private let textFieldTag = ListMultilineTextFieldItemComponent.Tag()
```

The two `ListMultilineTextFieldItemComponent(...)` constructions in `update(...)` pass the corresponding tag via the existing `tag:` parameter (currently `tag: nil` at both sites). This lets us identify which of our fields a hint's originating `TextFieldComponent.View` belongs to.

### 2. Recenter trigger

At the end of `TextStyleEditContentComponent.View.update(...)`, after all sub-component layout is complete and all frames are set, evaluate the incoming transition's user data:

```swift
if let hint = transition.userData(TextFieldComponent.AnimationHint.self),
   case .textChanged = hint.kind,
   let hintView = hint.view {
    self.recenterCaret(hintView: hintView, availableSize: availableSize, environment: environment, transition: transition)
}
```

`hint.kind` is either `.textChanged` or `.textFocusChanged(isFocused:)`; we match only `.textChanged`.

### 3. Scroll-to-caret logic

`recenterCaret(hintView:availableSize:environment:transition:)` is a private method on `TextStyleEditContentComponent.View` that performs these steps:

1. **Locate field view.** Walk ancestors of `hintView` up to the first `ListMultilineTextFieldItemComponent.View`. Confirm it matches one of `self.titleFieldTag` / `self.textFieldTag` via `fieldView.matches(tag:)`. If neither matches, bail silently.

2. **Compute caret rect in text-view space.** From the field view, grab `textFieldView?.inputTextView`. Retrieve the caret rect:
   ```swift
   let endPosition = inputTextView.selectedTextRange?.end ?? inputTextView.endOfDocument
   let caretRect = inputTextView.caretRect(for: endPosition)
   ```
   If `caretRect.isNull` or `caretRect.isInfinite`, bail (text view hasn't laid out yet).

3. **Locate enclosing scroll view.** Walk `self.superview` chain until the first `UIScrollView` is found (this is `ResizableSheetComponent`'s private scroll view). If no scroll view is found, bail.

4. **Convert caret rect to scroll-view coordinates.**
   ```swift
   let caretInScroll = inputTextView.convert(caretRect, to: scrollView)
   ```

5. **Compute visible region.** Within the scroll view's current bounds, determine the vertical range in which the caret should sit:
   ```swift
   let bottomActionAreaHeight: CGFloat = 52.0 + 8.0  // matches ResizableSheetComponent bottom layout
   let caretTopInset: CGFloat = 24.0                 // small cushion below keyboard/button
   let caretBottomInset: CGFloat = 24.0              // small cushion above keyboard/button
   let visibleTop = scrollView.bounds.minY + caretTopInset
   let visibleBottom = scrollView.bounds.maxY - environment.inputHeight - bottomActionAreaHeight - caretBottomInset
   ```

6. **Adjust `bounds.origin.y`.** Using the direct-assign + additive-animate pattern proven in `ComposePollScreen.swift:2873-2895`:
   ```swift
   let previousBounds = scrollView.bounds
   var newBounds = previousBounds
   if caretInScroll.maxY > visibleBottom {
       newBounds.origin.y += (caretInScroll.maxY - visibleBottom)
   } else if caretInScroll.minY < visibleTop {
       newBounds.origin.y -= (visibleTop - caretInScroll.minY)
   }
   let maxOriginY = max(0.0, scrollView.contentSize.height - scrollView.bounds.height)
   newBounds.origin.y = min(max(0.0, newBounds.origin.y), maxOriginY)
   if newBounds != previousBounds {
       scrollView.bounds = newBounds
       if !transition.animation.isImmediate {
           let offsetY = previousBounds.origin.y - newBounds.origin.y
           transition.animateBoundsOrigin(view: scrollView, from: CGPoint(x: 0.0, y: offsetY), to: CGPoint(), additive: true)
       }
   }
   ```
   This keeps the scroll animation in sync with the text-change spring carried by the hint's transition, and matches existing precedent in the codebase.

## Edge cases

- **Caret rect unavailable.** `caretRect(for:)` returns `CGRect.null` or `CGRect.infinite` when the text view hasn't laid out. Skip — the next hint will cover it.
- **No enclosing scroll view.** Defensive bail; should never happen in normal operation but keeps the code robust against host refactors.
- **Hint from unrelated field.** Tag mismatch → bail. Keeps the scroll view untouched if a future nested text input is added.
- **Over/under-scroll.** `newBounds.origin.y` clamped to `[0, contentSize.height − bounds.height]`.
- **Caret already visible.** No-op — `newBounds != scrollView.bounds` guards against churn.

## File-level changes summary

Only `TextStyleEditScreen.swift` is edited:

- Add two stored `ListMultilineTextFieldItemComponent.Tag` properties on `TextStyleEditContentComponent.View`.
- Pass those tags into the existing two `ListMultilineTextFieldItemComponent(...)` calls in `update(...)`.
- Add a private `recenterCaret(...)` method on `TextStyleEditContentComponent.View`.
- Add a small block at the end of `update(...)` that reads `transition.userData(TextFieldComponent.AnimationHint.self)` and invokes `recenterCaret` when `.textChanged`.

Estimated diff size: ~40–60 lines added, no deletions.

## Verification

No unit tests exist in this project (per `CLAUDE.md`). Verification is a full `Make.py build` plus a manual smoke test:

1. Open `TextStyleEditScreen` in create mode on a simulator/device.
2. Tap the "Style Name" field. Confirm keyboard slides up and the "Create" button sits above the keyboard (pre-existing behavior from the user's `inputHeight` work).
3. Type a character — with short content no scroll should occur; the scroll view remains at origin zero.
4. Tap the "Instructions" field. Type enough text to push the field past the viewport. Confirm the caret stays ~24pt above the keyboard/button as each newline is added.
5. Scroll up manually to push the active field off-screen, then type one character — confirm the scroll view snaps back so the caret sits above the keyboard.
6. In edit mode on a long pre-populated prompt, tap in the middle of the prompt (no scroll expected per non-goals), then type one character — confirm the caret's line is pulled into view.
