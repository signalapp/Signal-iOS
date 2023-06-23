//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The result of stripping, filtering, and hydrating mentions in a `MessageBody`.
/// This object can be held durably in memory as a way to cache mention hydrations
/// and other expensive string operations, and can subsequently be transformed
/// into string and attributed string values for display.
public class HydratedMessageBody: Equatable, Hashable {

    public typealias Style = MessageBodyRanges.Style
    public typealias SingleStyle = MessageBodyRanges.SingleStyle
    public typealias CollapsedStyle = MessageBodyRanges.CollapsedStyle

    private let hydratedText: String
    private let unhydratedMentions: [NSRangedValue<MentionAttribute>]
    private let mentionAttributes: [NSRangedValue<MentionAttribute>]
    private let styleAttributes: [NSRangedValue<StyleAttribute>]

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
        unhydratedMentions: [NSRangedValue<MentionAttribute>] = [],
        mentionAttributes: [NSRangedValue<MentionAttribute>],
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
        var unhydratedMentions = [NSRangedValue<MentionAttribute>]()
        var finalStyleAttributes = [NSRangedValue<StyleAttribute>]()
        var finalMentionAttributes = [NSRangedValue<MentionAttribute>]()

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
                    MentionAttribute.fromOriginalRange(mention.range, mentionUuid: mention.value),
                    range: newMentionRange
                ))
                continue
            case let .hydrate(displayName):
                let mentionPlaintext: String
                if isRTL {
                    mentionPlaintext = displayName + MentionAttribute.mentionPrefix
                } else {
                    mentionPlaintext = MentionAttribute.mentionPrefix + displayName
                }
                finalMentionLength = (mentionPlaintext as NSString).length
                // Make sure we don't have any illegal mention ranges; if so skip them.
                if newMentionRange.upperBound <= finalText.length {
                    mentionOffsetDelta = finalMentionLength - mention.range.length
                    finalText.replaceCharacters(in: newMentionRange, with: mentionPlaintext)
                    finalMentionAttributes.append(.init(
                        MentionAttribute.fromOriginalRange(mention.range, mentionUuid: mention.value),
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

        self.hydratedText = finalText.stringOrNil ?? ""
        self.unhydratedMentions = unhydratedMentions
        self.styleAttributes = finalStyleAttributes
        self.mentionAttributes = finalMentionAttributes
    }

    // MARK: - Displaying as NSAttributedString

    public struct DisplayConfiguration {
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
        }

        public let searchRanges: SearchRanges?

        public init(
            mention: MentionDisplayConfiguration,
            style: StyleDisplayConfiguration,
            searchRanges: SearchRanges?
        ) {
            self.mention = mention
            self.style = style
            self.searchRanges = searchRanges
        }
    }

    public func asAttributedStringForDisplay(
        config: DisplayConfiguration,
        baseAttributes: [NSAttributedString.Key: Any]? = nil,
        isDarkThemeEnabled: Bool
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(string: hydratedText, attributes: baseAttributes ?? [:])
        return Self.applyAttributes(
            on: string,
            mentionAttributes: mentionAttributes,
            styleAttributes: styleAttributes,
            config: config,
            isDarkThemeEnabled: isDarkThemeEnabled
        )
    }

    private static let searchRangeConfigKey = NSAttributedString.Key("OWS.searchRange")

    internal static func applyAttributes(
        on string: NSMutableAttributedString,
        mentionAttributes: [NSRangedValue<MentionAttribute>],
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
        if let searchRanges = config.searchRanges {
            for searchMatchRange in searchRanges.matchedRanges {
                string.addAttributes(
                    [
                        .backgroundColor: searchRanges.matchingBackgroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled),
                        .foregroundColor: searchRanges.matchingForegroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled),
                        Self.searchRangeConfigKey: config.searchRanges as Any
                    ],
                    range: searchMatchRange
                )
            }
        }

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

    internal static func extractSearchRangeConfigFromAttributes(
        _ attrs: [NSAttributedString.Key: Any]
    ) -> DisplayConfiguration.SearchRanges? {
        return attrs[Self.searchRangeConfigKey] as? DisplayConfiguration.SearchRanges
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

    public func asMessageBodyForForwarding() -> MessageBody {
        var unhydratedMentionsDict = [NSRange: UUID]()
        unhydratedMentions.forEach {
            unhydratedMentionsDict[$0.range] = $0.value.mentionUuid
        }

        return MessageBody(
            text: hydratedText,
            ranges: MessageBodyRanges(
                mentions: unhydratedMentionsDict,
                styles: Self.flattenStylesPreservingSharedIds(styleAttributes)
            )
        )
    }

    // MARK: - Editing

    internal func asEditableMessageBody() -> EditableMessageBodyTextStorage.Body {
        var mentions = [NSRange: UUID]()
        self.mentionAttributes.forEach {
            mentions[$0.range] = $0.value.mentionUuid
        }
        self.unhydratedMentions.forEach {
            mentions[$0.range] = $0.value.mentionUuid
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
        let offset = (prefix as NSString).length
        return HydratedMessageBody(
            hydratedText: prefix + hydratedText,
            unhydratedMentions: unhydratedMentions.map { $0.offset(by: offset) },
            mentionAttributes: mentionAttributes.map { $0.offset(by: offset) },
            styleAttributes: styleAttributes.map { $0.offset(by: offset) }
        )
    }

    public var nilIfEmpty: HydratedMessageBody? {
        if self.hydratedText.isEmpty {
            return nil
        }
        return self
    }

    // MARK: - Tappable items

    public enum TappableItem {
        public struct Mention {
            public let range: NSRange
            public let mentionUuid: UUID
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
        mentionAttributes: [NSRangedValue<MentionAttribute>],
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
                value: TappableItem.Mention(range: $0.range, mentionUuid: $0.value.mentionUuid),
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
                items.append(.mention(.init(range: range, mentionUuid: mention.mentionUuid)))
            } else if let dataItem = attrs[dataKey] as? TextCheckingDataItem {
                items.append(.data(dataItem.copyInNewRange(range)))
            }
        }

        return items
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

fileprivate extension NSRangedValue {

    func offset(by offset: Int) -> Self {
        return Self.init(
            value,
            range: NSRange(
                location: self.range.location + offset,
                length: self.range.length
            )
        )
    }
}
