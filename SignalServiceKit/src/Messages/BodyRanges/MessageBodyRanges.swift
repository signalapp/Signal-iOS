//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// MessageBodyRanges is the result of parsing `SSKProtoBodyRange` from a message;
/// it performs some cleanups for overlaps and such, ensuring that we have a standard
/// non-overlapping representation which can also be used for message drafts in the composer.
///
/// This object must be further applied to NSAttributedString to actually display mentions and styles.
@objcMembers
public class MessageBodyRanges: NSObject, NSCopying, NSSecureCoding {

    // Limit to up to 250 ranges per message.
    public static let maxRangesPerMessage = 250

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

    /// Sorted from lowest location to highest location.
    /// Styles can overlap with mentions but not with each other.
    /// If a style overlaps with _any_ part of a mention, it applies
    /// to the entire length of the mention.
    public let collapsedStyles: [NSRangedValue<CollapsedStyle>]

    public var hasRanges: Bool {
        return mentions.isEmpty.negated || collapsedStyles.isEmpty.negated
    }

    public init(
        mentions: [NSRange: UUID],
        orderedMentions: [NSRangedValue<UUID>],
        collapsedStyles: [NSRangedValue<CollapsedStyle>]
    ) {
        self.mentions = mentions
        self.orderedMentions = orderedMentions
        self.collapsedStyles = collapsedStyles

        super.init()
    }

    public convenience init(mentions: [NSRange: UUID], styles: [NSRangedValue<SingleStyle>]) {
        let orderedMentions = mentions.lazy
            .sorted(by: { $0.key.location < $1.key.location })
            .map { return NSRangedValue($0.value, range: $0.key) }
        let collapsedStyles = Self.processStylesForInitialization(styles, orderedMentions: orderedMentions)

        self.init(mentions: mentions, orderedMentions: orderedMentions, collapsedStyles: collapsedStyles)
    }

    public convenience init(protos: [SSKProtoBodyRange]) {
        var mentions = [NSRange: UUID]()
        var styles = [NSRangedValue<SingleStyle>]()
        for proto in protos.prefix(Self.maxRangesPerMessage) {
            guard proto.length > 0 else {
                // Ignore empty ranges.
                continue
            }
            let range = NSRange(location: Int(proto.start), length: Int(proto.length))
            if let mentionAciString = proto.mentionAci, let mentionAci = Aci.parseFrom(aciString: mentionAciString) {
                mentions[range] = mentionAci.temporary_rawUUID
            } else if
                let protoStyle = proto.style,
                let style = SingleStyle.from(protoStyle)
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

        var rawStyles = [NSRangedValue<SingleStyle>]()
        var isMissingStyleOriginalInfo = false
        var styles = [NSRangedValue<CollapsedStyle>]()
        for idx in 0..<stylesCount {
            guard let range = coder.decodeObject(of: NSValue.self, forKey: "styles.range.\(idx)")?.rangeValue else {
                owsFailDebug("Failed to decode style range key of MessageBody")
                return nil
            }
            let style = Style(rawValue: coder.decodeInteger(forKey: "styles.style.\(idx)"))
            var originals = [SingleStyle: MergedSingleStyle]()
            var singleStyles = [SingleStyle]()
            for singleStyle in style.contents {
                singleStyles.append(singleStyle)
                let key = "styles.style.originals.\(singleStyle.rawValue).\(idx)"
                if
                    coder.containsValue(forKey: key),
                    let mergedRange = coder.decodeObject(of: NSValue.self, forKey: key)?.rangeValue
                {
                    originals[singleStyle] = MergedSingleStyle(style: singleStyle, mergedRange: mergedRange)
                } else {
                    // Legacy; we didn't preserve the ranges merged by single types before, we only
                    // preserved the fully collapsed ranges across styles.
                    // Fall back to fully flattening everything out and re-processing.
                    isMissingStyleOriginalInfo = true
                }
            }
            singleStyles.forEach {
                rawStyles.append(NSRangedValue($0, range: range))
            }
            styles.append(NSRangedValue(CollapsedStyle(style: style, originals: originals), range: range))
        }

        if isMissingStyleOriginalInfo {
            self.collapsedStyles = Self.processStylesForInitialization(
                rawStyles,
                orderedMentions: orderedMentions,
                // Legacy styles are going to be split; aggresively re-merge them which
                // drops some info but that info was ignored in the originals, anyway.
                mergeAdjacentRangesOfSameStyle: true
            )
        } else {
            self.collapsedStyles = styles
        }
    }

    private static func processStylesForInitialization(
        _ styles: [NSRangedValue<SingleStyle>],
        orderedMentions: [NSRangedValue<UUID>],
        mergeAdjacentRangesOfSameStyle: Bool = false
    ) -> [NSRangedValue<CollapsedStyle>] {
        guard !styles.isEmpty else {
            return []
        }
        var sortedSingleStyles = styles.lazy
            .filter {
                return $0.range.location >= 0
            }
            .sorted(by: { $0.range.location < $1.range.location })
        Self.extendStylesAcrossMentions(&sortedSingleStyles, orderedMentions: orderedMentions)
        var sortedStyles = MergedSingleStyle.merge(
            sortedOriginals: sortedSingleStyles,
            mergeAdjacentRangesOfSameStyle: mergeAdjacentRangesOfSameStyle
        )

        var indexesOfInterestSet = Set<Int>()
        var indexesOfInterest = [Int]()
        func insertIntoIndexesOfInterest(_ value: Int) {
            guard !indexesOfInterestSet.contains(value) else {
                return
            }
            indexesOfInterest.append(value)
            indexesOfInterestSet.insert(value)
        }

        sortedStyles.forEach {
            insertIntoIndexesOfInterest($0.mergedRange.location)
            insertIntoIndexesOfInterest($0.mergedRange.upperBound)
        }
        // This O(nlogn) operation can theoretically be flattened to O(n) via a lot
        // of index management, but as long as we limit the number of body ranges
        // we allow, the difference is trivial.
        indexesOfInterest.sort()

        // Collapse all overlaps.
        var finalStyles = [NSRangedValue<CollapsedStyle>]()
        var collapsedStyleAtIndex: (start: Int, CollapsedStyle) = (start: 0, .empty())
        var endIndexToStyles = [Int: Set<SingleStyle>]()

        for i in indexesOfInterest {
            var newStylesToApply: [MergedSingleStyle] = []

            func startApplyingStyles(at index: Int) {
                while let newMergedStyle = sortedStyles.first, newMergedStyle.mergedRange.location == index {
                    sortedStyles.removeFirst()
                    newStylesToApply.append(newMergedStyle)
                    var stylesAtEnd = endIndexToStyles[newMergedStyle.mergedRange.upperBound] ?? []
                    stylesAtEnd.insert(newMergedStyle.style)
                    endIndexToStyles[newMergedStyle.mergedRange.upperBound] = stylesAtEnd
                }
            }

            startApplyingStyles(at: i)
            let stylesToRemove = endIndexToStyles.removeValue(forKey: i) ?? []

            if newStylesToApply.isEmpty.negated || stylesToRemove.isEmpty.negated {
                // We have changes. End the previous style if any, and start a new one.
                var (startIndex, currentCollapsedStyle) = collapsedStyleAtIndex
                if currentCollapsedStyle.isEmpty.negated {
                    finalStyles.append(.init(
                        currentCollapsedStyle,
                        range: NSRange(location: startIndex, length: i - startIndex)
                    ))
                }

                stylesToRemove.forEach {
                    currentCollapsedStyle.remove($0)
                }
                newStylesToApply.forEach {
                    currentCollapsedStyle.insert($0)
                }
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

    /// If a style starts or ends in the middle of a mention range, the style should be extended
    /// to cover the entire mention.
    /// This needs to happen _before_ we merge styles, so that two disconnected
    /// styles that partly cover the same mention end up overlapping after being
    /// extended to cover the mention, and are therefore merged.
    private static func extendStylesAcrossMentions(
        _ sortedStyles: inout [NSRangedValue<SingleStyle>],
        orderedMentions: [NSRangedValue<UUID>]
    ) {
        let orderedMentions = orderedMentions
        let enumeratedStyles = sortedStyles.enumerated()
        for mention in orderedMentions {
            guard mention.range.length > 0 else {
                continue
            }
            // Styles always apply to an entire mention. This means when we find
            // a mention we have to do two things:
            // 1) any styles that start later in the mention are treated as if they start now.
            for var (styleIndex, style) in enumeratedStyles {
                if style.range.location > mention.range.location && style.range.location < mention.range.upperBound {
                    // Starts inside, move it to start at the beginning.
                    style = NSRangedValue(
                        style.value,
                        range: NSRange(
                            location: mention.range.location,
                            length: style.range.length + style.range.location - mention.range.location
                        )
                    )
                    // Note this maintains sort; it can't move the location before another
                    // style because that other style would gets its location moved up, too.
                    sortedStyles[styleIndex] = style
                }
                if style.range.upperBound > mention.range.location && style.range.upperBound < mention.range.upperBound {
                    // Ends inside, move it to end at the end of the mention.
                    style = NSRangedValue(
                        style.value,
                        range: NSRange(
                            location: style.range.location,
                            length: style.range.length + mention.range.upperBound - style.range.upperBound
                        )
                    )
                    sortedStyles[styleIndex] = style
                }
            }
        }
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
        // Flatten out all the collapsed styles so we can re-merge from
        // scratch with the new styles being added.
        let oldStyles: [NSRangedValue<SingleStyle>] = self.collapsedStyles.flatMap { collapsedStyle -> [NSRangedValue<SingleStyle>] in
            guard intersect(collapsedStyle.range) != nil else {
                return []
            }
            return collapsedStyle.value.style.contents.map {
                return NSRangedValue($0, range: collapsedStyle.range)
            }
        }
        let stylesInSubstring = styles.stylesInSubstring.flatMap { style in
            return style.value.contents.map {
                return NSRangedValue($0, range: style.range)
            }
        }
        let orderedMentions = mentions.lazy
            .sorted(by: { $0.key.location < $1.key.location })
            .map { NSRangedValue($0.value, range: $0.key) }
        let finalStyles = Self.processStylesForInitialization(
            oldStyles + stylesInSubstring,
            orderedMentions: orderedMentions
        )
        return MessageBodyRanges(
            mentions: mentions,
            orderedMentions: orderedMentions,
            collapsedStyles: finalStyles
        )
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return MessageBodyRanges(mentions: mentions, orderedMentions: orderedMentions, collapsedStyles: collapsedStyles)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(mentions.count, forKey: "mentionsCount")
        for (idx, (range, uuid)) in mentions.enumerated() {
            coder.encode(NSValue(range: range), forKey: "mentions.range.\(idx)")
            coder.encode(uuid, forKey: "mentions.uuid.\(idx)")
        }
        coder.encode(collapsedStyles.count, forKey: "stylesCount")
        for (idx, style) in collapsedStyles.enumerated() {
            coder.encode(NSValue(range: style.range), forKey: "styles.range.\(idx)")
            coder.encode(style.value.style.rawValue, forKey: "styles.style.\(idx)")
            for (singleStyle, mergedStyle) in style.value.originals {
                coder.encode(NSValue(range: mergedStyle.mergedRange), forKey: "styles.style.originals.\(singleStyle.rawValue).\(idx)")
            }
        }
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MessageBodyRanges else {
            return false
        }
        guard mentions == other.mentions else {
            return false
        }
        guard collapsedStyles.count == other.collapsedStyles.count else {
            return false
        }
        for i in 0..<collapsedStyles.count {
            let style = collapsedStyles[i]
            let otherStyle = other.collapsedStyles[i]
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
        let flattenedStyles = CollapsedStyle.flatten(collapsedStyles)

        func appendMention(_ mention: NSRangedValue<UUID>) {
            guard let builder = self.protoBuilder(mention.range, maxBodyLength: maxBodyLength) else {
                return
            }
            builder.setMentionAci(Aci(fromUUID: mention.value).serviceIdString)
            do {
                try protos.append(builder.build())
            } catch {
                owsFailDebug("Failed to build body range proto: \(error)")
            }
        }

        func appendStyle(_ style: NSRangedValue<SingleStyle>) {
            guard let builder = self.protoBuilder(style.range, maxBodyLength: maxBodyLength) else {
                return
            }
            builder.setStyle(style.value.asProtoStyle)
            do {
                try protos.append(builder.build())
            } catch {
                owsFailDebug("Failed to build body range proto: \(error)")
            }
        }

        while mentionIndex < orderedMentions.count || styleIndex < flattenedStyles.count {
            if mentionIndex >= orderedMentions.count {
                appendStyle(flattenedStyles[styleIndex])
                styleIndex += 1
                continue
            }
            if styleIndex >= collapsedStyles.count {
                appendMention(orderedMentions[mentionIndex])
                mentionIndex += 1
                continue
            }
            // Insert whichever is earlier.
            let mention = orderedMentions[mentionIndex]
            let style = collapsedStyles[styleIndex]
            if mention.range.location <= style.range.location {
                appendMention(orderedMentions[mentionIndex])
                mentionIndex += 1
            } else {
                appendStyle(flattenedStyles[styleIndex])
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
