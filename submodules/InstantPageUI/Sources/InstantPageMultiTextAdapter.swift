import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore

public final class InstantPageMultiTextAdapter: ASDisplayNode, TextNodeProtocol {
    public struct Entry {
        public let item: InstantPageTextItem
        public let frameOrigin: CGPoint

        public init(item: InstantPageTextItem, frameOrigin: CGPoint) {
            self.item = item
            self.frameOrigin = frameOrigin
        }
    }

    private struct InternalEntry {
        let item: InstantPageTextItem
        let charOffset: Int
        let frameOrigin: CGPoint
    }

    private let entries: [InternalEntry]
    private let combinedString: NSAttributedString

    public init(entries: [Entry]) {
        let separator = NSAttributedString(string: "\n\n")
        let combined = NSMutableAttributedString()
        var internalEntries: [InternalEntry] = []
        for (index, entry) in entries.enumerated() {
            let charOffset = combined.length
            internalEntries.append(InternalEntry(item: entry.item, charOffset: charOffset, frameOrigin: entry.frameOrigin))
            combined.append(entry.item.attributedString)
            if index != entries.count - 1 {
                combined.append(separator)
            }
        }
        self.entries = internalEntries
        self.combinedString = combined
        super.init()
        self.isUserInteractionEnabled = false
    }

    public var currentText: NSAttributedString? {
        return self.combinedString
    }

    public func attributesAtPoint(_ point: CGPoint, orNearest: Bool) -> (Int, [NSAttributedString.Key: Any])? {
        for entry in self.entries {
            let localPoint = CGPoint(x: point.x - entry.frameOrigin.x, y: point.y - entry.frameOrigin.y)
            if let (localIndex, attrs) = entry.item.attributesAtPoint(localPoint, orNearest: false) {
                return (entry.charOffset + localIndex, attrs)
            }
        }
        guard orNearest, !self.entries.isEmpty else {
            return nil
        }
        var nearestEntry = self.entries[0]
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for entry in self.entries {
            let frame = CGRect(origin: entry.frameOrigin, size: entry.item.frame.size)
            let distance: CGFloat
            if point.y < frame.minY {
                distance = frame.minY - point.y
            } else if point.y > frame.maxY {
                distance = point.y - frame.maxY
            } else {
                distance = 0.0
            }
            if distance < nearestDistance {
                nearestDistance = distance
                nearestEntry = entry
            }
        }
        let localPoint = CGPoint(x: point.x - nearestEntry.frameOrigin.x, y: point.y - nearestEntry.frameOrigin.y)
        if let (localIndex, attrs) = nearestEntry.item.attributesAtPoint(localPoint, orNearest: true) {
            return (nearestEntry.charOffset + localIndex, attrs)
        }
        return nil
    }

    public func textRangeRects(in range: NSRange) -> (rects: [CGRect], start: TextRangeRectEdge, end: TextRangeRectEdge)? {
        var allRects: [CGRect] = []
        var startEdge: TextRangeRectEdge?
        var endEdge: TextRangeRectEdge?
        for entry in self.entries {
            let itemLength = entry.item.attributedString.length
            let entryRange = NSRange(location: entry.charOffset, length: itemLength)
            let intersection = NSIntersectionRange(range, entryRange)
            if intersection.length == 0 {
                continue
            }
            let localRange = NSRange(location: intersection.location - entry.charOffset, length: intersection.length)
            guard let result = entry.item.textRangeRects(in: localRange) else {
                continue
            }
            for rect in result.rects {
                allRects.append(rect.offsetBy(dx: entry.frameOrigin.x, dy: entry.frameOrigin.y))
            }
            let translatedStart = TextRangeRectEdge(x: result.start.x + entry.frameOrigin.x, y: result.start.y + entry.frameOrigin.y, height: result.start.height)
            let translatedEnd = TextRangeRectEdge(x: result.end.x + entry.frameOrigin.x, y: result.end.y + entry.frameOrigin.y, height: result.end.height)
            if startEdge == nil {
                startEdge = translatedStart
            }
            endEdge = translatedEnd
        }
        guard !allRects.isEmpty, let start = startEdge, let end = endEdge else {
            return nil
        }
        return (allRects, start, end)
    }
}
