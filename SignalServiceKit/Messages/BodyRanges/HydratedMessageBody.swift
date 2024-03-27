//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFAudio
import Foundation
import LibSignalClient

/// The result of stripping, filtering, and hydrating mentions in a `MessageBody`.
/// This object can be held durably in memory as a way to cache mention hydrations
/// and other expensive string operations, and can subsequently be transformed
/// into string and attributed string values for display.
public class HydratedMessageBody: Equatable, Hashable {

    public typealias Style = MessageBodyRanges.Style
    public typealias SingleStyle = MessageBodyRanges.SingleStyle
    public typealias CollapsedStyle = MessageBodyRanges.CollapsedStyle

    private let hydratedText: String
    private let unhydratedMentions: [NSRangedValue<UnhydratedMentionAttribute>]
    private let mentionAttributes: [NSRangedValue<HydratedMentionAttribute>]
    private let styleAttributes: [NSRangedValue<StyleAttribute>]

    public var isEmpty: Bool { hydratedText.isEmpty }

    public static func == (lhs: HydratedMessageBody, rhs: HydratedMessageBody) -> Bool {
        return lhs.hydratedText == rhs.hydratedText
            && lhs.mentionAttributes == rhs.mentionAttributes
            && lhs.styleAttributes == rhs.styleAttributes
            && lhs.unhydratedMentions == rhs.unhydratedMentions
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hydratedText)
        hasher.combine(unhydratedMentions)
        hasher.combine(mentionAttributes)
        hasher.combine(styleAttributes)
    }

    internal init(
        hydratedText: String,
        unhydratedMentions: [NSRangedValue<UnhydratedMentionAttribute>] = [],
        mentionAttributes: [NSRangedValue<HydratedMentionAttribute>],
        styleAttributes: [NSRangedValue<StyleAttribute>]
    ) {
        self.hydratedText = hydratedText
        self.unhydratedMentions = unhydratedMentions
        self.mentionAttributes = mentionAttributes
        self.styleAttributes = styleAttributes
    }

    public static func fromPlaintextWithoutRanges(_ text: String) -> HydratedMessageBody {
        return HydratedMessageBody(hydratedText: text, mentionAttributes: [], styleAttributes: [])
    }

    internal init(
        messageBody: MessageBody,
        mentionHydrator: MentionHydrator,
        isRTL: Bool = CurrentAppContext().isRTL
    ) {
        guard messageBody.text.isEmpty.negated else {
            self.hydratedText = ""
            self.unhydratedMentions = []
            self.mentionAttributes = []
            self.styleAttributes = []
            return
        }

        var mentionsInOriginal = messageBody.ranges.orderedMentions
        var stylesInOriginal = messageBody.ranges.collapsedStyles

        let finalText = NSMutableString(string: messageBody.text)
        let startLength = finalText.length
        var unhydratedMentions = [NSRangedValue<UnhydratedMentionAttribute>]()
        var finalStyleAttributes = [NSRangedValue<StyleAttribute>]()
        var finalMentionAttributes = [NSRangedValue<HydratedMentionAttribute>]()

        var rangeOffset = 0

        struct ProcessingStyle {
            let originalRange: NSRange
            let newRange: NSRange
            let style: CollapsedStyle
        }
        var styleAtCurrentIndex: ProcessingStyle?

        for currentIndex in 0..<startLength {
            // If we are past the end, apply the active style to the final result
            // and drop.
            if
                let style = styleAtCurrentIndex,
                currentIndex >= style.originalRange.upperBound
            {
                finalStyleAttributes.append(.init(
                    StyleAttribute.fromCollapsedStyle(style.style),
                    range: style.newRange
                ))
                styleAtCurrentIndex = nil
            }
            // Check for any new styles starting at the current index.
            if stylesInOriginal.first?.range.contains(currentIndex) == true {
                let style = stylesInOriginal.removeFirst()
                let originalRange = style.range
                styleAtCurrentIndex = .init(
                    originalRange: originalRange,
                    newRange: NSRange(
                        location: originalRange.location + rangeOffset,
                        length: originalRange.length
                    ),
                    style: style.value
                )
            }

            // Check for any mentions at the current index.
            // Mentions can't overlap, so we don't need a while loop to check for multiple.
            guard
                let mention = mentionsInOriginal.first,
                (
                    mention.range.contains(currentIndex)
                    || mention.range.location == currentIndex
                )
            else {
                // No mentions, so no additional logic needed, just go to the next index.
                continue
            }
            mentionsInOriginal.removeFirst()

            let newMentionRange = NSRange(
                location: mention.range.location + rangeOffset,
                length: mention.range.length
            )

            let finalMentionLength: Int
            let mentionOffsetDelta: Int
            switch mentionHydrator(mention.value) {
            case .preserveMention:
                // Preserve the mention without replacement and proceed.
                unhydratedMentions.append(.init(
                    UnhydratedMentionAttribute.fromOriginalRange(mention.range, mentionAci: mention.value),
                    range: newMentionRange
                ))
                continue
            case let .hydrate(displayName):
                let mentionPlaintext: String
                if isRTL {
                    mentionPlaintext = displayName + Mention.prefix
                } else {
                    mentionPlaintext = Mention.prefix + displayName
                }
                finalMentionLength = (mentionPlaintext as NSString).length
                // Make sure we don't have any illegal mention ranges; if so skip them.
                if newMentionRange.upperBound <= finalText.length {
                    mentionOffsetDelta = finalMentionLength - mention.range.length
                    finalText.replaceCharacters(in: newMentionRange, with: mentionPlaintext)
                    finalMentionAttributes.append(.init(
                        HydratedMentionAttribute.fromOriginalRange(
                            mention.range,
                            mentionAci: mention.value,
                            displayName: displayName
                        ),
                        range: NSRange(location: newMentionRange.location, length: finalMentionLength)
                    ))
                } else {
                    mentionOffsetDelta = 0
                }
            }
            rangeOffset += mentionOffsetDelta

            // We have to adjust style ranges for the active style
            if let style = styleAtCurrentIndex {
                if style.originalRange.upperBound <= mention.range.upperBound {
                    // If the style ended inside (or right at the end of) the mention,
                    // it should now end at the end of the replacement text.
                    let finalLength = (newMentionRange.location + finalMentionLength) - style.newRange.location
                    finalStyleAttributes.append(.init(
                        StyleAttribute.fromCollapsedStyle(style.style),
                        range: NSRange(
                            location: style.newRange.location,
                            length: finalLength
                        )
                    ))

                    // We are done with it, now.
                    styleAtCurrentIndex = nil
                } else {
                    // The original style ends past the mention; extend its
                    // length by the right amount, but keep it in
                    // the current styles being walked through.
                    styleAtCurrentIndex = .init(
                        originalRange: style.originalRange,
                        newRange: NSRange(
                            location: style.newRange.location,
                            length: style.newRange.length + mentionOffsetDelta
                        ),
                        style: style.style
                    )
                }
            }
        }

        if let style = styleAtCurrentIndex {
            // Styles that ran right to the end (or overran) should be finalized.
            let finalRange = NSRange(
                location: style.newRange.location,
                length: finalText.length - style.newRange.location
            )
            finalStyleAttributes.append(.init(
                StyleAttribute.fromCollapsedStyle(style.style),
                range: finalRange
            ))
        }

        self.hydratedText = finalText as String
        self.unhydratedMentions = unhydratedMentions
        self.styleAttributes = finalStyleAttributes
        self.mentionAttributes = finalMentionAttributes
    }

    // MARK: - Displaying as NSAttributedString

    public struct DisplayConfiguration {
        public let baseFont: UIFont
        public let baseTextColor: ThemedColor
        public let mention: MentionDisplayConfiguration
        public let style: StyleDisplayConfiguration

        public struct SearchRanges: Equatable {
            public let matchingBackgroundColor: ThemedColor
            public let matchingForegroundColor: ThemedColor
            public let matchedRanges: [NSRange]

            public init(
                matchingBackgroundColor: ThemedColor,
                matchingForegroundColor: ThemedColor,
                matchedRanges: [NSRange]
            ) {
                self.matchingBackgroundColor = matchingBackgroundColor
                self.matchingForegroundColor = matchingForegroundColor
                self.matchedRanges = matchedRanges
            }

            public func hashForSpoilerFrames(into hasher: inout Hasher) {
                hasher.combine(matchingBackgroundColor)
                hasher.combine(matchedRanges)
            }

            fileprivate static let configKey = NSAttributedString.Key("OWS.searchRange")

            public func apply(
                _ string: NSMutableAttributedString,
                isDarkThemeEnabled: Bool
            ) {
                for searchMatchRange in matchedRanges {
                    string.addAttributes(
                        [
                            .backgroundColor: matchingBackgroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled),
                            .foregroundColor: matchingForegroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled),
                            Self.configKey: self as Any
                        ],
                        range: searchMatchRange
                    )
                }
            }
        }

        public let searchRanges: SearchRanges?

        public init(
            baseFont: UIFont,
            baseTextColor: ThemedColor,
            mention: MentionDisplayConfiguration,
            style: StyleDisplayConfiguration,
            searchRanges: SearchRanges?
        ) {
            self.baseFont = baseFont
            self.baseTextColor = baseTextColor
            self.mention = mention
            self.style = style
            self.searchRanges = searchRanges
        }

        /**
         * Creates a new config using shared values.
         *
         * - parameter baseFont: Font to use for unstyled, non-mention text.
         * - parameter baseTextColor:
         * - parameter mentionFont: The font to use for mention text.
         *   If nil, baseFont is used.
         * - parameter mentionForegroundColor: The color to use for mention text.
         *   If nil, baseTextColor is used.
         * - parameter mentionBackgroundColor: The color to use to "highlight" mentions.
         *   If nil, no highlight is applied to mentions.
         * - parameter spoilerAnimationColorOverride: If set, animated spoiler particles
         *   will use this color instead of the baseTextColor.
         * - parameter revealedSpoilerBgColor: The color to use to "highlight" revealed spoilers.
         *   If nil, no highlight is applied to revealed spoilers.
         * - parameter revealAllSpoilers: If true, all spoilers will be revealed and
         *   `revealedSpoilerIds` will be ignored.
         * - parameter revealedSpoilerIds: IDs of spoiler ranges that should be revealed.
         *   Ignored if `revealAllSpoilers is true`.
         * - parameter searchRanges: Ranges to highlight as search results.
         */
        public init(
            baseFont: UIFont,
            baseTextColor: ThemedColor,
            mentionFont: UIFont? = nil,
            mentionForegroundColor: ThemedColor? = nil,
            mentionBackgroundColor: ThemedColor? = nil,
            spoilerAnimationColorOverride: ThemedColor? = nil,
            revealedSpoilerBgColor: ThemedColor? = nil,
            revealAllSpoilers: Bool = false,
            revealedSpoilerIds: Set<StyleIdType> = Set(),
            searchRanges: SearchRanges? = nil,
            useAnimatedSpoilers: Bool
        ) {
            self.init(
                baseFont: baseFont,
                baseTextColor: baseTextColor,
                mention: .init(
                    font: mentionFont ?? baseFont,
                    foregroundColor: mentionForegroundColor ?? baseTextColor,
                    backgroundColor: mentionBackgroundColor
                ),
                style: .init(
                    baseFont: baseFont,
                    textColor: baseTextColor,
                    spoilerAnimationColorOverride: spoilerAnimationColorOverride,
                    revealedSpoilerBgColor: revealedSpoilerBgColor,
                    revealAllIds: revealAllSpoilers,
                    revealedIds: revealedSpoilerIds,
                    useAnimatedSpoilers: useAnimatedSpoilers
                ),
                searchRanges: searchRanges
            )
        }

        public func hashForSpoilerFrames(into hasher: inout Hasher) {
            searchRanges?.hashForSpoilerFrames(into: &hasher)
            style.hashForSpoilerFrames(into: &hasher)
        }

        public var sizingCacheKey: String {
            return "\(baseFont.fontName)\(baseFont.pointSize)\(mention.font.fontName)\(mention.font.pointSize)\(style.baseFont.fontName)\(style.baseFont.pointSize)"
        }
    }

    /// If baseFont or baseTextColor are not provided, the values in the style display configuation are used.
    public func asAttributedStringForDisplay(
        config: DisplayConfiguration,
        baseFont: UIFont? = nil,
        baseTextColor: UIColor? = nil,
        textAlignment: NSTextAlignment? = nil,
        isDarkThemeEnabled: Bool
    ) -> NSAttributedString {
        let baseFont = baseFont ?? config.baseFont
        let baseTextColor = baseTextColor ?? config.baseTextColor.color(isDarkThemeEnabled: isDarkThemeEnabled)

        var baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseTextColor
        ]
        if let textAlignment {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = textAlignment
            baseAttributes[.paragraphStyle] = paragraphStyle
        }
        let string = NSMutableAttributedString(
            string: hydratedText,
            attributes: baseAttributes
        )
        return Self.applyAttributes(
            on: string,
            mentionAttributes: mentionAttributes,
            styleAttributes: styleAttributes,
            config: config,
            isDarkThemeEnabled: isDarkThemeEnabled
        )
    }

    internal static func applyAttributes(
        on string: NSMutableAttributedString,
        mentionAttributes: [NSRangedValue<HydratedMentionAttribute>],
        styleAttributes: [NSRangedValue<StyleAttribute>],
        config: HydratedMessageBody.DisplayConfiguration,
        isDarkThemeEnabled: Bool
    ) -> NSMutableAttributedString {
        // Start by removing the background color attribute on the
        // whole string. This is brittle but a big efficiency gain.

        // Consider the scenario where we have a mention under a spoiler
        // and reveal the spoiler.
        // The attributed string we get will have the spoiler background.
        // If we didn't have a mention, the style application would need
        // to wipe the background color in order to reveal; but if we do
        // have a mention doing so will clear the mention style too!

        // The most efficient solution is to always start by clearing
        // out the background, so that the revealed spoiler knows it can
        // do nothing, and it won't wipe the mention attribute.

        // This should be revisited in the future with a more complex solution
        // if there are more overlapping attributes; as of writing only the
        // background color is used by mentions and styles and search.
        string.removeAttribute(.backgroundColor, range: string.entireRange)

        mentionAttributes.forEach {
            $0.value.applyAttributes(
                to: string,
                at: $0.range,
                config: config.mention,
                isDarkThemeEnabled: isDarkThemeEnabled
            )
        }

        // Search takes priority over mentions, but not spoiler styles.
        config.searchRanges?.apply(string, isDarkThemeEnabled: isDarkThemeEnabled)

        styleAttributes.forEach {
            $0.value.applyAttributes(
                to: string,
                at: $0.range,
                config: config.style,
                searchRanges: config.searchRanges,
                isDarkThemeEnabled: isDarkThemeEnabled
            )
        }
        return string
    }

    // MARK: - Displaying as Plaintext

    public func asPlaintext() -> String {
        let mutableString = NSMutableString(string: hydratedText)
        // Reverse the sorted array so length changes that happen due to
        // replacement don't affect later ranges.
        styleAttributes.reversed().forEach {
            guard $0.value.style.contains(.spoiler) else {
                return
            }
            $0.value.applyPlaintextSpoiler(to: mutableString, at: $0.range)
        }
        return mutableString as String
    }

    // MARK: - Style-only (for stories)

    public func asStyleOnlyBody() -> StyleOnlyMessageBody {
        // Concept of "forwarding" is mentions only and therefore irrelevant;
        // we are really only mapping the styles here.
        return StyleOnlyMessageBody(messageBody: self.asMessageBodyForForwarding())
    }

    // MARK: - Forwarding

    public func asMessageBodyForForwarding(
        preservingAllMentions: Bool = false
    ) -> MessageBody {
        var mentionsDict = [NSRange: Aci]()
        unhydratedMentions.forEach {
            mentionsDict[$0.range] = $0.value.mentionAci
        }
        if preservingAllMentions {
            mentionAttributes.forEach {
                mentionsDict[$0.range] = $0.value.mentionAci
            }
        }

        return MessageBody(
            text: hydratedText,
            ranges: MessageBodyRanges(
                mentions: mentionsDict,
                styles: Self.flattenStylesPreservingSharedIds(styleAttributes)
            )
        )
    }

    // MARK: - Editing

    internal func asEditableMessageBody() -> EditableMessageBodyTextStorage.Body {
        var mentions = [NSRange: Aci]()
        self.mentionAttributes.forEach {
            mentions[$0.range] = $0.value.mentionAci
        }
        self.unhydratedMentions.forEach {
            mentions[$0.range] = $0.value.mentionAci
        }
        var flattenedStyles = [NSRangedValue<SingleStyle>]()
        var runningStyles = [SingleStyle: (StyleIdType, NSRange)]()

        styleAttributes.forEach { (styleAttribute: NSRangedValue<StyleAttribute>) in
            SingleStyle.allCases.forEach { style in
                guard styleAttribute.value.style.contains(style: style), let id = styleAttribute.value.ids[style] else {
                    return
                }
                if let runningStyle: (StyleIdType, NSRange) = runningStyles[style] {
                    // Append to the running style.
                    if runningStyle.0 == id {
                        runningStyles[style] = (id, runningStyle.1.union(styleAttribute.range))
                    } else {
                        flattenedStyles.append(.init(style, range: runningStyle.1))
                        runningStyles[style] = (id, styleAttribute.range)
                    }
                } else {
                    runningStyles[style] = (id, styleAttribute.range)
                }
            }
        }
        flattenedStyles.append(contentsOf: runningStyles
            .map({ style, values in
                return NSRangedValue<SingleStyle>(style, range: values.1)
            })
        )
        flattenedStyles.sort(by: { $0.range.location < $1.range.location })
        return .init(
            hydratedText: hydratedText,
            mentions: mentions,
            flattenedStyles: flattenedStyles
        )
    }

    // MARK: - Adding prefix

    public func addingPrefix(_ prefix: String) -> HydratedMessageBody {
        return addingStyledPrefix(.init(plaintext: prefix))
    }

    public func addingStyledPrefix(_ prefix: StyleOnlyMessageBody) -> HydratedMessageBody {
        let offset = (prefix.text as NSString).length
        let prefixStyles: [NSRangedValue<StyleAttribute>] = prefix.collapsedStyles.map {
            return .init(.fromCollapsedStyle($0.value), range: $0.range)
        }
        return HydratedMessageBody(
            hydratedText: prefix.text + hydratedText,
            unhydratedMentions: unhydratedMentions.map { $0.offset(by: offset) },
            mentionAttributes: mentionAttributes.map { $0.offset(by: offset) },
            styleAttributes: prefixStyles + styleAttributes.map { $0.offset(by: offset) }
        )
    }

    public var nilIfEmpty: HydratedMessageBody? {
        if self.hydratedText.isEmpty {
            return nil
        }
        return self
    }

    // MARK: - Truncation

    private struct TruncationLength {
        // Length defined by displayed grapheme clusters.
        // What you get from String.count
        let graphemeClusterCount: Int
        // Length defined by utf16 characters.
        // What you get from NSString.length or String.utf16.count
        let utf16Count: Int
    }

    /// NOTE: if there is a mention at the truncation point, we instead truncate sooner
    /// so as to not cut off mid-mention.
    public func truncating(
        desiredLength rawDesiredLength: Int,
        truncationSuffix: String
    ) -> HydratedMessageBody {
        // Input is defined in grapheme clusters (doesn't cut emoji off)
        // but mentions and styles are defined in utf16 character counts.
        let desiredLength = TruncationLength(
            graphemeClusterCount: rawDesiredLength,
            utf16Count: hydratedText.prefix(rawDesiredLength).utf16.count
        )

        var possibleOverlappingMention: NSRange?
        for mentionAttribute in self.mentionAttributes {
            if mentionAttribute.range.contains(desiredLength.utf16Count) {
                possibleOverlappingMention = mentionAttribute.range
                break
            }
            if mentionAttribute.range.location > desiredLength.utf16Count {
                // mentions are ordered; can early exit if we pass it.
                break
            }
        }

        // There's a mention overlapping our normal truncate point, we want to truncate sooner
        // so we don't "split" the mention.
        var finalLength = desiredLength
        if let possibleOverlappingMention, possibleOverlappingMention.location < desiredLength.utf16Count {
            // This would truncate in the middle of a grapheme cluster if the mention
            // starts in the middle of one. That should be impossible, though.
            finalLength = TruncationLength(
                graphemeClusterCount: (hydratedText as NSString).substring(to: possibleOverlappingMention.location).count,
                utf16Count: possibleOverlappingMention.location
            )
        }

        var mentionHydrationStrings = [Aci: String]()
        let mentions = self.mentionAttributes.filter({
            guard $0.range.location < finalLength.utf16Count else {
                return false
            }
            mentionHydrationStrings[$0.value.mentionAci] = $0.value.displayName
            return true
        })
        let unhydratedMentions = self.unhydratedMentions.filter { $0.range.upperBound <= finalLength.utf16Count }
        let styles = self.styleAttributes.compactMap { (styleAttribute) -> NSRangedValue<StyleAttribute>? in
            if styleAttribute.range.location > finalLength.utf16Count {
                return nil
            } else if styleAttribute.range.upperBound <= finalLength.utf16Count {
                return styleAttribute
            } else {
                return .init(
                    styleAttribute.value,
                    range: NSRange(
                        location: styleAttribute.range.location,
                        length: finalLength.utf16Count - styleAttribute.range.location
                    )
                )
            }
        }

        let newSelf = HydratedMessageBody(
            hydratedText: String(hydratedText.prefix(finalLength.graphemeClusterCount)) + truncationSuffix,
            unhydratedMentions: unhydratedMentions,
            mentionAttributes: mentions,
            styleAttributes: styles
        )
        // Strip. It's less efficient but avoids code repetition to go through message body.
        return newSelf
            .asMessageBodyForForwarding(preservingAllMentions: true)
            .filterStringForDisplay()
            .hydrating(mentionHydrator: { mentionAci in
                guard let string = mentionHydrationStrings[mentionAci] else {
                    return .preserveMention
                }
                return .hydrate(string)
            })
    }

    // MARK: - Spoiler Ranges

    public var hasSpoilerRangesToAnimate: Bool {
        return styleAttributes.contains(where: { $0.value.style.contains(style: .spoiler) })
    }

    public struct AnimatableSpoilerRange {
        public let range: NSRange
        public let color: ThemedColor
        public let isSearchResult: Bool
    }

    public func spoilerRangesForAnimation(
        config: DisplayConfiguration
    ) -> [AnimatableSpoilerRange] {
        // We want to collapse adjacent ranges because they should
        // all animate together even if they are distinct ranges
        // for the purposes of revealing. Otherwise we'd get
        // abrupt boundaries.
        var finalRanges = [NSRange]()
        var ongoingRange: NSRange?
        for styleAttribute in styleAttributes {
            guard
                styleAttribute.value.style.contains(style: .spoiler),
                let spoilerId = styleAttribute.value.ids[.spoiler],
                !(config.style.revealAllIds || config.style.revealedIds.contains(spoilerId))
            else {
                continue
            }
            guard let currentRange = ongoingRange else {
                ongoingRange = styleAttribute.range
                continue
            }
            if currentRange.upperBound >= styleAttribute.range.location {
                ongoingRange = currentRange.union(styleAttribute.range)
            } else {
                finalRanges.append(currentRange)
                ongoingRange = styleAttribute.range
            }
        }
        if let ongoingRange {
            finalRanges.append(ongoingRange)
        }

        guard let searchConfig = config.searchRanges, !searchConfig.matchedRanges.isEmpty else {
            return finalRanges.map { .init(range: $0, color: config.style.spoilerColor, isSearchResult: false) }
        }

        var coloredRanges = [AnimatableSpoilerRange]()
        for spoilerRange in finalRanges {
            var remainingSpoilerRange = spoilerRange
            searchRangeLoop: for searchRange in searchConfig.matchedRanges {
                if let intersection = remainingSpoilerRange.intersection(searchRange), intersection.length > 0 {
                    // First add any part of the spoiler range before the search range.
                    if remainingSpoilerRange.location < intersection.location {
                        coloredRanges.append(.init(
                            range: NSRange(
                                location: remainingSpoilerRange.location,
                                length: intersection.location - remainingSpoilerRange.location
                            ),
                            color: config.style.spoilerColor,
                            isSearchResult: false
                        ))
                    }
                    // The overlapping part gets the search config's color.
                    coloredRanges.append(
                        .init(range: intersection, color: searchConfig.matchingBackgroundColor, isSearchResult: true)
                    )
                    if spoilerRange.upperBound <= intersection.upperBound {
                        break searchRangeLoop
                    } else {
                        remainingSpoilerRange = NSRange(
                            location: intersection.upperBound,
                            length: remainingSpoilerRange.upperBound - intersection.upperBound
                        )
                    }
                } else if searchRange.location >= remainingSpoilerRange.upperBound {
                    break searchRangeLoop
                } else {
                    continue
                }
            }
            if remainingSpoilerRange.length > 0 {
                coloredRanges.append(.init(range: remainingSpoilerRange, color: config.style.spoilerColor, isSearchResult: false))
            }
        }
        return coloredRanges
    }

    // MARK: - Tappable items

    public enum TappableItem {
        public struct Mention {
            public let range: NSRange
            public let mentionAci: Aci
        }

        public struct UnrevealedSpoiler {
            public let range: NSRange
            public let id: StyleIdType
        }

        case mention(Mention)
        case unrevealedSpoiler(UnrevealedSpoiler)
        case data(TextCheckingDataItem)
    }

    public func tappableItems(
        revealedSpoilerIds: Set<Int>,
        dataDetector: NSDataDetector?
    ) -> [TappableItem] {
        return Self.tappableItems(
            text: hydratedText,
            mentionAttributes: mentionAttributes,
            styleAttributes: styleAttributes,
            revealedSpoilerIds: revealedSpoilerIds,
            dataDetector: dataDetector
        )
    }

    internal static func tappableItems(
        text: String,
        mentionAttributes: [NSRangedValue<HydratedMentionAttribute>],
        styleAttributes: [NSRangedValue<StyleAttribute>],
        revealedSpoilerIds: Set<Int>,
        dataDetector: NSDataDetector?
    ) -> [TappableItem] {
        // We "cheat" by using NSAttributedString to deal with overlapping
        // ranges for us. We add our items and their ranges as attributes,
        // then enumerate attributes to deal with overlaps.
        let attrString = NSMutableAttributedString(string: "")

        func setRange(
            value: Any,
            key: NSAttributedString.Key,
            range: NSRange
        ) {
            if range.upperBound > attrString.length {
                attrString.append(String(repeating: " ", count: range.upperBound - attrString.length))
            }
            attrString.addAttribute(key, value: value, range: range)
        }

        // These are used in a string tied to the scope of this
        // function; no need to be too careful about them.
        let unrevealedSpoilerKey = NSAttributedString.Key("ows.spoiler")
        let mentionKey = NSAttributedString.Key("ows.mention")
        let dataKey = NSAttributedString.Key("ows.data")

        styleAttributes.forEach {
            if
                $0.value.style.contains(.spoiler),
                let spoilerId = $0.value.ids[.spoiler],
                revealedSpoilerIds.contains(spoilerId).negated
            {
                setRange(
                    value: TappableItem.UnrevealedSpoiler(range: $0.range, id: spoilerId),
                    key: unrevealedSpoilerKey,
                    range: $0.range
                )
            }
        }
        mentionAttributes.forEach {
            setRange(
                value: TappableItem.Mention(range: $0.range, mentionAci: $0.value.mentionAci),
                key: mentionKey,
                range: $0.range
            )
        }

        let dataItems = TextCheckingDataItem.detectedItems(in: text, using: dataDetector)
        dataItems.forEach {
            setRange(
                value: $0,
                key: dataKey,
                range: $0.range
            )
        }

        var items = [TappableItem]()
        attrString.enumerateAttributes(in: attrString.entireRange) { attrs, range, _ in
            // Spoilers are highest priority; if we have those, stick with them.
            // Then comes mentions and last data items.
            // The attributed string will have split out overlapping subranges for us.
            if let unrevealedSpoiler = attrs[unrevealedSpoilerKey] as? TappableItem.UnrevealedSpoiler {
                items.append(.unrevealedSpoiler(.init(range: range, id: unrevealedSpoiler.id)))
            } else if let mention = attrs[mentionKey] as? TappableItem.Mention {
                items.append(.mention(.init(range: range, mentionAci: mention.mentionAci)))
            } else if let dataItem = attrs[dataKey] as? TextCheckingDataItem {
                items.append(.data(dataItem.copyInNewRange(range)))
            }
        }

        return items
    }

    // MARK: - Regex

    public func matches(for regex: NSRegularExpression) -> [NSRange] {
        return regex.matches(
            in: hydratedText,
            options: [.withoutAnchoringBounds],
            range: hydratedText.entireRange
        ).map(\.range)
    }

    // MARK: - DisplayableText

    // This misdirection is because we do not want to expose hydratedText externally;
    // that makes it very easy to misuse this class as just a plaintext string.

    public var rawTextLength: Int { (hydratedText as NSString).length }

    public var accessibilityDescription: String { hydratedText }

    public var debugDescription: String { hydratedText }

    public var utterance: AVSpeechUtterance { AVSpeechUtterance(string: hydratedText) }

    // Used for caching sizing information, so we need to cache attributes since
    // monospace affects sizing.
    public var cacheKey: String { hydratedText.description + styleAttributes.description }

    public var naturalTextAlignment: NSTextAlignment { hydratedText.naturalTextAlignment }

    public func jumbomojiCount(_ jumbomojiCounter: (String) -> UInt) -> UInt {
        if hasSpoilerRangesToAnimate {
            // Never jumbomoji anything with a spoiler in it.
            return 0
        }
        return jumbomojiCounter(hydratedText)
    }

    public func fullLengthWithNewLineScalar(_ parser: (String) -> Int) -> Int {
        return parser(hydratedText)
    }

    public func shouldAllowLinkification(
        linkDetector: NSDataDetector,
        isValidLink: (String) -> Bool
    ) -> Bool {
        guard LinkValidator.canParseURLs(in: hydratedText) else {
            return false
        }

        for match in linkDetector.matches(in: hydratedText, options: [], range: hydratedText.entireRange) {
            guard match.url != nil else {
                continue
            }

            // We extract the exact text from the `fullText` rather than use match.url.host
            // because match.url.host actually escapes non-ascii domains into puny-code.
            //
            // But what we really want is to check the text which will ultimately be presented to
            // the user.
            let rawTextOfMatch = (hydratedText as NSString).substring(with: match.range)
            guard isValidLink(rawTextOfMatch) else {
                return false
            }
        }
        return true
    }

    // MARK: - Helpers

    internal static func flattenStylesPreservingSharedIds(_ styleAttributes: [NSRangedValue<StyleAttribute>]) -> [NSRangedValue<SingleStyle>] {
        var styleIdToIndex = [StyleIdType: Int]()
        var styles = [NSRangedValue<MessageBodyRanges.SingleStyle>]()
        for styleAttribute in styleAttributes {
            for singleStyle in styleAttribute.value.style.contents {
                let styleId = styleAttribute.value.ids[singleStyle]
                if
                    let styleId,
                    let styleIndexToJoinInto = styleIdToIndex[styleId],
                    let styleToJoinInto = styles[safe: styleIndexToJoinInto],
                    styleToJoinInto.value == singleStyle,
                    styleToJoinInto.range.upperBound == styleAttribute.range.location
                {
                    // Merge into an existing range with the same id.
                    styles[styleIndexToJoinInto] = .init(singleStyle, range: styleToJoinInto.range.union(styleAttribute.range))
                } else {
                    if let styleId {
                        styleIdToIndex[styleId] = styles.count
                    }
                    styles.append(.init(singleStyle, range: styleAttribute.range))
                }

            }
        }
        return styles
    }
}
