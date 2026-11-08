import Foundation
import AccountContext

// MARK: Swiftgram
/// Calculates toolbar auto-selection without committing an intermediate editor update.
public func sgChatTextInputStateSelectingLastWordIfIdle(_ state: ChatTextInputState) -> ChatTextInputState {
    // Keep an existing selection; an empty field or a caret at the start needs no change.
    let selectionRange = state.selectionRange
    guard selectionRange.isEmpty, selectionRange.lowerBound > 0 else {
        return state
    }

    // Use UTF-16 offsets to match the editor's selection range; reject an out-of-bounds caret.
    let text = state.inputText.string as NSString
    guard selectionRange.lowerBound <= text.length else {
        return state
    }

    // Word boundaries remain whitespace/newlines, not punctuation or linguistic word boundaries.
    let boundaries = CharacterSet.whitespacesAndNewlines
    // Start at the caret, skipping whitespace backwards to the previous word's exclusive end.
    var end = selectionRange.lowerBound
    while end > 0, (boundaries as NSCharacterSet).characterIsMember(text.character(at: end - 1)) {
        end -= 1
    }
    // Only whitespace before the caret: keep the current state.
    guard end > 0 else {
        return state
    }

    // Find the preceding boundary; a caret inside a word selects only the portion before it.
    let boundary = text.rangeOfCharacter(from: boundaries, options: .backwards, range: NSRange(location: 0, length: end))
    let start = boundary.location == NSNotFound ? 0 : NSMaxRange(boundary)
    // Update selection without rebuilding content from attributed text or committing to the editor.
    return ChatTextInputState(content: state.content, selectionRange: start ..< end)
}
//
