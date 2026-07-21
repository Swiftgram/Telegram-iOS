#if canImport(UIKit)
import UIKit
import RichTextEditorCore

/// A host-supplied checklist checkbox view. The editor stays `CheckNode`-free; the host builds a
/// `CheckNode`-backed view conforming to this and the editor hosts/positions/animates it.
public protocol RichTextChecklistMarkerView: AnyObject {
    func setChecked(_ checked: Bool, animated: Bool)
}

/// A host-supplied inline custom-emoji view. The editor hosts/positions/culls it and keeps its
/// `dynamicColor` synced to the current text color, so a "template" (single-color) custom emoji tints
/// to match the surrounding text (mirrors how the legacy input tints template emoji). A host whose
/// emoji is never a template can leave `dynamicColor` unused.
public protocol RichTextEmojiView: AnyObject {
    /// The tint the editor pushes for a custom *template* emoji — the current text color. `nil` means
    /// untinted. Non-template (full-color) emoji ignore it; the editor assigns it regardless.
    var dynamicColor: UIColor? { get set }
}

/// Shared factory: turns one `Block` into its `CanvasBlock` box. Used by the document root
/// (`DocumentCanvasView.setBlocks`), table cells (`TableBlockBox.init`), and — once landed —
/// `BlockQuoteBox` (Task 4), so all three build children through one recursive function.
///
/// - Parameters:
///   - quoteStyle:     The canvas-level `QuoteStyle`; ignored by cell callers (default is fine).
///   - pullQuoteStyle: The canvas-level `PullQuoteStyle`; ignored by cell callers.
///   - expandImage:    The expand icon for `BlockQuoteBox`; nil when irrelevant.
///   - horizontalBleed: Media bleed beyond the content strip; 0 for table cells.
@available(iOS 13.0, *)
func makeBox(for block: Block, mapper: AttributedStringMapper,
             quoteStyle: QuoteStyle = .default, pullQuoteStyle: PullQuoteStyle = .default,
             expandImage: UIImage? = nil, collapseImage: UIImage? = nil,
             horizontalBleed: CGFloat = 0, width: CGFloat) -> CanvasBlock? {
    switch block {
    case .paragraph(let p):      return BlockBox(paragraph: p, mapper: mapper, width: width)
    case .media(let img):        return MediaBlockBox(media: img, mapper: mapper, width: width,
                                                      horizontalBleed: horizontalBleed)
    case .table(let t):          return TableBlockBox(table: t, mapper: mapper, width: width)
    case .code(let c):           return CodeBlockBox(code: c, mapper: mapper, width: width)
    case .pullQuote(let pq):     return PullQuoteBox(pullQuote: pq, mapper: mapper,
                                                     pullQuoteStyle: pullQuoteStyle, width: width)
    case .blockQuote(let bq):   return BlockQuoteBox(blockQuote: bq, mapper: mapper,
                                                      quoteStyle: quoteStyle,
                                                      pullQuoteStyle: pullQuoteStyle,
                                                      expandImage: expandImage,
                                                      collapseImage: collapseImage, width: width)
    }
}

/// The multi-block document surface. ONE view owns every block and the unified global selection.
/// (Internal — only `RichTextEditorView` is public; keeps `UITextInput` witnesses internal.)
@available(iOS 13.0, *)
final class DocumentCanvasView: UIView {
    let root = BlockStack()
    var boxes: [CanvasBlock] { get { root.boxes } set { root.boxes = newValue } }
    var mapper: AttributedStringMapper
    var returnKeyType: UIReturnKeyType = .default // MARK: Swiftgram
    /// The whole-document writing-direction override (the model side of `applyWritingDirectionOverride`).
    /// Mirrored into `Document.layoutDirection` by the façade getter; render-only auto-detection is separate.
    var layoutDirectionModel: DocumentLayoutDirection = .auto
    var imageProvider: (String) -> UIImage? = { _ in nil }
    /// Returns a FRESH, non-interactive view for an emoji `id` sized to the requested square, or nil.
    /// The canvas owns/positions/removes it and keeps its `dynamicColor` synced to the current text color
    /// (template-emoji tinting); a host with only a CALayer wraps it in a conforming `UIView`.
    var emojiViewProvider: (_ id: String, _ size: CGSize) -> (UIView & RichTextEmojiView)? = { _, _ in nil }
    /// Returns a FRESH checkbox view for a checklist marker (host-side `CheckNode`). `nil` when unset —
    /// the editor falls back to the Unicode glyph marker. The canvas hosts/positions/animates the view.
    var checklistMarkerViewProvider: ((_ checked: Bool, _ size: CGSize) -> (UIView & RichTextChecklistMarkerView)?)?
    /// Host hook for editing a formula atom. The editor supplies current LaTeX and a replacement callback;
    /// the host owns presentation and formula rendering dependencies.
    var formulaEditRequested: ((_ latex: String, _ completion: @escaping (String) -> Void) -> Void)?
    /// Hosted emoji views, keyed by `EmojiRef.instanceID` so edits/undo reuse (not recreate) them.
    /// Plain `internal` (NOT `private(set)`): the reconciler in `DocumentCanvasView+Emoji.swift` mutates it.
    var emojiViews: [String: HostedEmoji] = [:]
    /// Hosted checklist checkbox views, keyed by the owning `BlockBox`'s `BlockID`. Pooled so a toggle
    /// reuses (and animates) the existing view rather than recreating it.
    var checklistMarkerViews: [BlockID: HostedChecklistMarker] = [:]
    /// Back-most container for blockquote run fills (see `BlockquoteUnderlay`). Behind every block view.
    let blockquoteUnderlay = BlockquoteUnderlay()
    /// Back-most container for pull-quote pill fills — a second `BlockquoteUnderlay` instance with
    /// `barWidth = 0` (no leading bar, symmetric rounded pill). Behind every block view, alongside the
    /// blockquote underlay.
    let pullQuoteUnderlay = BlockquoteUnderlay()
    /// Non-interactive overlay hosting an opening (top-left) and closing (bottom-right, rotated 180°)
    /// quote-mark image view per pull-quote pill, tinted to the accent. Purely decorative; all touches
    /// fall through to the canvas (`isUserInteractionEnabled = false`).
    let pullQuoteMarksView = PullQuoteMarksView()
    /// Non-interactive container for body/caption emoji views (canvas coords). Kept below the chrome
    /// overlay (which is brought to front each layout pass). Cell emoji live in the table content view.
    let emojiOverlay = UIView()
    /// Hide an emoji view when its canvas frame is more than this far outside the visible viewport.
    var emojiCullMargin: CGFloat = 50
    /// Returns a media view for a container's items (in order), or nil. The canvas owns/positions/
    /// resizes/removes it. Mirrors `emojiViewProvider` but for block-level media; carries the whole item
    /// list (not just the primary item) so a multi-media container's host view can render every item.
    /// `existing` is the currently-hosted view for this block on an items-change (nil otherwise); the host
    /// may update it IN PLACE and return the SAME instance (surviving cells reused, fetch preserved) or
    /// return a fresh instance (recreate fallback). Returns nil = "not ready" (keep any existing view).
    var mediaViewProvider: (_ items: [MediaProviderItem], _ blockID: BlockID, _ displayMode: MediaDisplayMode, _ existing: RichTextMediaItemView?) -> RichTextMediaItemView? = { _, _, _, _ in nil }
    /// Hosted media views, keyed by the OWNING block's `BlockID` (the occurrence) so edits/undo reuse —
    /// not recreate — them, and two blocks sharing one `mediaID` get two independent views.
    var mediaItemViews: [BlockID: HostedMediaItem] = [:]
    /// Pass-through container for media views (canvas coords). Kept below the chrome overlay; above block
    /// backing views so a full-bleed medium overlays its block. It is user-interaction-ENABLED but its
    /// `hitTest` returns a subview only when the touch lands on an interactive media control (e.g. the
    /// more button) — otherwise nil, so the touch falls through to the canvas's own tap handling. See
    /// `MediaPassthroughOverlayView`.
    let mediaOverlay = MediaPassthroughOverlayView()
    /// Hide a media view when its canvas frame is more than this far outside the visible viewport.
    var mediaCullMargin: CGFloat = 50
    /// Pooled dust views, keyed by spoiler-run identity so a hidden run keeps its animating emitter across
    /// reconcile passes. Mutated by the reconciler in `DocumentCanvasView+Spoilers.swift`.
    var spoilerDustViews: [SpoilerKey: HostedSpoilerDust] = [:]
    /// The spoiler runs found by the last `syncSpoilers` (hidden-state + canvas rects). Drives the tap
    /// hit-test. Recomputed each pass; never persisted.
    var spoilerRuns: [SpoilerRun] = []
    /// Set by a tap on a hidden spoiler so the next reconcile plays the EXPLOSION (vs a cross-fade) for that
    /// run, from the tap point. Consumed + cleared in one pass.
    var spoilerRevealHint: (key: SpoilerKey, canvasPoint: CGPoint)?
    /// Non-interactive container for body/caption dust views (canvas coords), above emoji, below the wash.
    /// Cell dust rides the table content view (like cell emoji).
    let spoilerOverlay = UIView()
    /// Hide a dust view when its canvas frame is more than this far outside the visible viewport.
    var spoilerCullMargin: CGFloat = 50
    /// True iff some leaf region currently carries a `.rtSpoiler` run. A cheap gate so `syncSpoilers` (which
    /// runs on every caret move) does NO work in a spoiler-free document. Recomputed only when the model
    /// changes (load / edit / undo) — never on a pure selection change.
    var documentHasSpoilers = false
    /// Overscan band (points) realized above AND below the visible viewport, so scrolling reveals an
    /// already-drawn paragraph instead of a blank flash. NEGATIVE (the default) ⇒ auto = one viewport
    /// height each side. Tunable via the façade (`RichTextEditorView.blockViewOverscan`).
    var blockViewOverscan: CGFloat = -1
    /// Persistent block-view subviews, keyed by BlockID so edits/undo reuse (not recreate) them.
    private(set) var blockViews: [BlockID: BlockBackingView] = [:]
    /// Bounded reuse queue of free PARAGRAPH/IMAGE backing views (both plain `BlockBackingView`). A culled
    /// view is detached + dropped from `blockViews` and pushed here; a newly-realized paragraph/image pops
    /// it and rebinds. Tables (`TableBackingView`) are heavyweight + few, so they are created/destroyed,
    /// not queued. Excess beyond the cap is released.
    private var recycleQueue: [BlockBackingView] = []
    private let recycleQueueCap = 24   // ~2–3 screenfuls of paragraphs at typical heights; excess freed views are released
    /// Topmost overlay that draws table structural chrome (outline, handles, knobs) ABOVE the block views.
    private let blockChromeOverlay = BlockChromeOverlay()
    /// Dedicated overlay that draws the selection highlight + image washes ON TOP of all non-table content
    /// (text, emoji, image atoms) — above the emoji overlay, below the chrome. Table-cell highlights ride
    /// their own content-view overlay (`CellSelectionView`) to keep horizontal overscroll.
    let selectionHighlight = SelectionHighlightView()

    /// The app's own blinking text caret (the canvas installs no `UITextSelectionDisplayInteraction`, so
    /// there is no OS caret). When the caret is inside a horizontally-scrollable table cell it's reparented
    /// into that table's scrolling content view so it rides the scroll/overscroll; otherwise it's a direct
    /// subview of the canvas.
    let caretView = CaretView()
    /// The own-rendered FLOATING caret for the spacebar-trackpad gesture (see DocumentCanvasView+FloatingCursor).
    let transientCaretView = TransientCaretView()
    /// Own-drawn selection-handle lollipops (one per endpoint), shown for a ranged selection. Like the
    /// caret, each is hosted in the canvas or a table's scrolling content view per its endpoint's region,
    /// ON TOP of the wash. The handle DRAG is a separate proximity-gated pan (`isSelectionDragTouch`).
    let startHandleView = SelectionHandleView(isStart: true)
    let endHandleView = SelectionHandleView(isStart: false)
    /// Host hook to configure each selection-handle ("knob") view — e.g. to set Display's
    /// `disablesInteractiveModalDismiss` / `disablesInteractiveKeyboardGestureRecognizer` so a knob drag isn't
    /// hijacked by the interactive modal/keyboard-dismiss gestures. The package can't import Display, so the
    /// host applies the flags; the handle views are hit-testable so the flags are scoped to knob interaction.
    /// Applied to BOTH handle views (passed as bare `UIView`s) when set.
    var configureSelectionHandleView: ((UIView) -> Void)? {
        didSet {
            configureSelectionHandleView?(startHandleView)
            configureSelectionHandleView?(endHandleView)
        }
    }
    /// The container + frame the caret view was last placed at, so a repeated `updateCaretView()` (e.g. on a
    /// scroll tick) that lands the caret at the SAME spot does NOT restart the blink.
    private weak var lastCaretContainer: UIView?
    private var lastCaretFrame: CGRect = .null

    /// Fired by `notifyContentSizeChanged()` whenever the content height may have changed (after an
    /// edit/undo/IME/document-swap). The host (`RichTextEditorView`) sizes the canvas frame-based, not via
    /// Auto Layout, so the canvas does NOT lay itself out — it notifies through this hook and the parent
    /// drives layout explicitly (`performLayout` → `layoutContent`).
    var onContentSizeChange: (() -> Void)?
    /// Fired whenever the caret moves to a spot the host may need to reveal: the OS moving the selection
    /// through the `selectedTextRange` setter (hardware arrow navigation), and every editing operation
    /// that relocates the caret (typing, delete, Enter, IME-composition commit — via `editing { }` and the
    /// marked-text branch). The host uses it to scroll the caret into view, since these can land the caret
    /// off-screen (arrowing up out of a tall image; typing the line below the keyboard).
    var onSelectionChange: (() -> Void)?
    /// Fired once when the canvas actually GAINS first-responder status (not on a repeat
    /// `becomeFirstResponder()` while already focused — the tap handlers call it unconditionally). The
    /// host surfaces this as `RichTextEditorView.onBecameFirstResponder`.
    var onBecameFirstResponder: (() -> Void)?
    /// Fired once when the canvas actually RESIGNS first-responder status. Surfaced as
    /// `RichTextEditorView.onResignedFirstResponder`.
    var onResignedFirstResponder: (() -> Void)?
    /// Pasting MEDIA (image/gif/video/sticker) is a host concern — the editor never embeds it inline.
    /// `canPasteMedia` answers whether Paste should be offered for the current pasteboard (so the menu item
    /// shows for an image-only clipboard); `onPasteMedia` performs the media paste (routing to the host's
    /// send flow) and returns whether it consumed the paste. Consulted only when there is no TEXT rep — the
    /// editor pastes text (fragment/RTF/plain) itself.
    var canPasteMedia: (() -> Bool)?
    var onPasteMedia: (() -> Bool)?

    /// A HARDWARE-keyboard Return (plain or ⌘) routes here before the editor inserts a newline, so a host
    /// (the chat composer) can send-on-Enter / send-on-⌘-Enter. Mirrors the legacy `ChatInputTextViewImpl`'s
    /// `shouldReturn`. Return `true` to have the editor insert a newline (the default when unset — standalone
    /// editors like the article composer and Demo just add a line); `false` means the host consumed the Return
    /// (e.g. sent the message) and the editor does nothing. The SOFTWARE keyboard's Return never triggers a
    /// keyCommand, so it always inserts a newline (there's a separate send button) — matching the legacy input.
    var onHardwareReturn: ((UIKeyModifierFlags) -> Bool)?

    /// Interior content margins — interactable padding around the document, ADDED to the built-in
    /// `pageMargin`. Unlike the host's scroll insets (covered by chrome/keyboard, content scrolls under),
    /// these are PART of the content: the text lays out inset by them (so it wraps narrower and is offset
    /// from the canvas edges), the content height grows by top+bottom, and the margin area still hit-tests
    /// to the nearest text position. Applied by `RichTextEditorView.update(size:insets:contentMargins:)`
    /// (a layout-affecting input, passed every update); default `.zero`. A plain stored value: the `update`
    /// that sets it re-runs `performLayout`, which lays the canvas out EXPLICITLY (`layoutContent()`), so the
    /// setter neither schedules layout itself nor fires `onContentSizeChange`/`onChange`.
    var contentMargins: UIEdgeInsets = .zero

    /// The built-in horizontal page margin applied to paragraph/table text (in addition to `contentMargins`).
    /// Defaults to the document metric (`CanvasMetrics.pageMargin`, 16pt); a compact host (e.g. the chat
    /// composer) can set it to 0 so the host controls all horizontal insets via the frame + `contentMargins`.
    /// Media bleed is governed separately by `mediaBlockStyle` / `applyMediaBlockStyle`.
    var pageMargin: CGFloat = CanvasMetrics.pageMargin

    /// The base inter-block vertical inset for the document root (each side). Defaults to the document
    /// metric (`BlockBox.defaultVerticalInset`, 8pt); a compact host (the chat composer) sets it to 0 so a
    /// single paragraph hugs its text height instead of carrying the inter-paragraph gap. Applied to the
    /// root stack in `layoutContent`; nested (table-cell) stacks keep the document default.
    var blockVerticalInset: CGFloat = BlockBox.defaultVerticalInset

    /// Per-host media geometry. Applied via `applyMediaBlockStyle(_:)`; read at `MediaBlockBox` creation
    /// in `setBlocks` / `insertMedia`. Defaults to the document edge-to-edge look.
    var mediaBlockStyle: MediaBlockStyle = .default

    /// Per-host quote geometry. Applied via `applyQuoteStyle(_:)` (rebuilds the mapper stylesheet + pushes
    /// render values to the underlay). Read by `blockquoteDecorations()` for the bar width.
    var quoteStyle: QuoteStyle = .default

    /// Per-host pull-quote geometry. Applied via `applyPullQuoteStyle(_:)` (pushes corner radius + fill alpha
    /// to the underlay). Read by `pullQuotePillRects()` / `pullQuoteMarkRects()` for the pill + mark geometry.
    var pullQuoteStyle: PullQuoteStyle = .default

    /// Host-injected collapse/expand icons (nil ⇒ no affordance drawn). The `collapse` image goes to
    /// `BlockQuoteBox`; the `expand` image likewise.
    var quoteCollapseIcons: RichTextEditorQuoteCollapseIcons?

    /// Placeholder strings drawn in empty paragraphs. Stamped onto each top-level box during layout.
    /// Defaults to the editor's built-in hints; a compact host (chat composer) sets them to "" to suppress
    /// the editor's placeholder (it draws its own). Applied on the next layout pass.
    var placeholders: RichTextEditorPlaceholders = .default

    /// Whether a tap in the empty area below the document's last block appends a new empty body paragraph
    /// after it (`insertEmptyBodyParagraph`). Defaults to `true` (the full-page document editor: lets you
    /// always start a normal paragraph below the final block, whatever its type). A compact host (the chat
    /// composer) sets it to `false` — there is no "empty area below the content" to grow into, so a tap there
    /// just places the caret in the existing trailing paragraph.
    var tapBelowAddsTrailingParagraph = true

    // Selection as global UTF-16 positions; `anchor` fixed, `head` moving.
    var anchor = 0
    var head = 0

    /// True while a floating-cursor (spacebar-trackpad) gesture owns the caret; turns the steady caret into
    /// the dimmed "landing" indicator in `updateCaretView`.
    var floatingCursorActive = false
    // Floating cursor (spacebar-trackpad) gesture state — see DocumentCanvasView+FloatingCursor.swift.
    var floatingCursorPoint: CGPoint = .zero   // the last raw floating point (canvas coords)
    var floatingScrollLink: CADisplayLink?
    var floatingScrollVelocity: CGFloat = 0

    /// Last non-zero width laid out; used to rebuild boxes during undo (extensions can't add
    /// stored properties, so it lives here).
    var lastLayoutWidth: CGFloat = 0
    var effectiveWidth: CGFloat { lastLayoutWidth > 0 ? lastLayoutWidth : (bounds.width > 0 ? bounds.width : 320) }

    func clampGlobal(_ n: Int) -> Int { min(max(n, 0), documentSize) }

    /// Resolves a global position to the box that owns it, snapping structural-boundary and
    /// end-of-document positions to the nearest in-text position. Returns the box, the local
    /// UTF-16 offset, and the box's index.
    func resolveBox(at pos: Int) -> (box: CanvasBlock, local: Int, index: Int)? {
        if let (b, l) = box(containingGlobal: pos), let i = boxIndex(of: b) { return (b, l, i) }
        for (i, b) in boxes.enumerated() {
            if pos < b.textStart { return (b, 0, i) }
            if pos <= b.textStart + b.textLength { return (b, pos - b.textStart, i) }
        }
        if let last = boxes.last { return (last, last.textLength, boxes.count - 1) }
        return nil
    }
    private(set) var documentSize = 0
    var selFrom: Int { min(anchor, head) }
    var selTo: Int { max(anchor, head) }

    // UITextInput plumbing + undo.
    var textInputDelegate: UITextInputDelegate?
    // Created lazily in the `tokenizer` getter (Task 5) — declaring it with `= ...textInput: self`
    // here would require the UITextInput conformance to type-check before it exists.
    var inputTokenizer: UITextInputTokenizer?
    /// iOS 16+ system edit-menu interaction. Untyped storage because a stored property can't be
    /// `@available`-gated narrower than its (now iOS-13) enclosing type, while `UIEditMenuInteraction` is
    /// iOS 16+; below 16 the canvas falls back to `UIMenuController` (see DocumentCanvasView+EditMenu).
    private var editMenuInteractionStorage: AnyObject?
    @available(iOS 16.0, *)
    var editMenuInteraction: UIEditMenuInteraction? {
        get { editMenuInteractionStorage as? UIEditMenuInteraction }
        set { editMenuInteractionStorage = newValue }
    }
    /// Host-provided transform of the edit-menu elements. Consulted by the iOS-16 `menuFor:` delegate only,
    /// and only for a non-collapsed selection. nil ⇒ the editor's default menu. (iOS 13–15 keeps its built-in
    /// items — see DocumentCanvasView+EditMenu; UIMenuItem cannot carry a closure.)
    var hostContextMenuItemsProvider: ((_ defaultElements: [UIMenuElement]) -> [UIMenuElement])?
    /// Host hook for the table row/column structural menu. Fired from the `.menu` handle-tap case with a
    /// framework-agnostic description; the host presents its own ContextController. nil ⇒ no menu shown.
    var onRequestTableStructuralMenu: ((TableStructuralMenuRequest) -> Void)?
    /// Host hook for a media control (the "more" button; the "+" later). Fired from a bound media view with
    /// an account-free `MediaControlRequest` (opaque `mediaID` + occurrence-bound operation closures); the
    /// host resolves the concrete media and presents its own menu. nil ⇒ no menu shown.
    var onRequestMediaControl: ((MediaControlRequest) -> Void)?
    /// Whether the edit menu is currently presented (tracked via UIEditMenuInteractionDelegate), so a tap
    /// on the caret/selection can TOGGLE the menu instead of re-presenting it (the close-then-reopen flicker).
    var editMenuVisible = false
    /// Test observability: counts `dismissEditMenu()` calls (a presented `UIEditMenuInteraction` can't be
    /// driven in a unit test, so the auto-dismiss-on-change behavior is asserted via this counter).
    var dismissEditMenuCountForTesting = 0
    /// Reference-time of the last edit-menu dismissal. The system auto-dismisses the menu on a tap-down,
    /// BEFORE our single-tap handler runs (on tap-up), so `editMenuVisible` is already false by then; this
    /// lets the handler tell "this tap just dismissed the menu" from "no menu was up".
    var lastMenuDismissTime: TimeInterval = 0
    /// Manual multi-tap counting (see `handleTap`). The single-tap recognizer is no longer gated on a
    /// double-tap recognizer FAILING — that `require(toFail:)` made every caret placement wait out the
    /// ~0.35s multi-tap window. One 1-tap recognizer now fires immediately and these track the rapid-tap
    /// run that escalates caret → word → paragraph.
    var lastTapTime: TimeInterval = 0
    var lastTapLocation: CGPoint = .zero
    var tapCount = 0
    /// Set on a genuine not-focused→focused transition (`becomeFirstResponder`), consumed by the next
    /// `performSingleTap`. A FOCUSING tap must only place the caret, never open the menu. We can't detect it
    /// from `isFirstResponder` at touch-up: the chat composer focuses the editor on touch-DOWN (the panel's
    /// `ensureFocusedOnTap`), so by the time the tap handler runs `isFirstResponder` is already true. This flag
    /// captures the transition regardless of who triggered it (touch-down focus or the handler's own
    /// `ensureFirstResponder`).
    var didJustBecomeFirstResponder = false
    /// Active magnifier loupe during a long-press caret drag (iOS 17+). Begun on `.began`, moved on
    /// `.changed`, invalidated + niled on `.ended`/`.cancelled`/`.failed`. The storage is untyped because a
    /// stored property can't be `@available`-gated narrower than its enclosing (iOS-16) type, while
    /// `UITextLoupeSession` is iOS 17+; the typed accessor below is the gated view onto it.
    private var loupeSessionStorage: AnyObject?
    @available(iOS 17.0, *)
    var loupeSession: UITextLoupeSession? {
        get { loupeSessionStorage as? UITextLoupeSession }
        set { loupeSessionStorage = newValue }
    }
    /// SPIKE (loupe grow-from-cursor): a `UITextSelectionDisplayInteraction` (iOS 17+) installed solely to borrow
    /// its system `cursorView` for the loupe's `fromSelectionWidgetView`. Kept DEACTIVATED except during a loupe
    /// drag. Untyped storage for the same availability reason as `loupeSessionStorage`. INSTRUMENTED — evaluate
    /// the leaked-chrome logs before deciding whether this can stay.
    private var selectionDisplayInteractionStorage: AnyObject?
    @available(iOS 17.0, *)
    var selectionDisplayInteraction: UITextSelectionDisplayInteraction? {
        get { selectionDisplayInteractionStorage as? UITextSelectionDisplayInteraction }
        set { selectionDisplayInteractionStorage = newValue }
    }
    /// SPIKE: a stable container the borrowed interaction hosts its selection chrome in (via the delegate). It is
    /// NOT tracked in `blockViews`, so the block-view reload loop never removes it, and it is created lazily on the
    /// first loupe drag. All the interaction's chrome (cursor / lollipops / accessory) lands here so we can hide it.
    lazy var selectionChromeContainer: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.clipsToBounds = false
        addSubview(v)
        return v
    }()
    /// True for the duration of a long-press magnifier (loupe) drag. While set, `updateCaretView` keeps the
    /// steady caret SOLID (no blink, full alpha) so the loupe lifts off from / magnifies a crisp caret — a
    /// blinking caret is invisible for the part of each cycle its opacity dips toward 0, which made the loupe
    /// appear to pop in "from nothing" with no visible cursor (device-log-verified). Set BEFORE `begin(...)`
    /// (so the caret is already solid when the loupe captures it) and cleared on drag end.
    var loupeDragActive = false
    /// The current finger x (canvas/self space) during a loupe drag, set by the long-press handler each frame.
    /// `updateCaretView`'s loupe branch reads it to hide the gray "shadow" (`caretView`) while the accent glider
    /// at the finger sits within `loupeShadowMinSeparation` of the snapped caret. Owned here (not in
    /// `positionLoupeShadow`) so a re-run of `updateCaretView` — the loupe magnifier forces layout passes —
    /// re-applies the rule instead of `freezeSolid` leaving the shadow visible. `nil` when not dragging.
    var loupeFingerX: CGFloat?
    /// True when the current long-press `.began` was consumed as the follow-up tap of a double-/triple-tap
    /// (see `handleLoupeBegan`) rather than starting a loupe cursor-drag. While set, the long-press `.changed`
    /// / `.ended` handlers no-op (no `setCaret`, no loupe teardown) so the word/paragraph selection they made
    /// survives the rest of the gesture. Reset when the gesture ends.
    var loupeConsumedAsMultiTap = false
    /// Whether the edit menu was already showing when the current loupe long-press began, and the caret's global
    /// position at that moment — captured in `.began` so `.ended` can tell a STATIONARY press on an open menu
    /// (a tap-like toggle-off — suppress the re-present, else the menu flickers disappear-then-reappear) from a
    /// real cursor drag (present at the new position). A quick tap near the caret is caught as a loupe (the
    /// near-cursor press delay is 0.05s), so the loupe must match the tap path's menu-toggle semantics.
    var loupeMenuWasVisibleAtBegan = false
    var loupeHeadAtBegan = 0
    /// The steady caret's normal accent, saved while a loupe drag recolors it to the desaturated "shadow" gray
    /// (the snapped landing caret is the gray shadow; the gliding `transientCaretView` is the accent). Restored
    /// on drag end.
    var loupeSavedCaretAccent: UIColor?
    var draggingEndpoint: SelectionEndpoint?
    // The (caret-center − initial-touch) offset captured when a selection-handle drag begins, so the dragged
    // endpoint keeps its starting offset from the finger instead of snapping to the line under the touch (the
    // knob is drawn offset from the text line). Applied at every drag map via `selectionDragPosition(forTouch:)`.
    var selectionDragGrabOffset: CGSize = .zero
    var draggingTableKnob: TableRangeEnd?
    // A `.cells` corner-knob drag (Phase 2c-T4) — set in `.began` when the touch hits a corner knob, either a
    // committed `.cells` selection's or the focused-cell "fake" chrome's (no committed selection yet). The
    // FIRST `extendCellSelection` call promotes the fake chrome to a real committed `.cells` selection.
    var draggingTableCornerKnob: TableCellCorner?
    var selectionHandlePan: UIPanGestureRecognizer?
    // The loupe / move-cursor long-press. Held so `gestureRecognizerShouldBegin` can fail it on a touch that
    // lands on an active selection handle (letting the handle pan grab the knob instead) — see that method.
    var loupeLongPress: LocationAdaptiveLongPressGestureRecognizer?
    // True while an interactive selection-handle drag is in flight. While set, the per-touch-move selection
    // setters (`setSelectionHead`/`setSelectionAnchor`) SKIP the `inputDelegate` selection bracket; one
    // bracket fires when the drag ends (`endCoalescedSelectionDrag`). Driving the keyboard's autocorrect/
    // candidate pipeline (`-[_UIKeyboardStateManager updateForChangedSelection]`, which also re-enters our
    // tokenizer) on every frame pegs the CPU and is meaningless mid-drag — you can't accept a suggestion
    // while dragging a handle. The `selectedTextRange` getter stays live, so the OS reads the correct value
    // if it queries during the drag; only the proactive candidate recompute is deferred to the gesture end.
    var coalescingSelectionNotifications = false
    // Auto-scroll state while dragging a text-selection handle near an edge: vertically against the host
    // document scroll view, and/or horizontally within a scrollable table the head is in. One display link
    // drives both axes.
    private(set) var dragAutoScrollLink: CADisplayLink?
    private(set) var dragAutoScrollTable: TableBlockBox?
    private(set) var dragAutoScrollVelocityX: CGFloat = 0   // table horizontal, points/tick, signed
    private(set) var dragAutoScrollVelocityY: CGFloat = 0   // document vertical, points/tick, signed
    private(set) var dragAutoScrollPoint: CGPoint = .zero   // last touch (canvas coords), for re-extending
    /// Transient table row/column structural selection (separate from the text selection). The `table` id
    /// guards against a stale selection after the active table is rebuilt. nil = none. Mutually exclusive
    /// with `imageSelection`.
    var tableSelection: (table: BlockID, kind: TableStructuralSelection)?
    /// Transient atom-selection of a top-level image (separate from the text selection). The BlockID
    /// guards a stale selection after a relayout/undo. nil = none. Mutually exclusive with `tableSelection`.
    var imageSelection: BlockID?
    /// The image whose `imageSelection` was just cleared by the `selectedTextRange` setter — iOS overrides a
    /// tap-selected media's selection (clearing `imageSelection`) right before its Backspace. `deleteBackward`
    /// consumes this to replace that media; any non-delete edit clears it. nil = none.
    var imageObjectDeletePending: BlockID?
    /// Marked (composing/provisional) text as global positions over the same axis as `(anchor, head)`.
    /// nil = no active composition. The provisional characters live in the leaf region's storage like
    /// any committed text; this just tracks which range is provisional (for the underline + commit).
    var markedRange: (from: Int, to: Int)?
    /// True when the active marked text is a system INLINE PREDICTION (ghost text: `setMarkedText` with
    /// the caret at the start, `sel == {0,0}`) rather than CJK/IME composition. Predictions are
    /// keyboard-owned provisional text: a gesture/focus interruption must DISMISS the ghost (remove it),
    /// never COMMIT it — committing desyncs the keyboard's shadow doc and duplicates the word on accept.
    var markedTextIsPrediction = false
    /// The layout currently carrying the grey prediction-ghost rendering colour (display-only), so it
    /// can be cleared when the prediction moves or ends. Weak: the layout is owned by its box.
    weak var ghostStyledLayout: BlockLayoutEngine?
    /// Document + selection snapshot captured at composition START, registered as ONE undo at commit
    /// (so undo removes the whole composed word, not each keystroke).
    var compositionUndoSnapshot: [Block]?
    var compositionAnchorHead: (Int, Int)?
    /// Injectable pasteboard (defaults to the system pasteboard; tests inject a fake — see TextPasteboard).
    var pasteboard: TextPasteboard = UIPasteboard.general
    // MARK: Spell checking (see DocumentCanvasView+SpellCheck, +NativeTextCheckingClient)
    /// Native-checking underline style per flagged range.
    enum SpellStyle: Equatable { case spelling, grammar, correction }
    /// Per-region flagged ranges in REGION-LOCAL UTF-16, keyed by the owning block's id (from the region's
    /// `ref`). `contentHash` is reserved for a future content-keyed cache (native checking self-invalidates
    /// via the controller, so it is currently unused — 0).
    /// Accepted limitation: this is a side table edits do NOT shift, so a flagged word positioned after a
    /// mid-region edit renders at a stale offset until the caret next re-traverses it (self-healing). The old
    /// debounced full-region rescan used to mask this by rebuilding every flag on each pass.
    var spellResults: [BlockID: (contentHash: Int, ranges: [(range: NSRange, style: SpellStyle)])] = [:]
    /// Delivered `.correction` candidate replacements ("alternatives"), region-local — mirrors `spellResults`.
    /// Stashed from `nativeReplace` via KVC on the delivered `NSTextAlternatives` (see
    /// `+NativeTextCheckingClient.stashSpellingAlternatives`); best-effort (corrections were not observed firing
    /// in the test host). `.spelling`/`.grammar` flags never populate this — those go through the public
    /// `UITextChecker` guesses lookup instead (`+SpellCheck.nativeSpellingGuesses`).
    var spellingAlternatives: [BlockID: [(range: NSRange, candidates: [String], primary: String?)]] = [:]
    /// The native checking driver (nil ⇒ private class unavailable ⇒ checking off; no fallback).
    var nativeChecker: NativeTextChecker?
    /// Global caret position at the last selection-driven native check. nil until the first post-focus
    /// selection settles: native does NOT scan on focus — only words the caret traverses are checked.
    var lastCheckedCaret: Int?
    /// Set only for the duration of a driven `checkSpellingForWord`/`checkGrammarForSentence` call. The
    /// controller calls back `removeAnnotation:forRange:` SYNCHRONOUSLY within that call whenever the
    /// checked word/sentence turns out clean (verified live) — without knowing which check triggered it,
    /// `nativeRemoveAnnotation` can't tell a stale `.spelling` flag from an unrelated `.grammar` flag that
    /// merely overlaps the checked word, and would wipe both (the same style-isolation bug `.spelling`
    /// clears in `nativeCheckOnSelectionChange` have). Bracketed by `driveNativeCheck(style:_:)`.
    var inFlightCheckStyle: SpellStyle?
    /// Host toggle (façade `isSpellCheckingEnabled`). When false: no checking, no underlines, no tap override.
    var isSpellCheckingEnabled = true {
        didSet {
            guard oldValue != isSpellCheckingEnabled else { return }
            if isSpellCheckingEnabled { installNativeCheckingIfNeeded(); nativeChecker?.preheat() }
            else { nativeChecker?.invalidate(); nativeChecker = nil; spellResults = [:]; spellingAlternatives = [:]; pendingSpellingMenu = nil; setNeedsSpellUnderlineDisplay() }
            reloadInputViews()   // let the keyboard re-read the trait
        }
    }
    /// Set while the tap-to-fix guesses menu is up; `range` is GLOBAL (same axis as the selection).
    /// `revertTo` is the pre-correction original word — non-nil only for a `.correction` flag with a stashed
    /// `spellingAlternatives` entry (best-effort; see that field's doc) — and drives the "Revert to …" menu
    /// action added in N5.
    var pendingSpellingMenu: (range: NSRange, guesses: [String], revertTo: String?)?
    var undoManagerOverride: UndoManager?
    /// The editor's OWN undo manager, used in production. We deliberately do NOT fall back to the
    /// responder-chain `UIResponder.undoManager`: that manager is shared app-wide, so OTHER responders'
    /// (and the system text-input subsystem's) selection/typing undo registrations would surface in the
    /// editor's `canUndo` / `undo()` — the "a selection change is undoable / undo is active on the first
    /// tap before any content edit" bug. A private per-canvas manager keeps the buffer pristine: only the
    /// editor's own content edits (every `registerUndo`) count. Tests inject their own via `undoManagerOverride`.
    private let ownUndoManager = UndoManager()
    var effectiveUndoManager: UndoManager? { undoManagerOverride ?? ownUndoManager }

    /// Expose the editor's OWN (dedicated, private) undo manager to the responder chain so the SYSTEM undo
    /// affordances act on our edits: hardware ⌘Z / ⌘⇧Z, shake-to-undo, and the Edit-menu Undo/Redo items.
    /// Without this override, `UIResponder.undoManager` returns the app-wide SHARED manager (the window's),
    /// which our edits never touch — so ⌘Z did nothing after we went private for buffer isolation.
    ///
    /// **Safe by construction:** overriding `undoManager` changes only WHO can call `undo()` on our manager,
    /// not WHAT is registered into it. This manager only ever receives our `editing()` content-edit
    /// registrations (we register nothing on selection changes), and it is a private instance no other
    /// responder holds — so the foreign-entry pollution that motivated going private (which lived in the
    /// shared instance we no longer use) cannot appear here. UIKit does not auto-register typing/selection
    /// undos into a bare custom `UITextInput` (it owns no text here) and — like `UITextView` — never records
    /// cursor movements as undo steps.
    override var undoManager: UndoManager? { effectiveUndoManager }

    /// Coalescing kind for an edit: consecutive `.typing` (or consecutive `.deleting`) edits that
    /// are contiguous collapse into ONE undo step; `.none` always starts/breaks a step (structural,
    /// format, paste, media, list, table edits).
    enum UndoCoalescing { case typing, deleting, none }
    /// The currently-open coalescing run. `caret` is where the NEXT contiguous keystroke must land
    /// for it to join this run. `nil` = no open run (the next edit registers a fresh undo step).
    var openUndoRun: (kind: UndoCoalescing, caret: Int)?
    /// Number of NEW undo steps `editing` has started (a coalesced keystroke registers nothing, so it
    /// does not increment). A test seam that measures coalescing directly, independent of NSUndoManager
    /// grouping — mirrors the module's other internal test hooks.
    var undoRegistrationCount = 0
    /// Closes any open coalescing run so the next edit registers a fresh undo step. Called on every
    /// run-breaking boundary that isn't already caught by the contiguity check (undo/redo restore,
    /// IME commit, document swap, resign-first-responder).
    func breakUndoCoalescing() { openUndoRun = nil }

    /// Token for the input-language-change observer (see init); removed in deinit.
    private var inputModeObserver: NSObjectProtocol?
    deinit {
        if let inputModeObserver { NotificationCenter.default.removeObserver(inputModeObserver) }
        nativeChecker?.invalidate(); nativeChecker = nil   // tear down the native checking controller explicitly
    }

    init(mapper: AttributedStringMapper = AttributedStringMapper()) {
        self.mapper = mapper
        super.init(frame: .zero)
        // Re-flip an empty paragraph's caret when the input language changes (globe key) or the keyboard
        // first appears — `currentInputModeDidChange` fires for both. So an RTL input language puts the
        // caret on the right of an empty paragraph live, without a reload/refocus. `queue: nil` delivers
        // synchronously on the posting (main) thread.
        self.inputModeObserver = NotificationCenter.default.addObserver(
            forName: UITextInputMode.currentInputModeDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.refreshEmptyBoxWritingDirections()
            self?.updateCaretView()
        }
        backgroundColor = .systemBackground
        blockChromeOverlay.canvas = self
        addSubview(blockquoteUnderlay)   // back-most: blockquote fills behind every block view
        pullQuoteUnderlay.barWidth = 0                             // no leading bar — a symmetric pill
        pullQuoteUnderlay.accentColor = blockquoteUnderlay.accentColor
        // Corner radius + fill come from the pull-quote style (NOT the block-quote underlay) so the default
        // pull-quote look applies even in hosts that never assign a custom pullQuoteStyle (e.g. the composer).
        pullQuoteUnderlay.cornerRadius = pullQuoteStyle.cornerRadius
        pullQuoteUnderlay.fillAlpha = pullQuoteStyle.fillAlpha
        addSubview(pullQuoteUnderlay)    // back-most: pull-quote pill fills behind every block view
        emojiOverlay.isUserInteractionEnabled = false
        emojiOverlay.backgroundColor = .clear
        addSubview(emojiOverlay)
        mediaOverlay.isUserInteractionEnabled = true   // pass-through: only interactive media controls claim a touch (see MediaPassthroughOverlayView)
        mediaOverlay.backgroundColor = .clear
        addSubview(mediaOverlay)   // above block backing views, below the selection wash / chrome
        spoilerOverlay.isUserInteractionEnabled = false
        spoilerOverlay.backgroundColor = .clear
        addSubview(spoilerOverlay)   // above emoji, below the selection wash
        selectionHighlight.canvas = self
        addSubview(selectionHighlight)   // selection wash, above text + emoji, below chrome
        addSubview(blockChromeOverlay)
        // Interactive collapse-button overlay: above text/chrome, but hitTest passes only button touches
        // so caret placement / text selection / table chrome all still work through it.
        // Non-interactive pull-quote corner-mark overlay (decorative; isUserInteractionEnabled = false).
        addSubview(pullQuoteMarksView)
        addSubview(caretView)   // own caret, above content; reparented into a table's content view when needed
        addSubview(transientCaretView)   // own floating caret, above content; reparented like caretView
        addSubview(startHandleView)   // own-drawn selection handles, hosted per-endpoint like the caret
        addSubview(endHandleView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var canBecomeFirstResponder: Bool { true }

    /// When non-nil, replaces the system keyboard while the canvas stays first responder (a consumer
    /// sets e.g. an `EmptyInputView` to hide the keyboard while showing a separate emoji panel, so the
    /// caret keeps rendering). `nil` ⇒ system keyboard.
    var customInputView: UIView?
    override var inputView: UIView? { return self.customInputView }

    /// Test seam: when set, replaces the live `textInputMode?.primaryLanguage` lookup.
    /// Avoids subclassing the `final class DocumentCanvasView` just for tests.
    var keyboardLanguageProviderForTesting: (() -> String?)?

    /// Keyboard input-language pre-selection (mirrors the legacy `ChatInputTextView`). The chat composer
    /// seeds `initialPrimaryLanguage` from the draft's saved keyboard language. On the FIRST `textInputMode`
    /// query after it is set, return the active input mode whose `primaryLanguage` matches, so the keyboard
    /// opens in that language; thereafter report `super.textInputMode` (the live keyboard), which is the value
    /// the host reads back as the current input language.
    ///
    /// LOAD-BEARING ORDERING INVARIANT: the override is single-shot (the first query consumes the
    /// pre-selection and flips `didInitializePrimaryInputLanguage`). The host's read-back also queries
    /// `textInputMode`, so correctness depends on UIKit querying first — which it does, because
    /// `becomeFirstResponder` brings up the keyboard (querying `textInputMode`) before any keystroke or host
    /// read. This matches the legacy node exactly; do NOT add a separate non-side-effecting read path.
    var initialPrimaryLanguage: String?
    private var didInitializePrimaryInputLanguage = false

    override var textInputMode: UITextInputMode? {
        if !self.didInitializePrimaryInputLanguage {
            self.didInitializePrimaryInputLanguage = true
            if let initialPrimaryLanguage = self.initialPrimaryLanguage {
                for inputMode in UITextInputMode.activeInputModes {
                    if let primaryLanguage = inputMode.primaryLanguage, primaryLanguage == initialPrimaryLanguage {
                        return inputMode
                    }
                }
            }
        }
        return super.textInputMode
    }

    /// Re-arm the pre-selection so the next `textInputMode` query re-applies `initialPrimaryLanguage`.
    /// (The legacy `ChatInputTextNode.resetInitialPrimaryLanguage()` body is empty; this implements the
    /// documented intent. For the rich node this path is currently unreachable — its only caller is gated on
    /// `isCurrentlyEmoji()`, which the node reports `false`.)
    func resetInitialPrimaryLanguage() {
        self.didInitializePrimaryInputLanguage = false
        self.reloadInputViews()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let wasFirstResponder = isFirstResponder                         // capture BEFORE super flips it
        let became = super.becomeFirstResponder()
        if became { refreshEmptyBoxWritingDirections(); updateCaretView(); updateSelectionHandleViews() }   // show own-drawn caret/handles once focused
        if became && !wasFirstResponder { didJustBecomeFirstResponder = true; onBecameFirstResponder?() }   // only the real not-focused→focused transition
        if became { installNativeCheckingIfNeeded(); nativeChecker?.preheat(); lastCheckedCaret = head }   // install+preheat; no scan (native checks only traversed words)
        return became
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        finalizeMarkedText()
        breakUndoCoalescing()   // losing focus ends any open typing/deleting run (matches native)
        cancelFloatingCursor()                                           // tear down any in-flight floating-cursor gesture (display link retains self)
        let wasFirstResponder = isFirstResponder                         // capture BEFORE super flips it
        let resigned = super.resignFirstResponder()
        if resigned { updateCaretView(); updateSelectionHandleViews() }   // hide caret + handles (no longer FR)
        if resigned { didJustBecomeFirstResponder = false }              // don't carry a stale focusing-tap flag across a defocus
        if resigned && wasFirstResponder { onResignedFirstResponder?() } // only the real focused→not-focused transition
        return resigned
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTabKey)),
         UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(handleShiftTabKey)),
         // HARDWARE Return (plain + ⌘) routes to the host's return handler (send-on-Enter / ⌘-Enter) before
         // the editor inserts a newline — mirrors the legacy ChatInputTextViewImpl's own \r keyCommands. As the
         // first responder these take precedence over the app-level empty-action \r shortcut (which only
         // supplied the "Send Message" discoverability title). The SOFTWARE keyboard's Return doesn't fire
         // keyCommands, so it still inserts a newline via insertText.
         UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleReturnKey(_:))),
         UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(handleReturnKey(_:))),
         // Formatting shortcuts owned by the editor. The app-level ones (ChatControllerKeyShortcuts) mutate
         // the LEGACY ChatTextInputState (NSAttributedString), which the native editor doesn't use — so ⌘B
         // etc. silently no-op'd once the editor became the composer. The editor is the first responder, so
         // these keyCommands take precedence over KeyShortcutsController's (which sits higher in the chain),
         // fixing BOTH the chat composer and the attachment/article editor (both embed this view). Inputs +
         // modifiers match the app-level shortcuts.
         UIKeyCommand(input: "B", modifierFlags: .command, action: #selector(keyToggleBold)),
         UIKeyCommand(input: "I", modifierFlags: .command, action: #selector(keyToggleItalic)),
         UIKeyCommand(input: "U", modifierFlags: .command, action: #selector(keyToggleUnderline)),
         UIKeyCommand(input: "X", modifierFlags: [.command, .shift], action: #selector(keyToggleStrikethrough)),
         UIKeyCommand(input: "M", modifierFlags: [.command, .shift], action: #selector(keyToggleMonospace))]
    }
    @objc private func handleTabKey() {
        // Inside a table cell → cell nav; otherwise a quote-aware Tab (body → author end, author → out).
        if isInsideTable(head) { moveToCell(forward: true); return }
        handleQuoteTabForward()
    }
    @objc private func handleShiftTabKey() { moveToCell(forward: false) }
    @objc private func handleReturnKey(_ command: UIKeyCommand) { performHardwareReturn(command.modifierFlags) }
    /// Ask the host first (send-on-Enter etc.). true (or no host) → insert a newline like a normal Return;
    /// false → the host consumed it (sent the message), so the editor does nothing.
    func performHardwareReturn(_ modifierFlags: UIKeyModifierFlags) {
        if onHardwareReturn?(modifierFlags) ?? true { insertText("\n") }
    }
    @objc private func keyToggleBold() { toggleBold() }
    @objc private func keyToggleItalic() { toggleItalic() }
    @objc private func keyToggleUnderline() { toggleUnderline() }
    @objc private func keyToggleStrikethrough() { toggleStrikethrough() }
    @objc private func keyToggleMonospace() { toggleInlineCode() }

    /// Applies a theme: updates the mapper (text/link colors used on the next reload) and pushes the accent
    /// color to the persistent caret/selection/blockquote views. The caller reloads content afterward so the
    /// boxes rebuild with the themed mapper.
    func applyTheme(_ theme: RichTextEditorTheme) {
        self.mapper.theme = theme
        self.caretView.accentColor = theme.accent
        self.transientCaretView.accentColor = theme.accent
        self.startHandleView.accentColor = theme.accent
        self.endHandleView.accentColor = theme.accent
        self.blockquoteUnderlay.accentColor = theme.accent
        self.pullQuoteUnderlay.accentColor = theme.accent
        self.pullQuoteMarksView.accentColor = theme.accent
    }

    /// Applies quote geometry: rebuilds the mapper's stylesheet with the indent/trailing/spacing fields
    /// (preserving theme/emojiScale/writing-direction — the stylesheet is immutable) and pushes the
    /// render-only bar/radius/fill values to the underlay. The caller reloads afterward (mirrors applyTheme).
    func applyQuoteStyle(_ q: QuoteStyle) {
        self.quoteStyle = q
        var s = self.mapper.styleSheet
        s.quoteIndent = q.leadingInset
        s.quoteTrailingInset = q.trailingInset
        s.quoteSpacingBefore = q.spacingBefore
        s.quoteSpacingAfter = q.spacingAfter
        s.quoteTopInset = q.topInset
        s.quoteBottomInset = q.bottomInset
        self.mapper = AttributedStringMapper(styleSheet: s, emojiScale: self.mapper.emojiScale,
                                             theme: self.mapper.theme,
                                             baseWritingDirection: self.mapper.baseWritingDirection,
                                             formulaRenderer: self.mapper.formulaRenderer)
        self.blockquoteUnderlay.barWidth = q.barWidth
        self.blockquoteUnderlay.cornerRadius = q.cornerRadius
        self.blockquoteUnderlay.fillAlpha = q.fillAlpha
    }

    /// Applies pull-quote geometry: stores the style, pushes corner radius + fill alpha to the barless pill
    /// underlay, and stores the value so the next box build picks up the new padding. The caller reloads
    /// afterward (mirrors applyQuoteStyle — no mapper rebuild needed; geometry is read at box-build time).
    func applyPullQuoteStyle(_ s: PullQuoteStyle) {
        self.pullQuoteStyle = s
        self.pullQuoteUnderlay.cornerRadius = s.cornerRadius
        self.pullQuoteUnderlay.fillAlpha = s.fillAlpha
    }

    /// Applies host media geometry: stores it so the next box build (`setBlocks` / `insertMedia`) uses the
    /// new bleed. Pure geometry — no mapper rebuild (unlike `applyQuoteStyle`). The caller reloads afterward.
    func applyMediaBlockStyle(_ m: MediaBlockStyle) {
        self.mediaBlockStyle = m
    }

    /// Applies host-injected collapse/expand icons: stores them (read at `BlockQuoteBox` creation).
    /// The caller reloads afterward.
    func applyQuoteCollapseIcons(_ icons: RichTextEditorQuoteCollapseIcons?) {
        self.quoteCollapseIcons = icons
    }

    /// Applies tunable text-layout metrics: rebuilds the mapper's stylesheet with the line-height/spacing
    /// fields (preserving the other stylesheet fields + theme/emojiScale/writing-direction — the stylesheet
    /// is immutable). The caller reloads afterward (mirrors `applyQuoteStyle`). A compact host (the chat
    /// composer) sets a tight variant so body/caption paragraphs use natural line height and no spacing.
    func applyTextLayoutMetrics(_ m: TextLayoutMetrics) {
        var s = self.mapper.styleSheet
        s.bodyLineHeightMultiple = m.bodyLineHeightMultiple
        s.bodyParagraphSpacingBefore = m.bodyParagraphSpacingBefore
        s.bodyParagraphSpacingAfter = m.bodyParagraphSpacingAfter
        self.mapper = AttributedStringMapper(styleSheet: s, emojiScale: self.mapper.emojiScale,
                                             theme: self.mapper.theme,
                                             baseWritingDirection: self.mapper.baseWritingDirection,
                                             formulaRenderer: self.mapper.formulaRenderer)
    }

    /// Builds a box per block (paragraph, image, or table). Tables become `TableBlockBox`es whose
    /// cells the canvas reaches via `leafRegions()`.
    func setBlocks(_ blocks: [Block], width: CGFloat) {
        spellResults = [:]   // stale per-block results (keyed by BlockID) must not linger across a document swap
        spellingAlternatives = [:]   // same staleness risk (keyed by BlockID) as spellResults above
        if width > 0 { lastLayoutWidth = width }
        breakUndoCoalescing()   // a full document swap — programmatic set OR an undo/redo restore (the registerUndo closure calls setBlocks) — ends any open typing/deleting run
        tableSelection = nil
        imageSelection = nil   // a full document swap drops any transient structural selection
        spoilerDustViews.values.forEach { $0.view.removeFromSuperview() }
        spoilerDustViews.removeAll()
        spoilerRuns = []
        spoilerRevealHint = nil
        // `width` here is the raw canvas width; the per-box TextKit layout is re-done at the content width
        // (bounds − 2·pageMargin) on the next `layoutSubviews` pass, so this init width is a transient hint.
        boxes = blocks.compactMap {
            makeBox(for: $0, mapper: mapper, quoteStyle: quoteStyle, pullQuoteStyle: pullQuoteStyle,
                    expandImage: quoteCollapseIcons?.expand, collapseImage: quoteCollapseIcons?.collapse,
                    horizontalBleed: mediaBlockStyle.horizontalBleed, width: width)
        }
        recomputeSpans()
        recomputeDocumentHasSpoilers()   // a fresh document may load spoilers, or none (gates syncSpoilers)
        anchor = min(anchor, documentSize); head = min(head, documentSize)
        notifyContentSizeChanged(); setNeedsDisplay()
        lastCheckedCaret = nil   // a fresh document: nothing checked until the caret traverses it
    }

    /// A full-document replacement that NOTIFIES the input system (so the keyboard's shadow document
    /// stays in sync — an unbracketed reload is a top cause of stale/misplaced predictions). Use this
    /// from the public `document` setter; `setBlocks` alone is for internal layout-only rebuilds.
    func reload(_ blocks: [Block], width: CGFloat) {
        finalizeMarkedText()
        textInputDelegate?.textWillChange(self)
        textInputDelegate?.selectionWillChange(self)
        setBlocks(blocks, width: width)
        textInputDelegate?.selectionDidChange(self)
        textInputDelegate?.textDidChange(self)
        refreshEmptyBoxWritingDirections()
    }

    func currentBlocks() -> [Block] { boxes.map { $0.currentBlock() } }

    // MARK: - Viewport helpers

    /// The visible canvas rect: the host scroll view's window onto the content, or `bounds` when there
    /// is no scroll-view host (most unit tests / a non-scroll embed) — in which case the band covers the
    /// whole document and every box realizes (behavioral invariance).
    func viewportRect() -> CGRect {
        if let sv = superview as? UIScrollView { return CGRect(origin: sv.contentOffset, size: sv.bounds.size) }
        return bounds
    }

    /// The visible rect grown by the overscan band (one viewport height each side by default).
    func viewportBand() -> CGRect { overscanRect(for: viewportRect()) }

    /// The blockquote run fills that intersect `band` (off-screen runs are dropped so they allocate no
    /// underlay image view). The no-scroll-host fallback band covers the whole document ⇒ all runs kept.
    func visibleBlockquoteFills(band: CGRect) -> [CGRect] {
        // Flat-quote runs + collapsed-quote / code fills come from blockquoteDecorations(); BlockQuoteBox
        // fills (including nested) come from the recursive blockQuoteFillRects().
        let all = blockquoteDecorations().map { $0.fill } + blockQuoteFillRects()
        return all.filter { $0.intersects(band) }
    }

    /// Reconciles the back-most blockquote underlay to only the on-screen quote runs, and the barless
    /// pull-quote underlay to the content-hugging pill rects for all pull-quote boxes.
    func syncBlockquoteUnderlay() {
        blockquoteUnderlay.sync(runFills: visibleBlockquoteFills(band: viewportBand()))
        pullQuoteUnderlay.sync(runFills: pullQuotePillRects())
    }

    private func overscanRect(for visible: CGRect) -> CGRect {
        let overscan = blockViewOverscan >= 0 ? blockViewOverscan : visible.height
        return visible.insetBy(dx: 0, dy: -overscan)
    }

    /// Indices of the boxes whose drawn extent overlaps `band` — boundary-touching boxes ARE included
    /// (a conservative over-realization that avoids a blank strip at the exact viewport edge). Binary-
    /// searches the y-monotonic box frames (`BlockStack.layout` stacks them top-to-bottom, so `frame.minY`
    /// strictly increases), then widens outward while a neighbor's `blockViewFrame` (which may spill past
    /// `frame`, e.g. a full-bleed image) still intersects. Cost: O(log N + window).
    func blockWindow(forBand band: CGRect) -> [Int] {
        let n = boxes.count
        guard n > 0 else { return [] }
        // first index whose frame is NOT entirely above the band (frame.maxY >= band.minY)
        var lo = 0, hi = n
        while lo < hi { let m = (lo + hi) / 2; if boxes[m].frame.maxY < band.minY { lo = m + 1 } else { hi = m } }
        var first = lo
        // last index that STARTS at or before the band's bottom (frame.minY <= band.maxY)
        lo = 0; hi = n
        while lo < hi { let m = (lo + hi) / 2; if boxes[m].frame.minY <= band.maxY { lo = m + 1 } else { hi = m } }
        var last = lo - 1
        guard first <= last else { return [] }
        // Forward-looking guard: current types (image/table) don't spill vertically past their frame, but
        // a future non-text embed might — so widen on blockViewFrame, not frame.
        while first > 0 && boxes[first - 1].blockViewFrame.intersects(band) { first -= 1 }
        while last < n - 1 && boxes[last + 1].blockViewFrame.intersects(band) { last += 1 }
        return Array(first...last)
    }

    // MARK: - Block view pool

    /// Reconciles the block-view pool against the boxes currently in (or near) the viewport: realize the
    /// boxes whose drawn extent intersects the overscan band, recycle the rest. `blockViews` therefore
    /// holds only the *realized* views. Called from `layoutSubviews` (via `syncBlockViews()`) and the
    /// host's `scrollViewDidScroll` (via `viewportDidChange()`).
    /// Returns `true` when a fresh `TableBackingView` was created this call (used by `viewportDidChange`
    /// to decide whether to re-host cell emoji into the new content view).
    @discardableResult
    func reconcileBlockViews(visibleRect: CGRect) -> Bool {
        var createdFreshTable = false
        let window = blockWindow(forBand: overscanRect(for: visibleRect))
        var wantedIDs = Set<BlockID>()
        for i in window {
            let box = boxes[i]
            guard box.rendersAsBlockView else { continue }
            wantedIDs.insert(box.id)
            if let view = blockViews[box.id] {
                bindRealizedView(view, to: box, fresh: false)          // stayed realized
            } else {
                let view: BlockBackingView
                if box is TableBlockBox {
                    let t = TableBackingView(); t.canvas = self
                    t.pendingOffsetRestore = true                       // restore saved H-scroll on first layout
                    view = t
                    createdFreshTable = true
                } else {
                    view = dequeueRecycledView()                        // reuse (or create) a plain backing view
                }
                blockViews[box.id] = view
                insertSubview(view, aboveSubview: blockquoteUnderlay)    // above the back-most quote fills, below the overlays
                bindRealizedView(view, to: box, fresh: true)
            }
        }
        for (id, view) in blockViews where !wantedIDs.contains(id) {
            view.removeFromSuperview()
            blockViews[id] = nil
            if !(view is TableBackingView) {
                view.box = nil                                          // drop the strong ref to the old box
                view.lastRenderedSignature = nil
                if recycleQueue.count < recycleQueueCap { recycleQueue.append(view) }
            }
            // A TableBackingView is released; its `contentOffsetX` already lives on the box.
        }
        return createdFreshTable
    }

    /// `syncBlockViews()` keeps its old call sites (`layoutSubviews`) but is now viewport-aware.
    func syncBlockViews() { reconcileBlockViews(visibleRect: viewportRect()) }

    /// Called when only the VIEWPORT moved (the host scrolled) — frames are unchanged, so no relayout:
    /// re-realize block views + emoji against the moved viewport, re-cull the blockquote underlay, and
    /// re-home the caret/handles (a caret hosted in a table that was just realized must re-attach).
    func viewportDidChange() {
        let realizedFreshTable = reconcileBlockViews(visibleRect: viewportRect())
        syncBlockquoteUnderlay()
        // A freshly re-realized table has a brand-new (empty) content view; re-host emoji so its cell
        // emoji migrate back into it. Otherwise the cheap hide/show cull suffices (frames unchanged).
        if realizedFreshTable { syncEmojiViews(); syncChecklistMarkerViews(); syncMediaItemViews() } else { cullEmojiViews(); cullMediaItemViews() }
        refreshSelectionUI()
        scrollCaretIntoViewIfNeeded()
    }

    private func dequeueRecycledView() -> BlockBackingView {
        if let v = recycleQueue.popLast() { return v }
        let v = BlockBackingView(); v.canvas = self; return v
    }

    /// Binds (or re-binds) a realized view to its box: frame, table H-scroll sync, and the repaint gate.
    /// `fresh` = the view was just created/recycled (its bitmap is stale ⇒ force a repaint).
    private func bindRealizedView(_ view: BlockBackingView, to box: CanvasBlock, fresh: Bool) {
        // A structural edit (split/merge) keeps a surviving block's BlockID but swaps its BlockBox for a
        // brand-new instance whose fresh BlockLayout resets `renderVersion` to 0. `renderSignature` encodes
        // that per-instance counter, so it is MEANINGLESS to compare across a box-instance replacement —
        // a same-height/same-style upper half can collide with the old signature and wrongly skip the
        // repaint, leaving the pre-split full-text bitmap. Detect the instance swap and force a repaint;
        // the signature gate below still covers the common same-instance cases (scroll, typing in place).
        let boxInstanceChanged = view.box !== box
        view.box = box
        view.frame = box.blockViewFrame                                  // image: full drawn extent; table: visible window
        if let t = box as? TableBlockBox, let tv = view as? TableBackingView, !fresh {
            t.contentOffsetX = max(0, tv.scroll.contentOffset.x)         // a stays-realized table: sync view→box
        }
        view.setNeedsLayout()
        if let p = box as? BlockBox {
            let sig = p.renderSignature
            if fresh || boxInstanceChanged || view.lastRenderedSignature != sig {   // recycled OR rebound OR content changed
                view.lastRenderedSignature = sig
                view.setNeedsDisplay()
            }
        } else {
            view.setNeedsDisplay()   // image/table: no renderSignature gate, so always repaint (they're few)
        }
    }

    var realizedBlockViewCountForTesting: Int { blockViews.count }
    func isBlockViewRealizedForTesting(_ id: BlockID) -> Bool { blockViews[id] != nil }
    var recycleQueueDepthForTesting: Int { recycleQueue.count }

    /// Called by a `TableBackingView` whenever its inner scroll view moves: keep the box's `contentOffsetX`
    /// in lock-step (canvas-space queries fold it in, Task 3) and repaint the offset-dependent chrome/caret.
    func tableDidScroll(_ view: TableBackingView) {
        guard let t = view.box as? TableBlockBox else { return }
        t.contentOffsetX = max(0, view.scroll.contentOffset.x)
        refreshSelectionUI()
        blockChromeOverlay.setNeedsDisplay()
    }

    func setParagraphs(_ paragraphs: [ParagraphBlock], width: CGFloat) {
        setBlocks(paragraphs.map { .paragraph($0) }, width: width)
    }

    func currentParagraphs() -> [ParagraphBlock] {
        boxes.compactMap { ($0 as? BlockBox)?.currentParagraph() }
    }

    /// Assigns each box its `nodeStart` (= prior tokens + 1) and accumulates `documentSize` from each
    /// box's `nodeSize` (paragraph: textLength+2; image: textLength+5). Matches `RichTextEditorCore`
    /// row-major token addressing.
    func recomputeSpans() {
        documentSize = root.recompute(baseOffset: 0)
        for case let t as TableBlockBox in boxes { t.recompute() }
        for case let bq as BlockQuoteBox in boxes { bq.recompute() }
    }

    /// The box whose text contains `pos` (inclusive of the trailing caret slot), or nil at a
    /// structural boundary between blocks.
    func box(containingGlobal pos: Int) -> (box: CanvasBlock, local: Int)? {
        for box in boxes where pos >= box.textStart && pos <= box.textStart + box.textLength {
            return (box, pos - box.textStart)
        }
        return nil
    }

    /// All editable leaf regions in document order (recurses into tables). v1: rebuilt per call; cache
    /// if profiling shows it matters.
    func allLeafRegions() -> [LeafTextRegion] { root.leafRegions() }

    /// The leaf region containing `pos` (inclusive of the trailing caret slot), with the local offset.
    func leafRegion(containingGlobal pos: Int) -> (region: LeafTextRegion, local: Int)? {
        for r in allLeafRegions() where pos >= r.globalStart && pos <= r.globalStart + r.length {
            return (r, pos - r.globalStart)
        }
        return nil
    }

    func boxIndex(of box: CanvasBlock) -> Int? { boxes.firstIndex { $0 === box } }

    /// Public-within-module accessor for the façade.
    var documentSizeValue: Int { documentSize }

    /// The left/right padding from the canvas edge to the text: the built-in `pageMargin` plus the
    /// configurable `contentMargins` on that side. The text content width is the canvas width minus both.
    var contentLeftPad: CGFloat { self.pageMargin + contentMargins.left }
    var contentRightPad: CGFloat { self.pageMargin + contentMargins.right }
    func contentWidth(forWidth width: CGFloat) -> CGFloat { max(width - contentLeftPad - contentRightPad, 1) }

    /// Re-flows boxes to a new width if it changed, so the caller can read an accurate
    /// `intrinsicContentSize` BEFORE it sizes the canvas frame. Called from the façade's `performLayout`,
    /// which lays the canvas out explicitly (`layoutContent()`) right after — so this does not schedule
    /// layout itself.
    func setParagraphsWidthIfNeeded(_ width: CGFloat) {
        let content = contentWidth(forWidth: width)
        guard let first = boxes.first, abs(first.frame.width - content) > 0.5 || first.frame.width == 0 else { return }
        for box in boxes { box.setWidth(content) }
        recomputeSpans()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Skip a zero-width UIKit layout pass before the canvas is framed: laying out at width 0 builds the
        // media/overlay views at a 0×0 rect (and binds their fetch), redone the instant the real frame lands.
        // The parent (`RichTextEditorView.performLayout`) sets a non-zero canvas frame before calling
        // `layoutContent()` directly, so the real (framed) layout path is unaffected.
        if bounds.width > 0 {
            layoutContent()
        }
    }

    /// Lays out the document content + overlays against `bounds`. The parent
    /// (`RichTextEditorView.performLayout`) calls this DIRECTLY so layout never depends on the UIKit
    /// `needsLayout` flag — the editor's convention is that the parent drives layout explicitly and a view
    /// never `setNeedsLayout()`s itself; it only notifies the parent (`onContentSizeChange`). Also invoked
    /// by `layoutSubviews` for any UIKit-driven pass. Idempotent.
    func layoutContent() {
        if bounds.width > 0 { lastLayoutWidth = bounds.width }
        root.verticalInsetBase = self.blockVerticalInset
        _ = root.layout(origin: CGPoint(x: contentLeftPad, y: contentMargins.top),
                        width: contentWidth(forWidth: bounds.width))
        for case let t as TableBlockBox in boxes { t.recompute() }   // cell frames depend on the table frame
        for case let bq as BlockQuoteBox in boxes { bq.recompute() }   // child frames depend on the quote frame
        stampListMarkers()
        syncBlockViews()
        blockquoteUnderlay.frame = bounds
        sendSubviewToBack(blockquoteUnderlay)
        pullQuoteUnderlay.frame = bounds
        sendSubviewToBack(pullQuoteUnderlay)   // goes below blockquoteUnderlay; block views (inserted aboveSubview: blockquoteUnderlay) are above both
        syncBlockquoteUnderlay()
        pullQuoteMarksView.frame = bounds
        pullQuoteMarksView.sync(marks: pullQuoteMarkRects())
        emojiOverlay.frame = bounds
        syncEmojiViews()
        syncChecklistMarkerViews()
        mediaOverlay.frame = bounds
        syncMediaItemViews()
        spoilerOverlay.frame = bounds
        syncSpoilers()
        selectionHighlight.frame = bounds
        bringSubviewToFront(selectionHighlight)   // above emoji
        // Extend the chrome overlay LEFT of x=0 so the row grip — which sits at a NEGATIVE x when the page
        // margin is zero (the composer draws it into the field's left padding) — isn't clipped by the overlay's
        // own draw context. A view's `draw(_:)` is ALWAYS bounded by its frame (the graphics context is the
        // frame), independent of `clipsToBounds`, so widening the frame is the only way to paint there. The
        // matching `bounds.origin` shift keeps it drawing in canvas coordinates (see BlockChromeOverlay).
        let chromeLeftExtension: CGFloat = 40
        blockChromeOverlay.frame = CGRect(x: -chromeLeftExtension, y: 0, width: bounds.width + chromeLeftExtension, height: bounds.height)
        blockChromeOverlay.bounds.origin = CGPoint(x: -chromeLeftExtension, y: 0)
        bringSubviewToFront(blockChromeOverlay)    // chrome stays above the selection wash
        blockChromeOverlay.setNeedsDisplay()
        updateCaretView()              // frames/geometry may have changed (re-flow, table relayout); idempotent.
        updateSelectionHandleViews()   // reposition the own-drawn handles too
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopDragAutoScroll()     // don't let a CADisplayLink retain a torn-down view
            cancelFloatingCursor()   // same: tear down the floating-cursor display link on window removal
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: contentMargins.top + boxes.reduce(0) { $0 + $1.height } + contentMargins.bottom)
    }

    /// Stateless content height the document would have at canvas `width` — the measure analogue of
    /// `intrinsicContentSize.height` (same `contentMargins` + content-width derivation). Never mutates
    /// the live layout (no box `setWidth`, no frame/overlay/caret change).
    ///
    /// FRAMING DEPENDENCY (future enhancement): this reads each box's `topInset`/`bottomInset`
    /// (`BlockStack.measuredHeight` → `BlockBox.measuredHeight`), which are set only by a LAYOUT pass
    /// (`BlockStack.layout` via `facingInset`, run from `layoutContent`). So an editor that has NOT been
    /// framed/laid-out yet measures too tall — each box keeps its default `BlockBox.defaultVerticalInset`
    /// (8pt) rather than the host's configured inset (the composer's 0). Callers therefore measure a FRAMED
    /// editor (the live composer field is on-screen; the `measuredContentHeight` static probe sets a non-zero
    /// `probe.frame` before seeding). The robust fix (deferred) is to make the measure framing-independent —
    /// compute the facing insets here (mirroring `layout`) instead of reading the stored, layout-set values.
    func measuredContentHeight(forWidth width: CGFloat, contentMargins explicitMargins: UIEdgeInsets? = nil) -> CGFloat {
        // The measure must be PURE: a host sizing its field by this value (the chat composer) may call it
        // BEFORE the matching `update(...)` has pushed the real `contentMargins` onto the live canvas (a draft
        // applied before the editor is sized). Reading live `self.contentMargins` then yields a too-small height
        // (the right-inset reservation is missing → text measured at the full width → fewer wrapped lines), and
        // the field visibly grows on the next pass. So callers that know the intended margins pass them in;
        // others keep the live value.
        let margins = explicitMargins ?? self.contentMargins
        let contentW = max(width - (self.pageMargin + margins.left) - (self.pageMargin + margins.right), 1)
        return margins.top + root.measuredHeight(forWidth: contentW) + margins.bottom
    }

    /// Notifies the host that the content height may have changed (e.g. after an edit), so it re-runs
    /// layout. The editor convention: a view never `setNeedsLayout()`s itself for a content change — it
    /// notifies its parent, which drives layout explicitly. `intrinsicContentSize` is a pure computed
    /// property, so there is nothing to invalidate; this only fires the callback.
    func notifyContentSizeChanged() { onContentSizeChange?() }

    /// Selection/caret changes call `setNeedsDisplay()` without a layout pass; propagate the repaint to
    /// the selection overlays and the chrome overlay — and to TABLE views only (their cell wash is
    /// selection-dependent). Paragraph/image views are NOT cascaded: their pixels don't depend on the
    /// selection, so they repaint only via the signature gate in `syncBlockViews`.
    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        for v in blockViews.values where v is TableBackingView { v.setNeedsDisplay() }
        selectionHighlight.setNeedsDisplay()
        blockChromeOverlay.setNeedsDisplay()
    }

    // No `draw(_:)` override: the canvas paints nothing of its own, so it allocates no document-sized
    // backing store (the surface-size lever). Every visual is a bounded subview — block content via each
    // `BlockBackingView`, the blockquote fills via the back-most `blockquoteUnderlay`, the selection wash
    // via `selectionHighlight` / each table's `CellSelectionView`, table chrome via `blockChromeOverlay`,
    // and the caret/handles via their own-drawn views.

    /// Draws the selection highlight for all NON-TABLE regions (body + image captions) plus the image-atom
    /// washes, in canvas coordinates. Called by the `selectionHighlight` overlay so it renders ON TOP of
    /// the text and the emoji subviews. Table-cell regions are excluded (their highlight rides each table's
    /// own content-view overlay so it tracks horizontal overscroll).
    func drawNonTableSelectionHighlight(in ctx: CGContext) {
        self.mapper.theme.accent.withAlphaComponent(0.30).setFill()
        if selFrom != selTo {
            for r in selectionHighlightRects(globalFrom: selFrom, globalTo: selTo,
                                             regionFilter: { !self.isRegionInTable($0) }) {
                ctx.fill(r)
            }
        }
        // Image-atom wash for a selected (range-covered or tap-selected) image — moved here from the
        // image's BlockBackingView so it sits above any caption emoji and reads consistently.
        for case let img as MediaBlockBox in boxes {
            if let rect = imageSelectionTintRect(for: img) { ctx.fill(rect) }
        }
    }

    /// True if `region` belongs to a table (its global start falls in a `TableBlockBox`'s node span). Such
    /// regions' highlight is drawn by the table's content-view overlay, not the canvas overlay.
    func isRegionInTable(_ region: LeafTextRegion) -> Bool {
        boxes.contains { ($0 is TableBlockBox)
            && region.globalStart >= $0.nodeStart
            && region.globalStart < $0.nodeStart + $0.nodeSize }
    }

    /// Rect-union: clamp the global range to each leaf region, enumerate `.selection` segments,
    /// offset into canvas coordinates. The cross-block continuous highlight.
    /// - Parameter regionFilter: Optional predicate; only regions that pass are included (the canvas
    ///   selection overlay passes `{ !isRegionInTable($0) }` so table-cell regions are drawn by their
    ///   own content-view overlay). Defaults to `{ _ in true }` so existing callers are unaffected.
    func selectionRects(globalFrom: Int, globalTo: Int,
                        regionFilter: (LeafTextRegion) -> Bool = { _ in true }) -> [CGRect] {
        var rects: [CGRect] = []
        for r in allLeafRegions() where regionFilter(r) {
            let lo = max(globalFrom, r.globalStart), hi = min(globalTo, r.globalStart + r.length)
            guard lo < hi else { continue }
            let offX = tableContentOffsetX(forGlobal: r.globalStart)
            for seg in r.layout.selectionRects(start: lo - r.globalStart, end: hi - r.globalStart) {
                rects.append(seg.offsetBy(dx: r.canvasOrigin.x - offX, dy: r.canvasOrigin.y))
            }
        }
        return rects
    }

    /// Selection rects for DRAWING the highlight wash, styled like UITextView (distinct from the
    /// glyph-hugging `selectionRects`): a line covered in full fills to the text container's trailing edge,
    /// and an empty line spanned by the selection gets a full-width rect. Used only by the highlight draw
    /// path — the OS witness / edit-menu / spoiler / marked-text geometry keep the glyph-hugging rects.
    func selectionHighlightRects(globalFrom: Int, globalTo: Int,
                                 regionFilter: (LeafTextRegion) -> Bool = { _ in true }) -> [CGRect] {
        var rects: [CGRect] = []
        for r in allLeafRegions() where regionFilter(r) {
            let regionEnd = r.globalStart + r.length
            let offX = tableContentOffsetX(forGlobal: r.globalStart)
            let lo = max(globalFrom, r.globalStart), hi = min(globalTo, regionEnd)
            if lo < hi {
                // The selection continuing past this region's last character means its trailing newline (the
                // next block) is selected → the final covered line fills to the edge, like UITextView.
                let continuesPast = globalTo > regionEnd
                for seg in r.layout.selectionFillRects(start: lo - r.globalStart, end: hi - r.globalStart,
                                                       fillTrailingLine: continuesPast,
                                                       isRTL: resolvedDirection(forGlobal: lo) == .rightToLeft) {
                    rects.append(seg.offsetBy(dx: r.canvasOrigin.x - offX, dy: r.canvasOrigin.y))
                }
            } else if r.length == 0, globalFrom <= r.globalStart, r.globalStart < globalTo {
                // An empty line spanned by the selection → a full-width highlight (the empty paragraph has no
                // glyphs, so `selectionFillRects` yields nothing; synthesize the line-height-tall full row).
                let h = r.emptyLineHeight > 0 ? r.emptyLineHeight : r.layout.caretRect(atOffset: 0).height
                rects.append(CGRect(x: r.canvasOrigin.x - offX, y: r.canvasOrigin.y,
                                    width: r.layout.containerWidth, height: h))
            }
        }
        return rects
    }

    /// Maps a point in canvas coordinates to the closest global text position.
    func closestGlobalPosition(to point: CGPoint) -> Int { root.closestPosition(toCanvasPoint: point) }

    /// The `TableBlockBox` whose node span (incl. structural token slots) contains `pos`, if any — used to
    /// fold in horizontal scroll. Wider than `tableBox(containing:)` in Navigation (which matches cell text only).
    func tableBox(containingGlobal pos: Int) -> TableBlockBox? {
        boxes.first { ($0 as? TableBlockBox).map { pos >= $0.nodeStart && pos < $0.nodeStart + $0.nodeSize } ?? false } as? TableBlockBox
    }

    /// The horizontal scroll offset of the table containing `pos` (0 if none) — subtract it to turn an
    /// unscrolled-canvas rect into a VISIBLE canvas rect.
    func tableContentOffsetX(forGlobal pos: Int) -> CGFloat { tableBox(containingGlobal: pos)?.contentOffsetX ?? 0 }

    /// True if `pos` is the gap before a media atom box's `nodeStart` — a renderable caret slot.
    func isGapPosition(_ pos: Int) -> Bool {
        boxes.contains { $0 is MediaBlockBox && $0.nodeStart == pos }
    }

    /// The media box whose gap-before-atom is at `pos`, if any.
    func mediaBox(atGap pos: Int) -> MediaBlockBox? {
        boxes.first { ($0 as? MediaBlockBox)?.nodeStart == pos } as? MediaBlockBox
    }

    /// The COLLAPSED block-quote box whose leading gap is at `pos` (top-level), if any. The folded quote is a
    /// caption-less atom holding no editable text, so a caret can focus its gap but typing there must open a
    /// body paragraph before it — mirroring `mediaBox(atGap:)`.
    func collapsedBlockQuoteBox(atGap pos: Int) -> BlockQuoteBox? {
        boxes.first { ($0 as? BlockQuoteBox).map { $0.collapsed && $0.nodeStart == pos } ?? false } as? BlockQuoteBox
    }

    /// If the caret (`head`) is inside a horizontally-scrollable table, scroll its cell into view.
    /// Non-animated (fires during typing/nav); the scroll callback syncs `contentOffsetX` + repaints.
    func scrollCaretIntoViewIfNeeded() {
        // Note: an image-gap caret inside a cell isn't found by cellLocation (no UI path inserts one today),
        // so this simply no-ops for that case.
        guard let t = tableBox(containingGlobal: head),
              let tv = blockViews[t.id] as? TableBackingView,
              let loc = t.cellLocation(containing: head),
              let cellRect = t.cellRect(row: loc.row, column: loc.column) else { return }
        guard t.gridWidth > tv.bounds.width else { return }   // not scrollable → cheap early exit, no layout flush
        tv.layoutIfNeeded()                                   // ensure scroll.frame/contentSize are current
        let x = cellRect.minX - t.frame.minX                  // cell x in the scroll view's content space
        let target = CGRect(x: x, y: 0, width: cellRect.width, height: 1)
        tv.scroll.scrollRectToVisible(target, animated: false)
    }

    /// While dragging a selection handle, auto-scroll as the touch nears an edge: **vertically** against the
    /// host document scroll view whenever the touch enters its top/bottom band (the common case — selecting
    /// past the visible text), and/or **horizontally** within a scrollable table when the dragged head is in
    /// that table and the touch nears its left/right edge. A single `CADisplayLink` applies both nudges per
    /// tick and re-extends the head against the updated geometry. (`point` is in canvas / content coords.)
    func updateDragAutoScroll(point: CGPoint, headInTable: Bool) {
        dragAutoScrollPoint = point

        // Vertical: scroll the host document when the touch is in the viewport's top/bottom band. Reuses the
        // floating-cursor curve (60pt band, 14pt max step) so the two gestures auto-scroll identically.
        var vy: CGFloat = 0
        if let sv = superview as? UIScrollView {
            vy = floatingAutoScrollStep(forViewportY: point.y - sv.contentOffset.y,
                                        viewportHeight: sv.bounds.height, band: 60)
        }
        dragAutoScrollVelocityY = vy

        // Horizontal: nudge a scrollable table the head is in when the touch nears its left/right edge.
        var vx: CGFloat = 0
        if headInTable, let t = tableBox(containingGlobal: head),
           let tv = blockViews[t.id] as? TableBackingView, t.gridWidth > tv.bounds.width {
            let edge: CGFloat = 36, step: CGFloat = 12
            let left = t.frame.minX, right = t.frame.minX + tv.bounds.width
            if point.x < left + edge { vx = -step } else if point.x > right - edge { vx = step }
            dragAutoScrollTable = (vx != 0) ? t : nil
        } else {
            dragAutoScrollTable = nil
        }
        dragAutoScrollVelocityX = vx

        if vy == 0 && vx == 0 { stopDragAutoScroll(); return }
        if dragAutoScrollLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(dragAutoScrollTick))
            link.add(to: .main, forMode: .common)
            dragAutoScrollLink = link
        }
    }

    func stopDragAutoScroll() {
        dragAutoScrollLink?.invalidate(); dragAutoScrollLink = nil
        dragAutoScrollTable = nil; dragAutoScrollVelocityX = 0; dragAutoScrollVelocityY = 0
        dragAutoScrollPoint = .zero
    }

    @objc func dragAutoScrollTick() {
        var moved = false
        // Vertical document scroll: advance the host offset and keep the touch point under the finger as the
        // content scrolls (so the head re-extends to follow), exactly like the floating-cursor auto-scroll.
        if dragAutoScrollVelocityY != 0, let sv = superview as? UIScrollView {
            let maxY = max(sv.contentSize.height - sv.bounds.height, 0)
            let newY = min(max(sv.contentOffset.y + dragAutoScrollVelocityY, 0), maxY)
            if newY != sv.contentOffset.y {
                let delta = newY - sv.contentOffset.y
                sv.contentOffset.y = newY        // fires the façade's scrollViewDidScroll → viewportDidChange
                dragAutoScrollPoint.y += delta   // track the same screen point as content scrolls under it
                moved = true
            }
        }
        // Horizontal table scroll: advance the table's internal offset (the canvas-space point is unaffected).
        if dragAutoScrollVelocityX != 0, let t = dragAutoScrollTable, let tv = blockViews[t.id] as? TableBackingView {
            let maxX = max(tv.scroll.contentSize.width - tv.bounds.width, 0)
            let newX = min(max(tv.scroll.contentOffset.x + dragAutoScrollVelocityX, 0), maxX)
            if newX != tv.scroll.contentOffset.x {
                tv.scroll.contentOffset.x = newX   // triggers tableDidScroll → syncs contentOffsetX
                moved = true
            }
        }
        guard moved else { return }   // both axes already clamped at their edge
        // Re-extend the endpoint being dragged to the content now under the touch: the anchor when the start
        // handle is dragged, else the head (the default — also the table-only / direct-call path). The tick
        // owns the scroll position, so suppress `setSelectionHead`'s scrollCaretIntoViewIfNeeded (it would
        // fight `newX`); `setSelectionAnchor` never scrolls, so it needs no suppression.
        let target = selectionDragPosition(forTouch: dragAutoScrollPoint)   // touch + captured grab offset
        if draggingEndpoint == .anchor { setSelectionAnchor(global: target) }
        else { setSelectionHead(global: target, scrollIntoView: false) }
    }

    /// Sets a collapsed caret (clears the drag anchor).
    func setCaret(global pos: Int) {
        setCaret(global: pos, reportSelectionChange: true)
    }

    /// Sets a collapsed caret (clears the drag anchor). `reportSelectionChange` gates the host-facing selection
    /// report (`onSelectionChange`): pass `false` for the per-frame moves of an interactive caret drag (the
    /// long-press magnifier loupe) so the host is told ONCE at the drag's final position instead of on every
    /// frame — the same "report once at the end" model the floating cursor (spacebar-trackpad) uses. The
    /// own-drawn visuals + table-cell scroll-follow still update every call. The OS input-delegate bracket
    /// obeys `coalescingSelectionNotifications` (like `setSelectionHead`): during a coalesced caret drag it is
    /// skipped per frame — otherwise the keyboard's autocorrect/candidate bar recomputes and visibly JUMPS on
    /// every move — and `endCoalescedSelectionDrag` fires exactly one bracket for the final caret at the end.
    func setCaret(global pos: Int, reportSelectionChange: Bool) {
        var target = pos
        if let g = finalizeMarkedText() {            // a dismissed prediction shifts later positions left
            if pos >= g.to { target = pos - (g.to - g.from) }
            else if pos > g.from { target = g.from }
        }
        target = clampGlobal(target)
        clearStructuralSelections()
        dismissEditMenuForSelectionOrTextChange()   // the caret moved → close any open menu (native UITextView)
        if !coalescingSelectionNotifications { textInputDelegate?.selectionWillChange(self) }
        anchor = target; head = target
        if !coalescingSelectionNotifications { textInputDelegate?.selectionDidChange(self) }
        setNeedsDisplay(); refreshSelectionUI()
        scrollCaretIntoViewIfNeeded()
        guard reportSelectionChange else { return }
        onSelectionChange?()   // tap is harmless (caret already visible → no-op); covers non-tap movers —
                               // Backspace-at-cell-start / Tab cell-nav — that can land the caret off-screen
    }

    /// Moves the selection head, keeping the anchor (drag-to-select). During an interactive handle drag the
    /// input-delegate bracket is coalesced to the gesture's end (see `coalescingSelectionNotifications`).
    func setSelectionHead(global pos: Int, scrollIntoView: Bool = true) {
        finalizeMarkedText()
        clearStructuralSelections()
        dismissEditMenuForSelectionOrTextChange()
        if !coalescingSelectionNotifications { textInputDelegate?.selectionWillChange(self) }
        head = pos
        if !coalescingSelectionNotifications { textInputDelegate?.selectionDidChange(self) }
        setNeedsDisplay(); refreshSelectionUI()
        if scrollIntoView { scrollCaretIntoViewIfNeeded() }
    }

    /// Moves the selection anchor (keeps the head), bracketing the input-delegate change like setSelectionHead
    /// (also coalesced during an interactive handle drag).
    func setSelectionAnchor(global pos: Int) {
        finalizeMarkedText()
        clearStructuralSelections()
        dismissEditMenuForSelectionOrTextChange()
        if !coalescingSelectionNotifications { textInputDelegate?.selectionWillChange(self) }
        anchor = pos
        if !coalescingSelectionNotifications { textInputDelegate?.selectionDidChange(self) }
        setNeedsDisplay(); refreshSelectionUI()
    }

    /// Begins coalescing input-delegate selection notifications for an interactive selection-handle drag.
    /// While active, `setSelectionHead`/`setSelectionAnchor` update the selection + visuals every frame but
    /// skip the `inputDelegate` bracket; `endCoalescedSelectionDrag` fires exactly one bracket at the end.
    func beginCoalescedSelectionDrag() { coalescingSelectionNotifications = true }

    /// Ends a coalesced drag. If notifications were being coalesced, fire ONE input-delegate bracket so the OS
    /// re-syncs (and recomputes autocorrect/candidates) against the final selection — the `selectedTextRange`
    /// getter was live throughout, but the keyboard only refreshes on a bracket. No-op when no drag coalesced.
    func endCoalescedSelectionDrag() {
        guard coalescingSelectionNotifications else { return }
        coalescingSelectionNotifications = false
        textInputDelegate?.selectionWillChange(self)
        textInputDelegate?.selectionDidChange(self)
        nativeCheckOnSelectionChange()   // run once at the final caret of a coalesced drag
    }

    func refreshSelectionUI() {
        // The canvas owns every selection visual (caret, wash, handles); there is no
        // `UITextSelectionDisplayInteraction` to notify (see `installSelectionInteractions`).
        updateCaretView()
        updateSelectionHandleViews()
        syncSpoilers()
        nativeCheckOnSelectionChange()   // selection-driven native spell/grammar check (native-parity)
    }

    /// Positions the two own-drawn selection-handle views at the ranged selection's endpoints — each hosted
    /// in the table's scrolling content view for a cell endpoint, else the canvas — ON TOP of the wash and
    /// riding the right scroll. Hidden for a collapsed / structural / non-renderable selection. Mirrors
    /// `updateCaretView`; idempotent, so it's safe from `refreshSelectionUI` and `layoutSubviews`.
    func updateSelectionHandleViews() {
        guard isFirstResponder, selFrom != selTo, tableSelection == nil, imageSelection == nil else {
            hideHandle(startHandleView); hideHandle(endHandleView); return
        }
        positionHandle(startHandleView, atGlobal: selFrom)
        positionHandle(endHandleView, atGlobal: selTo)
    }

    private func positionHandle(_ handle: SelectionHandleView, atGlobal pos: Int) {
        guard let region = leafRegion(containingGlobal: pos) else { return hideHandle(handle) }
        let unscrolled = region.region.caretRect(atLocal: region.local)
            .offsetBy(dx: region.region.canvasOrigin.x + region.region.emptyLineLeadingIndent,
                      dy: region.region.canvasOrigin.y)
        if let table = tableBox(containingGlobal: pos),
           let tv = blockViews[table.id] as? TableBackingView,
           region.region.globalStart >= table.nodeStart,
           region.region.globalStart < table.nodeStart + table.nodeSize {
            // Cell endpoint → host in the table's content view (content-local = unscrolled − frame.origin),
            // so it rides the horizontal scroll like the caret.
            let contentCaret = unscrolled.offsetBy(dx: -table.frame.minX, dy: -table.frame.minY)
            tv.hostHandle(handle, at: handle.boundingFrame(forCaret: contentCaret))
            handle.setCaretLocalRect(handle.caretLocalRect(forCaret: contentCaret))   // interactive hit area
        } else {
            if handle.superview !== self { addSubview(handle) }
            bringSubviewToFront(handle)   // above the wash (and chrome — they're never co-visible with a text range)
            handle.frame = handle.boundingFrame(forCaret: unscrolled)
            handle.setCaretLocalRect(handle.caretLocalRect(forCaret: unscrolled))   // interactive hit area
        }
        handle.isHidden = false
    }

    private func hideHandle(_ handle: SelectionHandleView) {
        handle.isHidden = true
        if handle.superview !== self { addSubview(handle) }   // never leave it parked in a torn-down table
    }

    /// Positions (and shows/hides) the app's own blinking caret. Idempotent and cheap: re-running it for the
    /// same caret (a scroll tick / relayout) does NOT restart the blink (only a real container/frame change
    /// does), so it's safe to call from `refreshSelectionUI` (every selection change) and `layoutSubviews`.
    ///
    /// The caret shows iff we're first responder, the selection is COLLAPSED (`selFrom == selTo`), there's
    /// no structural table selection, and `head` is renderable. When the caret is inside a horizontally-
    /// scrollable table CELL it's hosted in that table's scrolling content view (so it rides the scroll);
    /// otherwise (paragraph / image-gap) it's a subview of the canvas.
    func updateCaretView() {
        // During a floating-cursor (spacebar-trackpad) gesture the steady caret becomes the DIMMED
        // "landing" indicator at the SNAPPED position (where the caret lands on release); the bright
        // gliding shadow (transientCaretView) is positioned separately by the floating handlers.
        if floatingCursorActive {
            guard isFirstResponder, let placement = caretHostPlacement(forGlobal: head) else { return hideCaretView() }
            hostOverlay(caretView, at: placement)
            caretView.freezeSolid()
            caretView.alpha = 0.4
            lastCaretContainer = placement.container
            lastCaretFrame = placement.frame
            return
        }
        // During a long-press magnifier (loupe) drag, draw the spacebar-style two-cursor visual: OUR own accent
        // caret is the "landing" at the snapped position, while the desaturated `transientCaretView` glides at the
        // finger (the borrowed system cursor is near-invisible — grow anchor only). Solid, no blink.
        if loupeDragActive {
            guard isFirstResponder, let placement = caretHostPlacement(forGlobal: head) else { return hideCaretView() }
            hostOverlay(caretView, at: placement)
            caretView.alpha = 1
            caretView.freezeSolid()   // NOTE: sets isHidden=false — so the visibility rule below must run AFTER it.
            // Show the gray "shadow" (the snapped real caret) only once the accent glider (at the finger,
            // `loupeFingerX`) has diverged from it by >= `loupeShadowMinSeparation`; coincident, it's redundant
            // clutter. Applied HERE (the sole owner of `caretView` during a loupe drag) so a re-run — the loupe
            // magnifier forces layout passes that call this again — re-asserts it instead of leaving it visible.
            // `nil` finger x (the drag's terminal refresh) → shown, so the final caret is never left hidden.
            if let fx = loupeFingerX {
                let accentX = (placement.container === self) ? fx : convert(CGPoint(x: fx, y: 0), to: placement.container).x
                caretView.isHidden = !loupeShadowShouldShow(accentX: accentX, snappedX: placement.frame.midX)
            } else {
                caretView.isHidden = false
            }
            lastCaretContainer = placement.container
            lastCaretFrame = placement.frame
            return
        }
        caretView.alpha = 1   // restore full opacity after a gesture

        // Should it show?
        guard isFirstResponder, selFrom == selTo, tableSelection == nil, imageSelection == nil else { return hideCaretView() }

        guard let placement = caretHostPlacement(forGlobal: head) else { return hideCaretView() }
        hostOverlay(caretView, at: placement)

        caretView.isHidden = false
        // Reset the blink ONLY when the caret actually moved (container or frame changed). A no-op refresh
        // (scroll tick / relayout at the same spot) keeps the existing blink running.
        let changed = placement.container !== lastCaretContainer || !placement.frame.equalTo(lastCaretFrame)
        if changed { caretView.resetBlink() } else { caretView.startBlink() }
        lastCaretContainer = placement.container
        lastCaretFrame = placement.frame
    }

    /// The (container, frame) where a caret-like overlay for global `pos` should be hosted, or `nil` if
    /// `pos` is not a renderable caret slot. For an in-cell position the container is the owning
    /// `TableBackingView` (frame in its content-local space); otherwise the canvas (frame in canvas
    /// space). Extracted from `updateCaretView` so the steady caret and the floating transient caret host
    /// identically — including riding a table's horizontal scroll.
    func caretHostPlacement(forGlobal pos: Int) -> (container: UIView, frame: CGRect)? {
        let leaf = leafRegion(containingGlobal: pos)
        if let region = leaf,
           let table = tableBox(containingGlobal: pos),
           let tv = blockViews[table.id] as? TableBackingView,
           region.region.globalStart >= table.nodeStart,
           region.region.globalStart < table.nodeStart + table.nodeSize {
            let unscrolled = region.region.caretRect(atLocal: region.local)
                .offsetBy(dx: region.region.canvasOrigin.x + region.region.emptyLineLeadingIndent,
                          dy: region.region.canvasOrigin.y)
            let frame = caretBar(from: unscrolled)
                .offsetBy(dx: -table.frame.minX, dy: -table.frame.minY)
            return (tv, frame)
        } else if let region = leaf {
            let frame = caretBar(from: region.region.caretRect(atLocal: region.local)
                .offsetBy(dx: region.region.canvasOrigin.x + region.region.emptyLineLeadingIndent,
                          dy: region.region.canvasOrigin.y))
            return (self, frame)
        } else if let img = mediaBox(atGap: pos) {
            let rr = img.mediaRect()
            return (self, CGRect(x: rr.minX, y: rr.minY, width: 2, height: rr.height))
        }
        return nil
    }

    /// Hosts an arbitrary overlay view at a placement (reparenting into a table's content view when
    /// needed), matching how the steady caret is hosted.
    func hostOverlay(_ v: UIView, at placement: (container: UIView, frame: CGRect)) {
        if let tv = placement.container as? TableBackingView {
            tv.hostCaret(v, at: placement.frame)
        } else {
            if v.superview !== placement.container { placement.container.addSubview(v) }
            placement.container.bringSubviewToFront(v)
            v.frame = placement.frame
        }
    }

    /// A 2pt-wide caret bar from a TextKit caret rect (keeps the OS-caret look used by `caretRect`).
    private func caretBar(from rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
    }

    private func hideCaretView() {
        caretView.stopBlink()
        if caretView.superview !== self { addSubview(caretView) }   // never leave it parked in a table's content view
        lastCaretContainer = nil
        lastCaretFrame = .null
    }

    /// Demo helper: set a selection spanning the middle of two blocks by index.
    func selectAcrossBlocks(firstIndex: Int, secondIndex: Int) {
        guard boxes.indices.contains(firstIndex), boxes.indices.contains(secondIndex) else { return }
        anchor = boxes[firstIndex].textStart + boxes[firstIndex].textLength / 2
        head = boxes[secondIndex].textStart + boxes[secondIndex].textLength / 2
        becomeFirstResponder()
        setNeedsDisplay(); refreshSelectionUI()
    }

    /// Demo helper: set a selection spanning mid-way through two leaf regions by document-order index.
    func selectAcrossLeafRegions(firstLeaf: Int, secondLeaf: Int) {
        let regions = allLeafRegions()
        guard regions.indices.contains(firstLeaf), regions.indices.contains(secondLeaf) else { return }
        let r1 = regions[firstLeaf], r2 = regions[secondLeaf]
        anchor = r1.globalStart + max(1, r1.length / 2)
        head   = r2.globalStart + max(1, r2.length / 2)
        becomeFirstResponder()
        setNeedsDisplay(); refreshSelectionUI()
    }
}

/// One pooled emoji: the host view plus its last canvas-space frame (for offscreen culling).
@available(iOS 13.0, *)
final class HostedEmoji {
    let view: UIView & RichTextEmojiView
    var canvasFrame: CGRect
    init(view: UIView & RichTextEmojiView, canvasFrame: CGRect) { self.view = view; self.canvasFrame = canvasFrame }
}

/// One pooled media view: the host view plus its last canvas-space frame (for offscreen culling).
@available(iOS 13.0, *)
final class HostedMediaItem {
    let view: RichTextMediaItemView
    var canvasFrame: CGRect
    // Signature of the item set the hosted `view` was built for (mediaID + kind + natural size, in order).
    // `syncMediaItemViews` recreates the view via the provider when a block's live items no longer match this
    // — the seam is one-shot, so a reused view can't be re-fed a changed item list in place.
    var itemsSignature: String
    init(view: RichTextMediaItemView, canvasFrame: CGRect, itemsSignature: String) {
        self.view = view; self.canvasFrame = canvasFrame; self.itemsSignature = itemsSignature
    }
}
#endif
