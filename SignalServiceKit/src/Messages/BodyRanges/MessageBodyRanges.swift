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
    public let orderedMentions: [NSRangedValue<UUID>]

    public struct Style: OptionSet, Equatable, Hashable, Codable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let bold = Style(rawValue: 1 << 0)
        public static let italic = Style(rawValue: 1 << 1)
        public static let spoiler = Style(rawValue: 1 << 2)
        public static let strikethrough = Style(rawValue: 1 << 3)
        public static let monospace = Style(rawValue: 1 << 4)

        public static let all: [Style] = [.bold, .italic, .spoiler, .strikethrough, .monospace]

        static let attributedStringKey = NSAttributedString.Key("OWSStyle")

        public static func from(_ protoStyle: SSKProtoBodyRangeStyle) -> Style? {
            switch protoStyle {
            case .none:
                return nil
            case .bold:
                return .bold
            case .italic:
                return .italic
            case .spoiler:
                return .spoiler
            case .strikethrough:
                return .strikethrough
            case .monospace:
                return .monospace
            }
        }

        /// Note it is one to many; we collapse styles into this option set
        /// in swift but in proto-land we fan out to one style per instance.
        public func asProtoStyles() -> [SSKProtoBodyRangeStyle] {
            return Self.all.compactMap {
                guard self.contains($0) else {
                    return nil
                }
                switch $0 {
                case .bold:
                    return .bold
                case .italic:
                    return .italic
                case .spoiler:
                    return .spoiler
                case .strikethrough:
                    return .strikethrough
                case .monospace:
                    return .monospace
                default:
                    return nil
                }
            }
        }
    }

    /// Sorted from lowest location to highest location.
    /// Styles can overlap with mentions but not with each other.
    /// If a style overlaps with _any_ part of a mention, it applies
    /// to the entire length of the mention.
    public let styles: [NSRangedValue<Style>]

    public var hasRanges: Bool {
        return mentions.isEmpty.negated || styles.isEmpty.negated
    }

    public init(mentions: [NSRange: UUID], styles: [NSRangedValue<Style>]) {
        self.mentions = mentions
        let orderedMentions = mentions.lazy
            .sorted(by: { $0.key.location < $1.key.location })
            .map { return NSRangedValue($0.value, range: $0.key) }
        self.orderedMentions = orderedMentions
        self.styles = Self.processStylesForInitialization(styles, orderedMentions: orderedMentions)

        super.init()
    }

    public convenience init(protos: [SSKProtoBodyRange]) {
        var mentions = [NSRange: UUID]()
        var styles = [NSRangedValue<Style>]()
        // Limit to up to 250 ranges per message.
        for proto in protos.prefix(250) {
            guard proto.length > 0 else {
                // Ignore empty ranges.
                continue
            }
            let range = NSRange(location: Int(proto.start), length: Int(proto.length))
            if
                let mentionUuidString = proto.mentionUuid,
                let mentionUuid = UUID(uuidString: mentionUuidString)
            {
                mentions[range] = mentionUuid
            } else if
                let protoStyle = proto.style,
                let style = Style.from(protoStyle)
            {
                styles.append(.init(style, range: range))
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
        let orderedMentions = mentions.lazy
            .sorted(by: { $0.key.location < $1.key.location })
            .map { NSRangedValue($0.value, range: $0.key) }
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

        var styles = [NSRangedValue<Style>]()
        for idx in 0..<stylesCount {
            guard let range = coder.decodeObject(of: NSValue.self, forKey: "styles.range.\(idx)")?.rangeValue else {
                owsFailDebug("Failed to decode style range key of MessageBody")
                return nil
            }
            let style = Style(rawValue: coder.decodeInteger(forKey: "styles.style.\(idx)"))
            styles.append(.init(style, range: range))
        }

        self.styles = Self.processStylesForInitialization(styles, orderedMentions: orderedMentions)
    }

    private static func processStylesForInitialization(
        _ styles: [NSRangedValue<Style>],
        orderedMentions: [NSRangedValue<UUID>]
    ) -> [NSRangedValue<Style>] {
        guard !styles.isEmpty else {
            return []
        }
        var indexesOfInterest = [Int]()
        var sortedStyles = styles
            .lazy
            .filter {
                guard $0.range.location >= 0 else {
                    return false
                }
                indexesOfInterest.append($0.range.location)
                indexesOfInterest.append($0.range.upperBound)
                return true
            }
            .sorted(by: { $0.range.location < $1.range.location })

        orderedMentions.forEach {
            indexesOfInterest.append($0.range.location)
            indexesOfInterest.append($0.range.upperBound)
        }
        // This O(nlogn) operation can theoretically be flattened to O(n) via a lot
        // of index management, but as long as we limit the number of body ranges
        // we allow, the difference is trivial.
        indexesOfInterest.sort()

        var orderedMentions = orderedMentions

        // Collapse all overlaps.
        var finalStyles = [NSRangedValue<Style>]()
        var collapsedStyleAtIndex: (start: Int, Style) = (start: 0, [])
        var endIndexToStyle = [Int: Style]()
        var styleToEndIndex = [Style: Int]()

        for i in indexesOfInterest {
            var newStylesToApply: Style = []

            func startApplyingStyles(at index: Int) {
                while let newRangedStyle = sortedStyles.first, newRangedStyle.range.location == index {
                    sortedStyles.removeFirst()
                    newStylesToApply.insert(newRangedStyle.value)

                    // A new style starts here. But we might overlap with
                    // a style of the same type, in which case we should
                    // join them by taking the further of the two endpoints
                    let oldUpperBound = styleToEndIndex[newRangedStyle.value]
                    if newRangedStyle.range.upperBound > (oldUpperBound ?? -1) {
                        styleToEndIndex[newRangedStyle.value] = newRangedStyle.range.upperBound
                        var stylesAtEnd = endIndexToStyle[newRangedStyle.range.upperBound] ?? []
                        stylesAtEnd.insert(newRangedStyle.value)
                        endIndexToStyle[newRangedStyle.range.upperBound] = stylesAtEnd
                        if let oldUpperBound {
                            var stylesAtExistingEnd = endIndexToStyle[oldUpperBound] ?? []
                            stylesAtExistingEnd.remove(newRangedStyle.value)
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

            if let mention = orderedMentions.first, mention.range.location == i {
                orderedMentions.removeFirst()
                if mention.range.length > 0 {
                    // Styles always apply to an entire mention. This means when we find
                    // a mention we have to do two things:
                    // 1) any styles that start later in the mention are treated as if they start now.
                    innerloop: for j in indexesOfInterest {
                        guard j > i else {
                            continue
                        }
                        guard j < mention.range.upperBound else {
                            break innerloop
                        }
                        startApplyingStyles(at: j)
                    }
                    // 2) make sure any active styles are extended to the end of the mention
                    innerloop: for j in indexesOfInterest {
                        guard j > i else {
                            continue
                        }
                        guard j < mention.range.upperBound else {
                            break innerloop
                        }
                        if let stylesEndingMidMention = endIndexToStyle.removeValue(forKey: j) {
                            var stylesAtNewEnd = endIndexToStyle[mention.range.upperBound] ?? []
                            stylesAtNewEnd.insert(stylesEndingMidMention)
                            endIndexToStyle[mention.range.upperBound] = stylesAtNewEnd
                        }
                    }
                }
            }

            if newStylesToApply.isEmpty.negated || stylesToRemove.isEmpty.negated {
                // We have changes. End the previous style if any, and start a new one.
                var (startIndex, currentCollapsedStyle) = collapsedStyleAtIndex
                if currentCollapsedStyle.isEmpty.negated {
                    finalStyles.append(.init(
                        currentCollapsedStyle,
                        range: NSRange(location: startIndex, length: i - startIndex)
                    ))
                }

                currentCollapsedStyle.remove(stylesToRemove)
                currentCollapsedStyle.insert(newStylesToApply)
                collapsedStyleAtIndex = (start: i, currentCollapsedStyle)
            }
        }

        if collapsedStyleAtIndex.1.isEmpty.negated {
            finalStyles.append(.init(
                collapsedStyleAtIndex.1,
                range: NSRange(
                    location: collapsedStyleAtIndex.start,
                    length: max(0, (indexesOfInterest.last ?? 0) - collapsedStyleAtIndex.start)
                )
            ))
        }

        return finalStyles
    }

    internal struct SubrangeStyles {
        let substringRange: NSRange
        let stylesInSubstring: [NSRangedValue<Style>]
    }

    /// Given a subrange and set of styles indexed _within that subrange_,
    /// filters ranges to those within that subrange and merges them with
    /// the provided styles.
    ///
    /// This method is confusing because of the interpretation of ranges.
    /// _First_ we filter the ranges to those falling in the subrange; the subrange
    /// is now our coordinate system, with its start being 0.
    /// _Then_ we merge in the styles, which are already in this coordinate system.
    internal func mergingStyles(_ styles: SubrangeStyles) -> MessageBodyRanges {
        func intersect(_ range: NSRange) -> NSRange? {
            guard
                let intersection = range.intersection(styles.substringRange),
                intersection.location != NSNotFound,
                intersection.length > 0
            else {
                return nil
            }
            return NSRange(
                location: intersection.location - styles.substringRange.location,
                length: intersection.length
            )
        }

        var mentions = [NSRange: UUID]()
        for (range, uuid) in self.mentions {
            guard let newRange = intersect(range) else {
                continue
            }
            mentions[newRange] = uuid
        }
        let oldStyles: [NSRangedValue<Style>] = self.styles.compactMap { style in
            guard let newRange = intersect(style.range) else {
                return nil
            }
            return .init(style.value, range: newRange)
        }
        let finalStyles = Self.processStylesForInitialization(
            oldStyles + styles.stylesInSubstring,
            orderedMentions: mentions.lazy
                .sorted(by: { $0.key.location < $1.key.location })
                .map { NSRangedValue($0.value, range: $0.key) }
        )
        return MessageBodyRanges(
            mentions: mentions,
            styles: finalStyles
        )
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
        for (idx, style) in styles.enumerated() {
            coder.encode(NSValue(range: style.range), forKey: "styles.range.\(idx)")
            coder.encode(style.value.rawValue, forKey: "styles.style.\(idx)")
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
            guard style.value == otherStyle.value else {
                return false
            }
            guard style.range == otherStyle.range else {
                return false
            }
        }
        return true
    }

    // MARK: Proto conversion

    /// If bodyLength is provided (is nonnegative), drops any ranges that exceed the length.
    func toProtoBodyRanges(bodyLength: Int = -1) -> [SSKProtoBodyRange] {
        let maxBodyLength = bodyLength < 0 ? nil : bodyLength
        var protos = [SSKProtoBodyRange]()

        var mentionIndex = 0
        var styleIndex = 0

        func appendMention(_ mention: NSRangedValue<UUID>) {
            guard let builder = self.protoBuilder(mention.range, maxBodyLength: maxBodyLength) else {
                return
            }
            builder.setMentionUuid(mention.value.uuidString)
            do {
                try protos.append(builder.build())
            } catch {
                owsFailDebug("Failed to build body range proto: \(error)")
            }
        }

        func appendStyle(_ style: NSRangedValue<Style>) {
            for protoStyle in style.value.asProtoStyles() {
                guard let builder = self.protoBuilder(style.range, maxBodyLength: maxBodyLength) else {
                    continue
                }
                builder.setStyle(protoStyle)
                do {
                    try protos.append(builder.build())
                } catch {
                    owsFailDebug("Failed to build body range proto: \(error)")
                }
            }
        }

        while mentionIndex < orderedMentions.count || styleIndex < styles.count {
            if mentionIndex >= orderedMentions.count {
                appendStyle(styles[styleIndex])
                styleIndex += 1
                continue
            }
            if styleIndex >= styles.count {
                appendMention(orderedMentions[mentionIndex])
                mentionIndex += 1
                continue
            }
            // Insert whichever is earlier.
            let mention = orderedMentions[mentionIndex]
            let style = styles[styleIndex]
            if mention.range.location <= style.range.location {
                appendMention(orderedMentions[mentionIndex])
                mentionIndex += 1
            } else {
                appendStyle(styles[styleIndex])
                styleIndex += 1
            }
        }
        return protos
    }

    private func protoBuilder(
        _ range: NSRange,
        maxBodyLength: Int?
    ) -> SSKProtoBodyRangeBuilder? {
        var range = range
        if let maxBodyLength {
            if range.location >= maxBodyLength {
                return nil
            }
            if range.upperBound > maxBodyLength {
                range = NSRange(location: range.location, length: maxBodyLength - range.location)
            }
        }

        let builder = SSKProtoBodyRange.builder()
        builder.setStart(UInt32(truncatingIfNeeded: range.location))
        builder.setLength(UInt32(truncatingIfNeeded: range.length))
        return builder
    }
}
