import Foundation
import UIKit
import Postbox
import TelegramCore
import AccountContext
import InstantPageUI

private let markdownPresentationIntentAttribute = NSAttributedString.Key("NSPresentationIntent")
private let markdownInlinePresentationIntentAttribute = NSAttributedString.Key("NSInlinePresentationIntent")
private let markdownLinkAttribute = NSAttributedString.Key("NSLink")
private let markdownImageURLAttribute = NSAttributedString.Key("NSImageURL")
private let markdownAlternateDescriptionAttribute = NSAttributedString.Key("NSAlternateDescription")

@available(iOS 15.0, *)
private let markdownSoftBreakInlineIntent = InlinePresentationIntent(rawValue: 1 << 6)
@available(iOS 15.0, *)
private let markdownHardBreakInlineIntent = InlinePresentationIntent(rawValue: 1 << 7)
@available(iOS 15.0, *)
private let markdownInlineHTMLInlineIntent = InlinePresentationIntent(rawValue: 1 << 8)

private let markdownDefaultBlockImageDimensions = PixelDimensions(width: 1200, height: 900)
private let markdownDefaultInlineImageDimensions = PixelDimensions(width: 18, height: 18)

private struct MarkdownPageResult {
    let blocks: [InstantPageBlock]
    let media: [MediaId: Media]
}

private enum MarkdownInlineFragment {
    case richText(RichText)
    case image(MarkdownResolvedImage)
}

private struct MarkdownInlineContent {
    let fragments: [MarkdownInlineFragment]
    
    var richText: RichText {
        var result: [RichText] = []
        result.reserveCapacity(self.fragments.count)
        
        for fragment in self.fragments {
            switch fragment {
            case let .richText(text):
                result.append(text)
            case let .image(image):
                var text: RichText = .image(id: image.mediaId, dimensions: image.inlineDimensions)
                if let linkUrl = image.linkUrl {
                    text = .url(text: text, url: linkUrl, webpageId: nil)
                }
                result.append(text)
            }
        }
        
        return markdownCompact(result)
    }
    
    var standaloneImage: MarkdownResolvedImage? {
        var result: MarkdownResolvedImage?
        
        for fragment in self.fragments {
            switch fragment {
            case let .richText(text):
                if !markdownIsWhitespaceOnly(text) {
                    return nil
                }
            case let .image(image):
                if result != nil {
                    return nil
                }
                result = image
            }
        }
        
        return result
    }
}

private struct MarkdownResolvedImage {
    let mediaId: MediaId
    let inlineDimensions: PixelDimensions
    let caption: InstantPageCaption
    let linkUrl: String?
}

private enum MarkdownResolvedImageSource {
    case remote(String)
    case data(Data, PixelDimensions)
    case unsupported
}

private final class MarkdownConversionContext {
    private let context: AccountContext
    fileprivate let documentURL: URL
    private var nextRemoteMediaId: Int64 = 0
    private var nextLocalMediaId: Int64 = 0
    
    private(set) var media: [MediaId: Media] = [:]
    
    init(context: AccountContext, documentURL: URL) {
        self.context = context
        self.documentURL = documentURL
    }
    
    func makePageResult(blocks: [InstantPageBlock]) -> MarkdownPageResult {
        return MarkdownPageResult(blocks: blocks, media: self.media)
    }
    
    func resolveImage(attributes: [NSAttributedString.Key: Any]) -> MarkdownResolvedImage? {
        guard let imageUrl = markdownImageURL(attributes: attributes) else {
            return nil
        }
        
        let inlineDimensions = markdownInlineImageDimensions(attributes: attributes)
        let caption = markdownImageCaption(markdownAlternateDescription(attributes: attributes))
        let linkUrl = markdownLink(attributes: attributes, documentURL: self.documentURL)
        
        switch markdownResolveImageSource(imageUrl) {
        case let .remote(url):
            let mediaId = self.nextMediaId(namespace: Namespaces.Media.CloudImage)
            self.media[mediaId] = TelegramMediaImage(
                imageId: mediaId,
                representations: [
                    TelegramMediaImageRepresentation(
                        dimensions: markdownDefaultBlockImageDimensions,
                        resource: InstantPageExternalMediaResource(url: url),
                        progressiveSizes: [],
                        immediateThumbnailData: nil
                    )
                ],
                immediateThumbnailData: nil,
                reference: nil,
                partialReference: nil,
                flags: []
            )
            return MarkdownResolvedImage(
                mediaId: mediaId,
                inlineDimensions: inlineDimensions,
                caption: caption,
                linkUrl: linkUrl
            )
        case let .data(data, dimensions):
            let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: Int64(data.count), isSecretRelated: false)
            self.context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
            
            let mediaId = self.nextMediaId(namespace: Namespaces.Media.LocalImage)
            self.media[mediaId] = TelegramMediaImage(
                imageId: mediaId,
                representations: [
                    TelegramMediaImageRepresentation(
                        dimensions: dimensions,
                        resource: resource,
                        progressiveSizes: [],
                        immediateThumbnailData: nil
                    )
                ],
                immediateThumbnailData: nil,
                reference: nil,
                partialReference: nil,
                flags: []
            )
            return MarkdownResolvedImage(
                mediaId: mediaId,
                inlineDimensions: inlineDimensions,
                caption: caption,
                linkUrl: linkUrl
            )
        case .unsupported:
            return nil
        }
    }
    
    private func nextMediaId(namespace: Int32) -> MediaId {
        switch namespace {
        case Namespaces.Media.LocalImage:
            self.nextLocalMediaId += 1
            return MediaId(namespace: namespace, id: self.nextLocalMediaId)
        default:
            self.nextRemoteMediaId += 1
            return MediaId(namespace: namespace, id: self.nextRemoteMediaId)
        }
    }
}

func markdownWebpage(context: AccountContext, file: FileMediaReference) -> (webPage: TelegramMediaWebpage, fileURL: URL)? {
    guard #available(iOS 15.0, *) else {
        return nil
    }
    guard let path = context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(file.media.resource.id)) else {
        return nil
    }
    let fileURL = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: fileURL) else {
        return nil
    }
    guard let webPage = markdownWebpage(context: context, file: file, fileURL: fileURL, data: data) else {
        return nil
    }
    return (webPage, fileURL)
}

@available(iOS 15.0, *)
private func markdownWebpage(context: AccountContext, file: FileMediaReference, fileURL: URL, data: Data) -> TelegramMediaWebpage? {
    let attributedString: NSAttributedString
    do {
        attributedString = try NSAttributedString(
            markdown: data,
            options: .init(),
            baseURL: fileURL.deletingLastPathComponent()
        )
    } catch {
        return nil
    }
    
    let conversionContext = MarkdownConversionContext(context: context, documentURL: fileURL)
    let pageResult = markdownPageResult(from: attributedString, context: conversionContext)
    let blocks = markdownBlocksWithGeneratedAnchors(pageResult.blocks)
    guard !blocks.isEmpty else {
        return nil
    }
    
    let title = markdownTitle(from: blocks, file: file, fileURL: fileURL)
    let text = markdownFirstParagraphText(from: blocks)
    let instantPage = InstantPage(
        blocks: blocks,
        media: pageResult.media,
        isComplete: true,
        rtl: false,
        url: fileURL.absoluteString,
        views: nil
    )
    
    return TelegramMediaWebpage(
        webpageId: MediaId(namespace: 0, id: 0),
        content: .Loaded(
            TelegramMediaWebpageLoadedContent(
                url: fileURL.absoluteString,
                displayUrl: fileURL.absoluteString,
                hash: 0,
                type: "article",
                websiteName: nil,
                title: title,
                text: text,
                embedUrl: nil,
                embedType: nil,
                embedSize: nil,
                duration: nil,
                author: nil,
                isMediaLargeByDefault: nil,
                imageIsVideoCover: false,
                image: nil,
                file: nil,
                story: nil,
                attributes: [],
                instantPage: instantPage
            )
        )
    )
}

@available(iOS 15.0, *)
private func markdownPageResult(from attributedString: NSAttributedString, context: MarkdownConversionContext) -> MarkdownPageResult {
    var nodesByIdentity: [Int: MarkdownIntentNode] = [:]
    var rootNodes: [MarkdownIntentNode] = []
    var rootIdentities: Set<Int> = []
    
    attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { attributes, range, _ in
        guard range.length > 0 else {
            return
        }
        guard let presentationIntent = attributes[markdownPresentationIntentAttribute] as? PresentationIntent else {
            return
        }
        let components = presentationIntent.components
        guard !components.isEmpty else {
            return
        }
        
        var orderedNodes: [MarkdownIntentNode] = []
        for component in components.reversed() {
            let node: MarkdownIntentNode
            if let current = nodesByIdentity[component.identity] {
                node = current
            } else {
                let created = MarkdownIntentNode(component: component)
                nodesByIdentity[component.identity] = created
                node = created
            }
            orderedNodes.append(node)
        }
        
        if let rootNode = orderedNodes.first, rootIdentities.insert(rootNode.identity).inserted {
            rootNodes.append(rootNode)
        }
        if orderedNodes.count >= 2 {
            for index in 0 ..< (orderedNodes.count - 1) {
                orderedNodes[index].append(child: orderedNodes[index + 1])
            }
        }
        if let leafNode = orderedNodes.last {
            leafNode.append(text: attributedString.attributedSubstring(from: range))
        }
    }
    
    return context.makePageResult(blocks: markdownBlocks(from: rootNodes, context: context))
}

private func markdownBlocks(from nodes: [MarkdownIntentNode], context: MarkdownConversionContext) -> [InstantPageBlock] {
    var result: [InstantPageBlock] = []
    for node in nodes {
        result.append(contentsOf: markdownBlocks(from: node, context: context))
    }
    return result
}

private func markdownBlocks(from node: MarkdownIntentNode, context: MarkdownConversionContext) -> [InstantPageBlock] {
    switch node.kind {
    case let .table(alignments):
        let rows = markdownTableRows(from: node.children, alignments: alignments, context: context)
        guard !rows.isEmpty else {
            return []
        }
        return [.table(title: .empty, rows: rows, bordered: true, striped: false)]
    case let .header(level):
        let text = markdownRichText(from: node.attributedText, context: context)
        guard markdownHasDisplayableContent(text) else {
            return []
        }
        if level <= 1 {
            return [.title(text)]
        } else if level == 2 {
            return [.header(text)]
        } else {
            return [.heading(text: text, level: Int32(max(3, min(level, 6))))]
        }
    case .paragraph:
        let inlineContent = markdownInlineContent(from: node.attributedText, context: context)
        if let image = inlineContent.standaloneImage {
            return [
                .image(
                    id: image.mediaId,
                    caption: image.caption,
                    url: image.linkUrl,
                    webpageId: nil
                )
            ]
        }
        let text = inlineContent.richText
        guard markdownHasDisplayableContent(text) else {
            return []
        }
        return [.paragraph(text)]
    case let .codeBlock(languageHint):
        let text = markdownRichText(from: markdownTrimTrailingCodeBlockNewline(node.attributedText), context: context)
        guard markdownHasDisplayableContent(text) else {
            return []
        }
        return [.preformatted(text: text, language: markdownNormalizedCodeBlockLanguage(languageHint))]
    case .thematicBreak:
        return [.divider]
    case .blockQuote:
        var result: [InstantPageBlock] = []
        for child in node.children {
            for childBlock in markdownBlocks(from: child, context: context) {
                switch childBlock {
                case let .paragraph(text):
                    result.append(.blockQuote(text: text, caption: .empty))
                default:
                    let plainText = markdownPlainText(from: childBlock)
                    if !plainText.isEmpty {
                        result.append(.blockQuote(text: .plain(plainText), caption: .empty))
                    }
                }
            }
        }
        return result
    case .orderedList:
        let items = markdownListItems(from: node.children, ordered: true, context: context)
        guard !items.isEmpty else {
            return []
        }
        return [.list(items: items, ordered: true)]
    case .unorderedList:
        let items = markdownListItems(from: node.children, ordered: false, context: context)
        guard !items.isEmpty else {
            return []
        }
        return [.list(items: items, ordered: false)]
    case .listItem(_), .tableHeaderRow, .tableRow, .tableCell(_), .unknown:
        return markdownBlocks(from: node.children, context: context)
    }
}

private func markdownListItems(from nodes: [MarkdownIntentNode], ordered: Bool, context: MarkdownConversionContext) -> [InstantPageListItem] {
    var result: [InstantPageListItem] = []
    for node in nodes {
        guard case let .listItem(ordinal) = node.kind else {
            continue
        }
        let blocks = markdownBlocks(from: node.children, context: context)
        guard !blocks.isEmpty else {
            continue
        }
        let number: String?
        if ordered {
            number = "\(ordinal)"
        } else {
            number = nil
        }
        if blocks.count == 1, case let .paragraph(text) = blocks[0] {
            result.append(.text(text, number))
        } else {
            result.append(.blocks(blocks, number))
        }
    }
    return result
}

private func markdownTableRows(from nodes: [MarkdownIntentNode], alignments: [TableHorizontalAlignment], context: MarkdownConversionContext) -> [InstantPageTableRow] {
    var result: [InstantPageTableRow] = []
    for node in nodes {
        switch node.kind {
        case .tableHeaderRow:
            let cells = markdownTableCells(from: node.children, alignments: alignments, header: true, context: context)
            if !cells.isEmpty {
                result.append(InstantPageTableRow(cells: cells))
            }
        case .tableRow:
            let cells = markdownTableCells(from: node.children, alignments: alignments, header: false, context: context)
            if !cells.isEmpty {
                result.append(InstantPageTableRow(cells: cells))
            }
        default:
            continue
        }
    }
    return result
}

private func markdownTableCells(from nodes: [MarkdownIntentNode], alignments: [TableHorizontalAlignment], header: Bool, context: MarkdownConversionContext) -> [InstantPageTableCell] {
    let maxColumnIndex = nodes.reduce(-1) { partialResult, node in
        if case let .tableCell(column) = node.kind {
            return max(partialResult, column)
        } else {
            return partialResult
        }
    }
    let columnCount = max(alignments.count, maxColumnIndex + 1)
    guard columnCount > 0 else {
        return []
    }
    
    var result: [InstantPageTableCell] = []
    var nextColumn = 0
    
    for node in nodes {
        guard case let .tableCell(column) = node.kind else {
            continue
        }
        
        while nextColumn < column {
            result.append(markdownEmptyTableCell(header: header, alignment: markdownTableAlignment(at: nextColumn, from: alignments)))
            nextColumn += 1
        }
        
        let text = markdownRichText(from: node.attributedText, context: context)
        result.append(
            InstantPageTableCell(
                text: text,
                header: header,
                alignment: markdownTableAlignment(at: column, from: alignments),
                verticalAlignment: .top,
                colspan: 1,
                rowspan: 1
            )
        )
        nextColumn = max(nextColumn, column + 1)
    }
    
    while nextColumn < columnCount {
        result.append(markdownEmptyTableCell(header: header, alignment: markdownTableAlignment(at: nextColumn, from: alignments)))
        nextColumn += 1
    }
    
    return result
}

private func markdownEmptyTableCell(header: Bool, alignment: TableHorizontalAlignment) -> InstantPageTableCell {
    return InstantPageTableCell(
        text: .empty,
        header: header,
        alignment: alignment,
        verticalAlignment: .top,
        colspan: 1,
        rowspan: 1
    )
}

private func markdownTableAlignment(at index: Int, from alignments: [TableHorizontalAlignment]) -> TableHorizontalAlignment {
    guard index >= 0, index < alignments.count else {
        return .left
    }
    return alignments[index]
}

private func markdownRichText(from attributedString: NSAttributedString, context: MarkdownConversionContext) -> RichText {
    return markdownInlineContent(from: attributedString, context: context).richText
}

private func markdownInlineContent(from attributedString: NSAttributedString, context: MarkdownConversionContext) -> MarkdownInlineContent {
    guard attributedString.length > 0, #available(iOS 15.0, *) else {
        return MarkdownInlineContent(fragments: [])
    }
    
    var fragments: [MarkdownInlineFragment] = []
    var htmlStyles: [MarkdownHTMLInlineStyle] = []
    var consumeNextSoftBreak = false
    
    attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { attributes, range, _ in
        guard range.length > 0 else {
            return
        }
        
        let text = attributedString.attributedSubstring(from: range).string
        guard !text.isEmpty else {
            return
        }
        
        let inlineIntent: InlinePresentationIntent?
        if let inlineIntentValue = attributes[markdownInlinePresentationIntentAttribute] as? InlinePresentationIntent {
            inlineIntent = inlineIntentValue
        } else if let inlineIntentValue = attributes[markdownInlinePresentationIntentAttribute] as? NSNumber {
            inlineIntent = InlinePresentationIntent(rawValue: inlineIntentValue.uintValue)
        } else {
            inlineIntent = nil
        }
        
        if let inlineIntent, inlineIntent.contains(markdownInlineHTMLInlineIntent), let directive = markdownHTMLDirective(for: text) {
            switch directive {
            case let .open(style):
                htmlStyles.append(style)
            case let .close(style):
                if let index = htmlStyles.lastIndex(of: style) {
                    htmlStyles.remove(at: index)
                }
            case .lineBreak:
                fragments.append(.richText(markdownApplyHTMLStyles(htmlStyles, to: .plain("\n"))))
                consumeNextSoftBreak = true
            }
            return
        }
        
        if consumeNextSoftBreak {
            if let inlineIntent, inlineIntent.contains(markdownSoftBreakInlineIntent), text == " " {
                consumeNextSoftBreak = false
                return
            }
            consumeNextSoftBreak = false
        }
        
        if let image = context.resolveImage(attributes: attributes) {
            fragments.append(.image(image))
            return
        }
        
        var fragment: RichText = .plain(text)
        if let inlineIntent {
            if inlineIntent.contains(.stronglyEmphasized) {
                fragment = .bold(fragment)
            }
            if inlineIntent.contains(.emphasized) {
                fragment = .italic(fragment)
            }
            if inlineIntent.contains(.strikethrough) {
                fragment = .strikethrough(fragment)
            }
            if inlineIntent.contains(.code) {
                fragment = .fixed(fragment)
            }
            if inlineIntent.contains(markdownHardBreakInlineIntent) {
                fragment = .plain("\n")
            }
        }
        
        if let url = markdownLink(attributes: attributes, documentURL: context.documentURL) {
            fragment = .url(text: fragment, url: url, webpageId: nil)
        }
        
        fragments.append(.richText(markdownApplyHTMLStyles(htmlStyles, to: fragment)))
    }
    
    return MarkdownInlineContent(fragments: fragments)
}

private enum MarkdownHTMLInlineStyle: Equatable {
    case `subscript`
    case superscript
    case marked
}

private enum MarkdownHTMLDirective {
    case open(MarkdownHTMLInlineStyle)
    case close(MarkdownHTMLInlineStyle)
    case lineBreak
}

private func markdownHTMLDirective(for text: String) -> MarkdownHTMLDirective? {
    switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "<sub>":
        return .open(.subscript)
    case "</sub>":
        return .close(.subscript)
    case "<sup>":
        return .open(.superscript)
    case "</sup>":
        return .close(.superscript)
    case "<mark>":
        return .open(.marked)
    case "</mark>":
        return .close(.marked)
    case "<br>", "<br/>", "<br />":
        return .lineBreak
    default:
        return nil
    }
}

private func markdownApplyHTMLStyles(_ styles: [MarkdownHTMLInlineStyle], to text: RichText) -> RichText {
    var result = text
    for style in styles {
        switch style {
        case .subscript:
            result = .subscript(result)
        case .superscript:
            result = .superscript(result)
        case .marked:
            result = .marked(result)
        }
    }
    return result
}

private func markdownAlternateDescription(attributes: [NSAttributedString.Key: Any]) -> String? {
    if let value = attributes[markdownAlternateDescriptionAttribute] as? String, !value.isEmpty {
        return value
    }
    return nil
}

private func markdownImageURL(attributes: [NSAttributedString.Key: Any]) -> String? {
    if let value = attributes[markdownImageURLAttribute] as? URL {
        return value.absoluteString
    }
    if let value = attributes[markdownImageURLAttribute] as? NSURL {
        return (value as URL).absoluteString
    }
    if let value = attributes[markdownImageURLAttribute] as? String, !value.isEmpty {
        return value
    }
    return nil
}

private func markdownResolveImageSource(_ value: String) -> MarkdownResolvedImageSource {
    if value.hasPrefix("//") {
        return .remote("https:\(value)")
    }
    
    if value.lowercased().hasPrefix("data:") {
        return markdownResolveDataImageSource(value)
    }
    
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
        return .unsupported
    }
    
    switch scheme {
    case "http", "https":
        return .remote(url.absoluteString)
    case "data":
        return markdownResolveDataImageSource(url.absoluteString)
    default:
        return .unsupported
    }
}

private func markdownResolveDataImageSource(_ value: String) -> MarkdownResolvedImageSource {
    guard value.lowercased().hasPrefix("data:"),
          let commaIndex = value.firstIndex(of: ",") else {
        return .unsupported
    }
    
    let header = String(value[value.index(value.startIndex, offsetBy: 5) ..< commaIndex])
    let payloadStart = value.index(after: commaIndex)
    let payload = String(value[payloadStart...])
    let isBase64 = header.lowercased().contains(";base64")
    
    let data: Data?
    if isBase64 {
        data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
    } else if let decodedPayload = payload.removingPercentEncoding {
        data = decodedPayload.data(using: .utf8)
    } else {
        data = nil
    }
    
    guard let data,
          let image = UIImage(data: data),
          let dimensions = markdownImagePixelDimensions(image) else {
        return .unsupported
    }
    
    return .data(data, dimensions)
}

private func markdownImagePixelDimensions(_ image: UIImage) -> PixelDimensions? {
    if let cgImage = image.cgImage {
        return PixelDimensions(width: Int32(cgImage.width), height: Int32(cgImage.height))
    }
    
    let width = max(1, Int32(ceil(image.size.width * image.scale)))
    let height = max(1, Int32(ceil(image.size.height * image.scale)))
    return PixelDimensions(width: width, height: height)
}

private func markdownImageCaption(_ title: String?) -> InstantPageCaption {
    if let title, !title.isEmpty {
        return InstantPageCaption(text: .plain(title), credit: .empty)
    } else {
        return InstantPageCaption(text: .empty, credit: .empty)
    }
}

private func markdownInlineImageDimensions(attributes: [NSAttributedString.Key: Any]) -> PixelDimensions {
    guard let font = attributes[.font] as? UIFont else {
        return markdownDefaultInlineImageDimensions
    }
    
    let side = max(markdownDefaultInlineImageDimensions.width, Int32(ceil(font.lineHeight)))
    return PixelDimensions(width: side, height: side)
}

private func markdownLink(attributes: [NSAttributedString.Key: Any], documentURL: URL) -> String? {
    if let value = attributes[markdownLinkAttribute] as? URL {
        return markdownNormalizedLink(value, documentURL: documentURL)
    }
    if let value = attributes[markdownLinkAttribute] as? NSURL {
        return markdownNormalizedLink(value as URL, documentURL: documentURL)
    }
    if let value = attributes[markdownLinkAttribute] as? String, !value.isEmpty {
        if value.hasPrefix("#") {
            return value
        }
        if let url = URL(string: value) {
            return markdownNormalizedLink(url, documentURL: documentURL)
        }
        return value
    }
    return nil
}

private func markdownNormalizedLink(_ url: URL, documentURL: URL) -> String {
    if url.baseURL != nil {
        let relative = url.relativeString
        if relative.hasPrefix("#") {
            return relative
        }
    }
    if let fragment = url.fragment, markdownMatchesDocument(url, documentURL: documentURL) {
        return "#\(fragment)"
    }
    return url.absoluteString
}

private func markdownMatchesDocument(_ url: URL, documentURL: URL) -> Bool {
    let normalizedUrl = markdownURLWithoutFragment(url)
    let normalizedDocumentURL = markdownURLWithoutFragment(documentURL)
    
    if normalizedUrl.isFileURL && normalizedDocumentURL.isFileURL {
        return normalizedUrl.standardizedFileURL == normalizedDocumentURL.standardizedFileURL
    } else {
        return normalizedUrl == normalizedDocumentURL
    }
}

private func markdownURLWithoutFragment(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
        return url
    }
    components.fragment = nil
    return components.url ?? url
}

private func markdownCompact(_ fragments: [RichText]) -> RichText {
    var compacted: [RichText] = []
    for fragment in fragments {
        switch fragment {
        case .empty:
            continue
        case let .plain(text):
            guard !text.isEmpty else {
                continue
            }
            if let last = compacted.last, case let .plain(lastText) = last {
                compacted[compacted.count - 1] = .plain(lastText + text)
            } else {
                compacted.append(fragment)
            }
        case let .concat(items):
            let nested = markdownCompact(items)
            switch nested {
            case .empty:
                continue
            case let .plain(text):
                if let last = compacted.last, case let .plain(lastText) = last {
                    compacted[compacted.count - 1] = .plain(lastText + text)
                } else {
                    compacted.append(.plain(text))
                }
            default:
                compacted.append(nested)
            }
        default:
            compacted.append(fragment)
        }
    }
    if compacted.isEmpty {
        return .empty
    } else if compacted.count == 1 {
        return compacted[0]
    } else {
        return .concat(compacted)
    }
}

private func markdownHasDisplayableContent(_ richText: RichText) -> Bool {
    switch richText {
    case .empty:
        return false
    case let .plain(text):
        return !text.isEmpty
    case let .bold(text),
         let .italic(text),
         let .underline(text),
         let .strikethrough(text),
         let .fixed(text),
         let .subscript(text),
         let .superscript(text),
         let .marked(text),
         let .anchor(text, _):
        return markdownHasDisplayableContent(text)
    case let .url(text, _, _),
         let .email(text, _),
         let .phone(text, _):
        return markdownHasDisplayableContent(text)
    case let .concat(items):
        return items.contains(where: markdownHasDisplayableContent)
    case .image:
        return true
    }
}

private func markdownIsWhitespaceOnly(_ richText: RichText) -> Bool {
    switch richText {
    case .empty:
        return true
    case let .plain(text):
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case let .bold(text),
         let .italic(text),
         let .underline(text),
         let .strikethrough(text),
         let .fixed(text),
         let .subscript(text),
         let .superscript(text),
         let .marked(text),
         let .anchor(text, _):
        return markdownIsWhitespaceOnly(text)
    case let .url(text, _, _),
         let .email(text, _),
         let .phone(text, _):
        return markdownIsWhitespaceOnly(text)
    case let .concat(items):
        return items.allSatisfy(markdownIsWhitespaceOnly)
    case .image:
        return false
    }
}

private func markdownPlainText(from block: InstantPageBlock) -> String {
    switch block {
    case let .title(text):
        return text.plainText
    case let .subtitle(text):
        return text.plainText
    case let .authorDate(author, _):
        return author.plainText
    case let .header(text):
        return text.plainText
    case let .subheader(text):
        return text.plainText
    case let .heading(text, _):
        return text.plainText
    case let .paragraph(text):
        return text.plainText
    case let .preformatted(text, _):
        return text.plainText
    case let .footer(text):
        return text.plainText
    case let .blockQuote(text, caption):
        return text.plainText.isEmpty ? caption.plainText : text.plainText
    case let .pullQuote(text, caption):
        return text.plainText.isEmpty ? caption.plainText : text.plainText
    case let .kicker(text):
        return text.plainText
    case let .table(title, _, _, _):
        return title.plainText
    case let .details(title, _, _):
        return title.plainText
    case let .relatedArticles(title, _):
        return title.plainText
    default:
        return ""
    }
}

private func markdownTitle(from blocks: [InstantPageBlock], file: FileMediaReference, fileURL: URL) -> String {
    for block in blocks {
        if case let .title(text) = block, !text.plainText.isEmpty {
            return text.plainText
        }
    }
    if let fileName = file.media.fileName, !fileName.isEmpty {
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if !baseName.isEmpty {
            return baseName
        }
        return fileName
    }
    let baseName = fileURL.deletingPathExtension().lastPathComponent
    if !baseName.isEmpty {
        return baseName
    }
    return fileURL.lastPathComponent
}

private func markdownNormalizedCodeBlockLanguage(_ language: String?) -> String? {
    guard let language else {
        return nil
    }
    let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.isEmpty ? nil : normalized
}

private func markdownFirstParagraphText(from blocks: [InstantPageBlock]) -> String? {
    for block in blocks {
        switch block {
        case let .paragraph(text):
            if !text.plainText.isEmpty {
                return text.plainText
            }
        case let .list(items, _):
            for item in items {
                switch item {
                case let .text(text, _):
                    if !text.plainText.isEmpty {
                        return text.plainText
                    }
                case let .blocks(blocks, _):
                    if let text = markdownFirstParagraphText(from: blocks) {
                        return text
                    }
                default:
                    break
                }
            }
        case let .details(_, blocks, _):
            if let text = markdownFirstParagraphText(from: blocks) {
                return text
            }
        default:
            break
        }
    }
    return nil
}

private func markdownBlocksWithGeneratedAnchors(_ blocks: [InstantPageBlock]) -> [InstantPageBlock] {
    var result: [InstantPageBlock] = []
    var slugCounts: [String: Int] = [:]
    
    for block in blocks {
        if let headingText = markdownHeadingText(from: block), !headingText.isEmpty {
            let baseSlug = markdownAnchorSlug(from: headingText)
            if !baseSlug.isEmpty {
                let count = slugCounts[baseSlug] ?? 0
                slugCounts[baseSlug] = count + 1
                
                let slug: String
                if count == 0 {
                    slug = baseSlug
                } else {
                    slug = "\(baseSlug)-\(count)"
                }
                result.append(.anchor(slug))
            }
        }
        result.append(block)
    }
    
    return result
}

private func markdownHeadingText(from block: InstantPageBlock) -> String? {
    switch block {
    case let .title(text):
        return text.plainText
    case let .header(text):
        return text.plainText
    case let .subheader(text):
        return text.plainText
    case let .heading(text, _):
        return text.plainText
    default:
        return nil
    }
}

private func markdownAnchorSlug(from text: String) -> String {
    let normalized = text
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        .lowercased()
    
    let dashScalar = "-".unicodeScalars.first!
    let separatorSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_"))
    var scalars: [UnicodeScalar] = []
    var previousWasDash = false
    
    for scalar in normalized.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            scalars.append(scalar)
            previousWasDash = false
        } else if separatorSet.contains(scalar) {
            if !scalars.isEmpty && !previousWasDash {
                scalars.append(dashScalar)
                previousWasDash = true
            }
        }
    }
    
    if scalars.last == dashScalar {
        scalars.removeLast()
    }
    
    return String(String.UnicodeScalarView(scalars))
}

private func markdownTrimTrailingCodeBlockNewline(_ attributedString: NSAttributedString) -> NSAttributedString {
    guard attributedString.length > 0 else {
        return attributedString
    }
    let mutable = NSMutableAttributedString(attributedString: attributedString)
    let string = mutable.string
    if string.hasSuffix("\r\n"), mutable.length >= 2 {
        mutable.deleteCharacters(in: NSRange(location: mutable.length - 2, length: 2))
    } else if string.hasSuffix("\n") {
        mutable.deleteCharacters(in: NSRange(location: mutable.length - 1, length: 1))
    }
    return mutable
}

private enum MarkdownIntentKind {
    case table([TableHorizontalAlignment])
    case tableHeaderRow
    case tableRow
    case tableCell(Int)
    case paragraph
    case header(Int)
    case codeBlock(String?)
    case thematicBreak
    case blockQuote
    case unorderedList
    case orderedList
    case listItem(Int)
    case unknown
    
    @available(iOS 15.0, *)
    init(component: PresentationIntent.IntentType) {
        switch component.kind {
        case let .table(columns):
            self = .table(columns.map(markdownTableColumnAlignment))
        case .tableHeaderRow:
            self = .tableHeaderRow
        case .tableRow(_):
            self = .tableRow
        case let .tableCell(column):
            self = .tableCell(column)
        case .paragraph:
            self = .paragraph
        case let .header(level):
            self = .header(level)
        case let .codeBlock(languageHint):
            self = .codeBlock(languageHint)
        case .thematicBreak:
            self = .thematicBreak
        case .blockQuote:
            self = .blockQuote
        case .unorderedList:
            self = .unorderedList
        case .orderedList:
            self = .orderedList
        case let .listItem(ordinal):
            self = .listItem(ordinal)
        default:
            self = .unknown
        }
    }
}

@available(iOS 15.0, *)
private func markdownTableColumnAlignment(_ column: PresentationIntent.TableColumn) -> TableHorizontalAlignment {
    switch column.alignment {
    case .left:
        return .left
    case .center:
        return .center
    case .right:
        return .right
    @unknown default:
        return .left
    }
}

private final class MarkdownIntentNode {
    let identity: Int
    let kind: MarkdownIntentKind
    
    private(set) var children: [MarkdownIntentNode] = []
    private var childIdentities: Set<Int> = []
    private(set) var attributedText = NSMutableAttributedString(string: "")
    
    @available(iOS 15.0, *)
    init(component: PresentationIntent.IntentType) {
        self.identity = component.identity
        self.kind = MarkdownIntentKind(component: component)
    }
    
    func append(child: MarkdownIntentNode) {
        if self.childIdentities.insert(child.identity).inserted {
            self.children.append(child)
        }
    }
    
    func append(text: NSAttributedString) {
        self.attributedText.append(text)
    }
}
