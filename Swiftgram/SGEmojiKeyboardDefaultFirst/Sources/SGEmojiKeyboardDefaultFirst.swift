import Foundation


func sgPatchEmojiKeyboardItems(_ items: [EmojiPagerContentComponent.ItemGroup]) -> [EmojiPagerContentComponent.ItemGroup] {
    var items = items
    let staticEmojisIndex = items.firstIndex { item in
        if let groupId = item.groupId.base as? String, groupId == "static" {
            return true
        }
        return false
    }
    let recentEmojisIndex = items.firstIndex { item in
        if let groupId = item.groupId.base as? String, groupId == "recent" {
            return true
        }
        return false
    }
    if let staticEmojisIndex = staticEmojisIndex {
        let staticEmojiItem = items.remove(at: staticEmojisIndex)
        items.insert(staticEmojiItem, at: (recentEmojisIndex ?? -1) + 1 )
    }
    return items
}