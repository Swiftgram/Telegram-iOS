import Foundation
import UIKit
import SwiftSignalKit
import Display
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGTrollPrivacy
import SGTrollPrivacyCore

// MARK: - TrollTweaks

private enum TweaksEntry: ItemListNodeEntry {
    case header(id: Int32, section: Int32, text: String)
    case toggle(id: Int32, section: Int32, key: String, title: String, value: Bool, enabled: Bool)
    case archive(id: Int32, section: Int32, count: Int)
    case clear(id: Int32, section: Int32, count: Int)
    case footer(id: Int32, section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .toggle(_, section, _, _, _, _), let .archive(_, section, _), let .clear(_, section, _), let .footer(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .toggle(id, _, _, _, _, _), let .archive(id, _, _), let .clear(id, _, _), let .footer(id, _, _):
            return id
        }
    }

    static func <(lhs: TweaksEntry, rhs: TweaksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TweaksArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .toggle(_, section, key, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, enabled: enabled, sectionId: section, style: .blocks, updated: { updated in
                arguments.toggle(key, updated)
            })
        case let .archive(_, section, count):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Saved Messages Log", label: "\(count)", sectionId: section, style: .blocks, action: {
                arguments.openArchive()
            })
        case let .clear(_, section, count):
            return ItemListActionItem(presentationData: presentationData, title: "Clear Saved Messages Log", kind: count == 0 ? .disabled : .destructive, alignment: .natural, sectionId: section, style: .blocks, action: {
                if count != 0 {
                    arguments.clearArchive()
                }
            })
        case let .footer(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private final class TweaksArguments {
    let toggle: (String, Bool) -> Void
    let openArchive: () -> Void
    let clearArchive: () -> Void

    init(toggle: @escaping (String, Bool) -> Void, openArchive: @escaping () -> Void, clearArchive: @escaping () -> Void) {
        self.toggle = toggle
        self.openArchive = openArchive
        self.clearArchive = clearArchive
    }
}

private func tweaksEntries(archiveCount: Int) -> [TweaksEntry] {
    var entries: [TweaksEntry] = []
    var id: Int32 = 0
    let ghostMode = TrollPrivacyOptions.flag(TrollPrivacyOptions.Key.ghostMode)
    for (index, group) in TrollPrivacyOptions.groups.enumerated() {
        let section = Int32(index + 1)
        id += 1
        entries.append(.header(id: id, section: section, text: group.title))
        for row in group.rows {
            id += 1
            entries.append(.toggle(id: id, section: section, key: row.key, title: row.title, value: TrollPrivacyOptions.flag(row.key), enabled: !row.requiresGhostMode || ghostMode))
        }
        if group.showsArchive {
            id += 1
            entries.append(.archive(id: id, section: section, count: archiveCount))
            id += 1
            entries.append(.clear(id: id, section: section, count: archiveCount))
        }
        if !group.footer.isEmpty {
            id += 1
            entries.append(.footer(id: id, section: section, text: group.footer))
        }
    }
    return entries
}

/// The TrollTweaks screen: Ghost Mode, saved messages and the other TrollGram switches.
public func trollTweaksController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    func redraw() {
        revision += 1
        refresh.set(revision)
    }

    weak var controllerReference: ViewController?

    let arguments = TweaksArguments(
        toggle: { key, value in
            TrollPrivacyOptions.setFlag(key, value)
            TrollPrivacyBootstrap.mirror()
            redraw()
        },
        openArchive: {
            controllerReference?.push(trollArchiveController(context: context))
        },
        clearArchive: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(context: context, title: "Clear Saved Messages Log?", text: "This deletes the log and every file saved with it from this device.", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: "Clear", action: {
                    TrollMessageArchive.shared.clear()
                    redraw()
                })
            ])
            controllerReference?.present(alert, in: .window(.root))
        }
    )

    let signal = combineLatest(queue: Queue.mainQueue(), refresh.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("TrollTweaks"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: tweaksEntries(archiveCount: TrollMessageArchive.shared.entryCount()), style: .blocks)
        return (controllerState, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controllerReference = controller
    return controller
}

// MARK: - Saved messages log

private enum ArchiveEntry: ItemListNodeEntry {
    case item(id: Int32, index: Int, title: String, label: String)
    case note(id: Int32, text: String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .item(id, _, _, _), let .note(id, _):
            return id
        }
    }

    static func <(lhs: ArchiveEntry, rhs: ArchiveEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! (Int) -> Void
        switch self {
        case let .item(_, index, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments(index)
            })
        case let .note(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private let archiveDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

private func archiveKindName(_ kind: String) -> String {
    switch kind {
    case TrollMessageArchive.Kind.deleted:
        return "Deleted"
    case TrollMessageArchive.Kind.edited:
        return "Earlier version of an edited message"
    case TrollMessageArchive.Kind.selfDestructing:
        return "Self-destructing media"
    default:
        return kind
    }
}

private func archiveTitle(_ entry: TrollMessageArchive.Entry) -> String {
    let prefix: String
    switch entry.kind {
    case TrollMessageArchive.Kind.deleted:
        prefix = "🗑 "
    case TrollMessageArchive.Kind.edited:
        prefix = "✎ "
    case TrollMessageArchive.Kind.selfDestructing:
        prefix = "⏱ "
    default:
        prefix = ""
    }
    let who = entry.authorTitle ?? entry.peerTitle ?? "Chat \(entry.peerId)"
    var body = entry.text.replacingOccurrences(of: "\n", with: " ")
    if let summary = entry.mediaSummary {
        body = body.isEmpty ? "[\(summary)]" : "[\(summary)] " + body
    }
    if body.count > 60 {
        body = String(body.prefix(60)) + "…"
    }
    return prefix + who + ": " + body
}

private func archiveDetails(_ entry: TrollMessageArchive.Entry) -> String {
    var lines: [String] = [archiveKindName(entry.kind)]
    if let chat = entry.peerTitle {
        lines.append("Chat: \(chat)")
    }
    if let author = entry.authorTitle {
        lines.append("From: \(author)")
    }
    lines.append("Sent: " + archiveDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.date))))
    lines.append("Saved: " + archiveDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.savedAt))))
    if let summary = entry.mediaSummary {
        lines.append("Media: \(summary)")
    }
    if let files = entry.media, !files.isEmpty {
        lines.append("Saved as: " + files.joined(separator: ", ") + " (in the app's Documents/TrollArchive/media)")
    } else if entry.mediaSummary != nil {
        lines.append("The file was not downloaded, so no copy exists.")
    }
    if !entry.text.isEmpty {
        lines.append("")
        lines.append(entry.text)
    }
    return lines.joined(separator: "\n")
}

/// Newest-first list of what the saved-messages switches logged; a row opens the details.
private func trollArchiveController(context: AccountContext) -> ViewController {
    let limit = 300
    let all = TrollMessageArchive.shared.load()
    let shown = Array(all.reversed().prefix(limit))

    weak var controllerReference: ViewController?

    let openDetails: (Int) -> Void = { index in
        guard shown.indices.contains(index) else {
            return
        }
        let entry = shown[index]
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var actions: [TextAlertAction] = []
        if !entry.text.isEmpty {
            actions.append(TextAlertAction(type: .genericAction, title: "Copy Text", action: {
                UIPasteboard.general.string = entry.text
            }))
        }
        actions.append(TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {}))
        controllerReference?.present(textAlertController(context: context, title: archiveTitle(entry), text: archiveDetails(entry), actions: actions), in: .window(.root))
    }

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Saved Messages Log"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        var entries: [ArchiveEntry] = []
        var id: Int32 = 0
        for (index, entry) in shown.enumerated() {
            id += 1
            entries.append(.item(id: id, index: index, title: archiveTitle(entry), label: archiveDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.savedAt)))))
        }
        id += 1
        if shown.isEmpty {
            entries.append(.note(id: id, text: "Nothing saved yet. Deleted messages, earlier versions of edited ones and self-destructing media appear here once the switches in TrollTweaks are on."))
        } else if all.count > shown.count {
            entries.append(.note(id: id, text: "Showing the newest \(shown.count) of \(all.count). Older entries are still in the log file."))
        }
        let nodeState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (nodeState, openDetails))
    }

    let controller = ItemListController(context: context, state: signal)
    controllerReference = controller
    return controller
}
