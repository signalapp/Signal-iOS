//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// MessageBodyRanges is the result of parsing `SSKProtoBodyRange` from a message;
/// it performs some cleanups for overlaps and such, ensuring that we have a standard
/// non-overlapping representation which can also be used for message drafts in the composer.
///
/// This object must be further applied to NSAttributedString to actually display mentions and styles.
@objcMembers
public class MessageBodyRanges: NSObject, NSCopying, NSSecureCoding {
    public static var supportsSecureCoding = true
    public static var empty: MessageBodyRanges { MessageBodyRanges(mentions: [:], styles: []) }

    // Styles are kept separate from mentions; mentions are not allowed to overlap,
    // which is partially enforced by its structure (it enforces they at least can't have
    // identical ranges) while styles can overlap with each other and
    // with mentions.

    /// Mentions can overlap with styles but not with each other.
    public let mentions: [NSRange: UUID]
    public var hasMentions: Bool { !mentions.isEmpty }

    /// Sorted from lowest location to highest location
    public let orderedMentions: [(NSRange, UUID)]

    public struct Style: OptionSet, Equatable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let bold = Style(rawValue: 1 << 0)
        public static let italic = Style(rawValue: 1 << 1)
        public static let spoiler = Style(rawValue: 1 << 2)
        public static let strikethrough = Style(rawValue: 1 << 3)
        public static let monospace = Style(rawValue: 1 << 4)

        static let attributedStringKey = NSAttributedString.Key("OWSStyle")
    }

    /// Sorted from lowest location to highest location.
    /// Styles can overlap with mentions but not with each other.
    /// If a style overlaps with _any_ part of a mention, it applies
    /// to the entire length of the mention.
    public let styles: [(NSRange, Style)]

    public var hasRanges: Bool {
        return mentions.isEmpty.negated || styles.isEmpty.negated
    }

    public init(mentions: [NSRange: UUID], styles: [(NSRange, Style)]) {
        self.mentions = mentions
        let orderedMentions = mentions.sorted(by: { $0.key.location < $1.key.location })
        self.orderedMentions = orderedMentions
        self.styles = Self.processStylesForInitialization(styles, orderedMentions: orderedMentions)

        super.init()
    }

    public convenience init(protos: [SSKProtoBodyRange]) {
        var mentions = [NSRange: UUID]()
        var styles = [(NSRange, Style)]()
        for proto in protos {
            let range = NSRange(location: Int(proto.start), length: Int(proto.length))
            if
                let mentionUuidString = proto.mentionUuid,
                let mentionUuid = UUID(uuidString: mentionUuidString)
            {
                mentions[range] = mentionUuid
            } else if let protoStyle = proto.style {
                let style: Style
                switch protoStyle {
                case .none:
                    continue
                case .bold:
                    style = .bold
                case .italic:
                    style = .italic
                case .spoiler:
                    style = .spoiler
                case .strikethrough:
                    style = .strikethrough
                case .monospace:
                    style = .monospace
                }
                styles.append((range, style))
            }
        }
        self.init(mentions: mentions, styles: styles)
    }

    public required init?(coder: NSCoder) {
        let mentionsCount = coder.decodeInteger(forKey: "mentionsCount")

        var mentions = [NSRange: UUID]()
        for idx in 0..<mentionsCount {
            guard let range = coder.decodeObject(of: NSValue.self, forKey: "mentions.range.\(idx)")?.rangeValue else {
                owsFailDebug("Failed to decode mention range key of MessageBody")
                return nil
            }
            guard let uuid = coder.decodeObject(of: NSUUID.self, forKey: "mentions.uuid.\(idx)") as UUID? else {
                owsFailDebug("Failed to decode mention range value of MessageBody")
                return nil
            }
            mentions[range] = uuid
        }

        self.mentions = mentions
        let orderedMentions = mentions.sorted(by: { $0.key.location < $1.key.location })
        self.orderedMentions = orderedMentions

        let stylesCount: Int = {
            let key = "stylesCount"
            guard coder.containsValue(forKey: key) else {
                // encoded values from before styles were added
                // have no styles; that's fine.
                return 0
            }
            return coder.decodeInteger(forKey: key)
        }()

        var styles = [(NSRange, Style)]()
        for idx in 0..<stylesCount {
            guard let range = coder.decodeObject(of: NSValue.self, forKey: "styles.range.\(idx)")?.rangeValue else {
                owsFailDebug("Failed to decode style range key of MessageBody")
                return nil
            }
            let style = Style(rawValue: coder.decodeInteger(forKey: "styles.style.\(idx)"))
            styles.append((range, style))
        }

        self.styles = Self.processStylesForInitialization(styles, orderedMentions: orderedMentions)
    }

    private static func processStylesForInitialization(
        _ styles: [(NSRange, Style)],
        orderedMentions: [(NSRange, UUID)]
    ) -> [(NSRange, Style)] {
        guard !styles.isEmpty else {
            return []
        }
        var maxUpperBound = orderedMentions.last?.0.upperBound ?? 0
        var sortedStyles = styles
            .lazy
            .filter { (range, _) in
                guard range.location >= 0 else {
                    return false
                }
                maxUpperBound = max(maxUpperBound, range.upperBound)
                return true
            }
            .sorted(by: { $0.0.location < $1.0.location })
        var orderedMentions = orderedMentions

        // Collapse all overlaps.
        var finalStyles = [(NSRange, Style)]()
        var collapsedStyleAtIndex: (start: Int, Style) = (start: 0, [])
        var endIndexToStyle = [Int: Style]()
        var styleToEndIndex = [Style: Int]()
        for i in 0..<maxUpperBound {
            var newStylesToApply: Style = []

            func startApplyingStyles(at index: Int) {
                while let (newRange, newStyle) = sortedStyles.first, newRange.location == index {
                    sortedStyles.removeFirst()
                    newStylesToApply.insert(newStyle)

                    // A new style starts here. But we might overlap with
                    // a style of the same type, in which case we should
                    // join them by taking the further of the two endpoints
                    let oldUpperBound = styleToEndIndex[newStyle]
                    if newRange.upperBound > (oldUpperBound ?? -1) {
                        styleToEndIndex[newStyle] = newRange.upperBound
                        var stylesAtEnd = endIndexToStyle[newRange.upperBound] ?? []
                        stylesAtEnd.insert(newStyle)
                        endIndexToStyle[newRange.upperBound] = stylesAtEnd
                        if let oldUpperBound {
                            var stylesAtExistingEnd = endIndexToStyle[oldUpperBound] ?? []
                            stylesAtExistingEnd.remove(newStyle)
                            endIndexToStyle[oldUpperBound] = stylesAtExistingEnd
                        }
                    }
                }
            }

            startApplyingStyles(at: i)
            let stylesToRemove = endIndexToStyle.removeValue(forKey: i) ?? []
            if stylesToRemove.isEmpty.negated {
                styleToEndIndex[stylesToRemove] = nil
            }

            if let mention = orderedMentions.first, mention.0.location == i {
                orderedMentions.removeFirst()
                if mention.0.length > 0 {
                    // Styles always apply to an entire mention. This means when we find
                    // a mention we have to do two things:
                    // 1) any styles that start later in the mention are treated as if they start now.
                    for j in i+1..<mention.0.upperBound {
                        startApplyingStyles(at: j)
                    }
                    // 2) make sure any active styles are extended to the end of the mention
                    for j in i..<mention.0.upperBound {
                        if let stylesEndingMidMention = endIndexToStyle.removeValue(forKey: j) {
                            var stylesAtNewEnd = endIndexToStyle[mention.0.upperBound] ?? []
                            stylesAtNewEnd.insert(stylesEndingMidMention)
                            endIndexToStyle[mention.0.upperBound] = stylesAtNewEnd
                        }
                    }
                }
            }

            if newStylesToApply.isEmpty.negated || stylesToRemove.isEmpty.negated {
                // We have changes. End the previous style if any, and start a new one.
                var (startIndex, currentCollapsedStyle) = collapsedStyleAtIndex
                if currentCollapsedStyle.isEmpty.negated {
                    finalStyles.append((NSRange(location: startIndex, length: i - startIndex), currentCollapsedStyle))
                }

                currentCollapsedStyle.remove(stylesToRemove)
                currentCollapsedStyle.insert(newStylesToApply)
                collapsedStyleAtIndex = (start: i, currentCollapsedStyle)
            }
        }

        if collapsedStyleAtIndex.1.isEmpty.negated {
            finalStyles.append((
                NSRange(
                    location: collapsedStyleAtIndex.start,
                    length: maxUpperBound - collapsedStyleAtIndex.start
                ),
                collapsedStyleAtIndex.1
            ))
        }

        return finalStyles
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return MessageBodyRanges(mentions: mentions, styles: styles)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(mentions.count, forKey: "mentionsCount")
        for (idx, (range, uuid)) in mentions.enumerated() {
            coder.encode(NSValue(range: range), forKey: "mentions.range.\(idx)")
            coder.encode(uuid, forKey: "mentions.uuid.\(idx)")
        }
        coder.encode(styles.count, forKey: "stylesCount")
        for (idx, (range, style)) in styles.enumerated() {
            coder.encode(NSValue(range: range), forKey: "styles.range.\(idx)")
            coder.encode(style.rawValue, forKey: "styles.style.\(idx)")
        }
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MessageBodyRanges else {
            return false
        }
        guard mentions == other.mentions else {
            return false
        }
        guard styles.count == other.styles.count else {
            return false
        }
        for i in 0..<styles.count {
            let style = styles[i]
            let otherStyle = other.styles[i]
            guard style.0 == otherStyle.0 else {
                return false
            }
            guard style.1 == otherStyle.1 else {
                return false
            }
        }
        return true
    }
}
