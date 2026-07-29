//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// MessageBodyRanges is the result of parsing `SSKProtoBodyRange` from a message;
/// it performs some cleanups for overlaps and such, ensuring that we have a standard
/// non-overlapping representation which can also be used for message drafts in the composer.
///
/// This object must be further applied to NSAttributedString to actually display mentions and styles.
@objc
public final class MessageBodyRanges: NSObject, NSCopying, NSSecureCoding {
    // Limit to up to 250 ranges per message.
    public static let maxRangesPerMessage = 250

    public static var supportsSecureCoding: Bool { true }
    public static var empty: MessageBodyRanges { MessageBodyRanges(mentions: [], styles: []) }

    @objc
    public var hasMentions: Bool { !orderedMentions.isEmpty }

    /// Unsorted, potentially overlapping mentions
    private let originalMentions: [NSRangedValue<Aci>]

    /// Sorted, non-overlapping mentions
    public let orderedMentions: [NSRangedValue<Aci>]

    private static func normalizeMentions(_ mentions: [NSRangedValue<Aci>]) -> [NSRangedValue<Aci>] {
        // Sort by location
        let sortedMentions = mentions.sorted(by: {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            if $0.range.length != $1.range.length {
                return $0.range.length < $1.range.length
            }
            return $0.value < $1.value
        })
        // then keep non-empty ranges that don't overlap
        var filteredMentions = [NSRangedValue<Aci>]()
        for mention in sortedMentions {
            guard mention.range.length > 0 else {
                continue
            }
            guard mention.range.location >= (filteredMentions.last?.range.upperBound ?? .min) else {
                continue
            }
            filteredMentions.append(mention)
        }
        return filteredMentions
    }

    /// Sorted from lowest location to highest location.
    /// Styles can overlap with mentions but not with each other.
    /// If a style overlaps with _any_ part of a mention, it applies
    /// to the entire length of the mention.
    public let collapsedStyles: [NSRangedValue<CollapsedStyle>]

    public var hasRanges: Bool {
        return !orderedMentions.isEmpty || !collapsedStyles.isEmpty
    }

    private init(
        originalMentions: [NSRangedValue<Aci>],
        orderedMentions: [NSRangedValue<Aci>],
        collapsedStyles: [NSRangedValue<CollapsedStyle>],
    ) {
        self.originalMentions = originalMentions
        self.orderedMentions = orderedMentions
        self.collapsedStyles = collapsedStyles
    }

    public convenience init(collapsedStyles: [NSRangedValue<CollapsedStyle>]) {
        self.init(
            originalMentions: [],
            orderedMentions: [],
            collapsedStyles: collapsedStyles,
        )
    }

    public convenience init(mentions: [NSRangedValue<Aci>], styles: [NSRangedValue<SingleStyle>]) {
        let orderedMentions = Self.normalizeMentions(mentions)
        self.init(
            originalMentions: mentions,
            orderedMentions: orderedMentions,
            collapsedStyles: Self.normalizeStyles(styles, orderedMentions: orderedMentions),
        )
    }

    public convenience init(protos: [SSKProtoBodyRange]) {
        var mentions = [NSRangedValue<Aci>]()
        var styles = [NSRangedValue<SingleStyle>]()
        for proto in protos.prefix(Self.maxRangesPerMessage) {
            guard let location = Int(exactly: proto.start), let length = Int(exactly: proto.length) else {
                continue
            }
            let range = NSRange(location: location, length: length)
            if let mentionAci = Aci.parseFrom(serviceIdBinary: proto.mentionAciBinary, serviceIdString: proto.mentionAci) {
                mentions.append(NSRangedValue(mentionAci, range: range))
            } else if
                let protoStyle = proto.style,
                let style = SingleStyle.from(protoStyle)
            {
                styles.append(NSRangedValue(style, range: range))
            }
        }
        self.init(mentions: mentions, styles: styles)
    }

    public required init?(coder: NSCoder) {
        let mentionsCount = coder.decodeInteger(forKey: "mentionsCount")

        var mentions = [NSRangedValue<Aci>]()
        for idx in 0..<mentionsCount {
            guard let range = coder.decodeObject(of: NSValue.self, forKey: "mentions.range.\(idx)")?.rangeValue else {
                owsFailDebug("Failed to decode mention range key of MessageBody")
                return nil
            }
            guard let aciUuid = coder.decodeObject(of: NSUUID.self, forKey: "mentions.uuid.\(idx)") as UUID? else {
                owsFailDebug("Failed to decode mention range value of MessageBody")
                return nil
            }
            mentions.append(NSRangedValue(Aci(fromUUID: aciUuid), range: range))
        }

        self.originalMentions = mentions
        self.orderedMentions = Self.normalizeMentions(mentions)

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
            self.collapsedStyles = Self.normalizeStyles(
                rawStyles,
                orderedMentions: orderedMentions,
                // Legacy styles are going to be split; aggresively re-merge them which
                // drops some info but that info was ignored in the originals, anyway.
                mergeAdjacentRangesOfSameStyle: true,
            )
        } else {
            self.collapsedStyles = styles
        }
    }

    private static func normalizeStyles(
        _ styles: [NSRangedValue<SingleStyle>],
        orderedMentions: [NSRangedValue<Aci>],
        mergeAdjacentRangesOfSameStyle: Bool = false,
    ) -> [NSRangedValue<CollapsedStyle>] {
        var sortedSingleStyles = styles.lazy
            .filter {
                return $0.range.length > 0 && $0.range.location >= 0
            }
            .sorted(by: { $0.range.location < $1.range.location })
        Self.extendStylesAcrossMentions(&sortedSingleStyles, orderedMentions: orderedMentions)
        var sortedStyles = MergedSingleStyle.merge(
            sortedOriginals: sortedSingleStyles,
            mergeAdjacentRangesOfSameStyle: mergeAdjacentRangesOfSameStyle,
        )[...]

        var changeIndicesSet = Set<Int>()
        sortedStyles.forEach {
            changeIndicesSet.insert($0.mergedRange.location)
            changeIndicesSet.insert($0.mergedRange.upperBound)
        }
        let changeIndices = changeIndicesSet.sorted()

        // Collapse all overlaps.
        var finalStyles = [NSRangedValue<CollapsedStyle>]()
        var currentCollapsedStyle: CollapsedStyle = .empty()
        var currentCollapsedStyleStartIndex = 0
        var endIndexToStyles = [Int: Set<SingleStyle>]()

        for idx in changeIndices {
            var newStylesToApply: [MergedSingleStyle] = []

            func startApplyingStyles(at index: Int) {
                while let newMergedStyle = sortedStyles.first, newMergedStyle.mergedRange.location == index {
                    sortedStyles.removeFirst()
                    newStylesToApply.append(newMergedStyle)
                    endIndexToStyles[newMergedStyle.mergedRange.upperBound, default: Set()].insert(newMergedStyle.style)
                }
            }

            startApplyingStyles(at: idx)
            let stylesToRemove = endIndexToStyles.removeValue(forKey: idx) ?? []

            // Every element of changeIndices adds or removes at least one style, so at
            // least one of these will always be non-empty.
            assert(!newStylesToApply.isEmpty || !stylesToRemove.isEmpty)

            // We have changes. End the previous style if any, and start a new one.
            if !currentCollapsedStyle.isEmpty {
                finalStyles.append(.init(
                    currentCollapsedStyle,
                    range: NSRange(location: currentCollapsedStyleStartIndex, length: idx - currentCollapsedStyleStartIndex),
                ))
            }

            stylesToRemove.forEach {
                currentCollapsedStyle.remove($0)
            }
            newStylesToApply.forEach {
                currentCollapsedStyle.insert($0)
            }
            currentCollapsedStyleStartIndex = idx
        }

        // Every style is removed in the loop above; it's always empty at the end.
        assert(currentCollapsedStyle.isEmpty)

        return finalStyles
    }

    /// If a style starts or ends in the middle of a mention range, the style
    /// should be extended to cover the entire mention.
    ///
    /// This needs to happen _before_ we merge styles, so that two disconnected
    /// styles that partly cover the same mention end up overlapping after being
    /// extended to cover the mention, and are therefore merged.
    private static func extendStylesAcrossMentions(
        _ sortedStyles: inout [NSRangedValue<SingleStyle>],
        orderedMentions: [NSRangedValue<Aci>],
    ) {
        // TODO: Make this O(n lg n) rather than O(n^2).
        for mention in orderedMentions {
            // Styles always apply to an entire mention. This means when we find
            // a mention we have to do two things:
            // 1) any styles that start later in the mention are treated as if they start now.
            for idx in sortedStyles.indices {
                var style = sortedStyles[idx]
                if style.range.location > mention.range.location, style.range.location < mention.range.upperBound {
                    // Starts inside, move it to start at the beginning.
                    style = NSRangedValue(
                        style.value,
                        range: NSRange(
                            location: mention.range.location,
                            length: style.range.length + style.range.location - mention.range.location,
                        ),
                    )
                    // Note this maintains sort; it can't move the location before another
                    // style because that other style would gets its location moved up, too.
                    sortedStyles[idx] = style
                }
                if style.range.upperBound > mention.range.location, style.range.upperBound < mention.range.upperBound {
                    // Ends inside, move it to end at the end of the mention.
                    style = NSRangedValue(
                        style.value,
                        range: NSRange(
                            location: style.range.location,
                            length: style.range.length + mention.range.upperBound - style.range.upperBound,
                        ),
                    )
                    sortedStyles[idx] = style
                }
            }
        }
    }

    func addingStyles(_ newStyles: [NSRangedValue<Style>]) -> Self {
        // Flatten out all the collapsed styles so we can re-merge from
        // scratch with the new styles being added.
        let oldSingleStyles = self.collapsedStyles.flatMap { collapsedStyle -> [NSRangedValue<SingleStyle>] in
            return collapsedStyle.value.style.contents.map {
                return NSRangedValue($0, range: collapsedStyle.range)
            }
        }
        let newSingleStyles = newStyles.flatMap { style in
            return style.value.contents.map {
                return NSRangedValue($0, range: style.range)
            }
        }
        return Self(
            mentions: originalMentions,
            styles: oldSingleStyles + newSingleStyles,
        )
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    public func encode(with coder: NSCoder) {
        coder.encode(originalMentions.count, forKey: "mentionsCount")
        for (idx, mention) in originalMentions.enumerated() {
            coder.encode(NSValue(range: mention.range), forKey: "mentions.range.\(idx)")
            coder.encode(mention.value.rawUUID, forKey: "mentions.uuid.\(idx)")
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
        return (
            orderedMentions == other.orderedMentions
                && collapsedStyles == other.collapsedStyles,
        )
    }

    func clamped(to range: NSRange) -> Self {
        // This doesn't keep originalMentions because normalizing mentions and
        // clamping them isn't commutative. (In other words,
        // normalize(clamp(mentions)) may not equal clamp(normalize(mentions)).)
        let clampedMentions = self.orderedMentions.compactMap { $0.intersection(range) }
        return Self(
            originalMentions: clampedMentions,
            orderedMentions: clampedMentions,
            collapsedStyles: self.collapsedStyles.compactMap { $0.intersection(range) },
        )
    }

    public func offset(by utf16Count: Int) -> Self {
        return Self(
            originalMentions: self.originalMentions.map { $0.offset(by: utf16Count) },
            orderedMentions: self.orderedMentions.map { $0.offset(by: utf16Count) },
            collapsedStyles: self.collapsedStyles.map { $0.offset(by: utf16Count) },
        )
    }

    // MARK: Proto conversion

    /// If bodyLength is provided, drops any ranges that exceed the length.
    func toProtoBodyRanges(bodyLength: Int? = nil) -> [SSKProtoBodyRange] {
        let maxBodyLength = bodyLength
        var protos = [SSKProtoBodyRange]()

        func appendMention(_ mention: NSRangedValue<Aci>) {
            guard let builder = self.protoBuilder(mention.range, maxBodyLength: maxBodyLength) else {
                return
            }
            builder.setMentionAciBinary(mention.value.serviceIdBinary)
            protos.append(builder.buildInfallibly())
        }

        func appendStyle(_ style: NSRangedValue<SingleStyle>) {
            guard let builder = self.protoBuilder(style.range, maxBodyLength: maxBodyLength) else {
                return
            }
            builder.setStyle(style.value.asProtoStyle)
            protos.append(builder.buildInfallibly())
        }

        for mention in orderedMentions {
            appendMention(mention)
        }

        for singleStyle in CollapsedStyle.flatten(collapsedStyles) {
            appendStyle(singleStyle)
        }

        return protos
    }

    private func protoBuilder(
        _ range: NSRange,
        maxBodyLength: Int?,
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
