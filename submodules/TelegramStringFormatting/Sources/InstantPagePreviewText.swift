import Foundation
import TelegramCore

extension RichText {
    public func previewText() -> String {
        switch self {
        case .empty:
            return ""
        case let .plain(value):
            return value
        case let .bold(value):
            return value.previewText()
        case let .italic(value):
            return value.previewText()
        case let .underline(value):
            return value.previewText()
        case let .strikethrough(value):
            return value.previewText()
        case let .fixed(value):
            return value.previewText()
        case let .url(value, _, _):
            return value.previewText()
        case let .email(value, _):
            return value.previewText()
        case let .concat(values):
            var result = ""
            for value in values {
                result.append(value.previewText())
            }
            return result
        case let .`subscript`(value):
            return value.previewText()
        case let .superscript(value):
            return value.previewText()
        case let .marked(value):
            return value.previewText()
        case let .phone(value, _):
            return value.previewText()
        case .image:
            //TODO:localize
            return "Photo"
        case let .anchor(value, _):
            return value.previewText()
        case .formula:
            //TODO:localize
            return "Fx"
        case let .textCustomEmoji(_, alt):
            return alt
        case let .textAutoEmail(value), let .textAutoPhone(value), let .textAutoUrl(value), let .textBankCard(value), let .textBotCommand(value), let .textCashtag(value), let .textHashtag(value), let .textMention(value), let .textMentionName(value, _), let .textSpoiler(value), let .textDate(value, _, _):
            return value.previewText()
        }
    }
}

extension InstantPageListItem {
    public func previewText() -> String {
        switch self {
        case .unknown:
            return ""
        case let .text(text, num, checked):
            let body = text.previewText()
            if let checked {
                return "\(checked ? "☑︎" : "☐") \(body)"
            } else if let num, !num.isEmpty {
                return "\(num). \(body)"
            } else {
                return body
            }
        case let .blocks(blocks, num, checked):
            var blocksText = ""
            for block in blocks {
                if !blocksText.isEmpty {
                    blocksText.append("\n")
                }
                blocksText.append(block.previewText())
            }
            if let checked {
                return "\(checked ? "☑︎" : "☐") \(blocksText)"
            } else if let num {
                return "\(num). \(blocksText)"
            } else {
                return blocksText
            }
        }
    }
}

extension InstantPageBlock {
    public func previewText() -> String {
        switch self {
        case .unsupported:
            return ""
        case let .title(text):
            return text.previewText()
        case let .subtitle(text):
            return text.previewText()
        case let .authorDate(author, _):
            return author.previewText()
        case let .header(text):
            return text.previewText()
        case let .subheader(text):
            return text.previewText()
        case let .heading(text, _):
            return text.previewText()
        case .formula:
            return "Fx"
        case let .paragraph(text):
            return text.previewText()
        case let .preformatted(text, _):
            return text.previewText()
        case let .footer(text):
            return text.previewText()
        case .divider:
            return "\n"
        case .anchor:
            return ""
        case let .list(items, _):
            var result = ""
            for item in items {
                if !result.isEmpty {
                    result.append("\n")
                }
                result.append(item.previewText())
            }
            return result
        case let .blockQuote(blocks, caption):
            let body = blocks.map { $0.previewText() }.joined(separator: " ")
            return body + caption.previewText()
        case let .pullQuote(text, caption):
            return text.previewText() + caption.previewText()
        case .image(_, _, _, _):
            //TODO:localize
            return "Photo"
        case .video(_, _, _, _):
            //TODO:localize
            return "Video"
        case .audio:
            //TODO:localize
            return "Audio"
        case .cover:
            return ""
        case .webEmbed:
            return ""
        case .postEmbed:
            return ""
        case .collage:
            return ""
        case .slideshow:
            return ""
        case .channelBanner:
            return ""
        case .kicker:
            return ""
        case .thinking:
            return ""
        case .table:
            //TODO:localize
            return "Table"
        case .details:
            return ""
        case .relatedArticles:
            return ""
        case .map:
            //TODO:localize
            return "Map"
        }
    }
}

extension InstantPage {
    public func previewText() -> String {
        let maxLength: Int = 200
        var result = ""
        for block in self.blocks {
            if !result.isEmpty {
                result.append("\n")
            }
            result.append(block.previewText())
            if result.count > maxLength {
                break
            }
        }
        return result
    }
}
