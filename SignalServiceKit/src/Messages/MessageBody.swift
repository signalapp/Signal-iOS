//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objcMembers
public class MessageBody: NSObject, NSCopying, NSSecureCoding {

    typealias Style = MessageBodyRanges.Style

    public static var supportsSecureCoding = true
    public static let mentionPlaceholder = "\u{FFFC}" // Object Replacement Character

    public let text: String
    public let ranges: MessageBodyRanges
    public var hasMentions: Bool { ranges.hasMentions }

    public init(text: String, ranges: MessageBodyRanges) {
        self.text = text
        self.ranges = ranges
    }

    public required init?(coder: NSCoder) {
        guard let text = coder.decodeObject(of: NSString.self, forKey: "text") as String? else {
            owsFailDebug("Missing text")
            return nil
        }

        guard let ranges = coder.decodeObject(of: MessageBodyRanges.self, forKey: "ranges") else {
            owsFailDebug("Missing ranges")
            return nil
        }

        self.text = text
        self.ranges = ranges
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return MessageBody(text: text, ranges: ranges)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(text, forKey: "text")
        coder.encode(ranges, forKey: "ranges")
    }

    // TODO[TextFormatting]: "plaintext" here is misleading; depending on usage we may
    // want to apply some styles.
    public func plaintextBody(transaction: GRDBReadTransaction) -> String {
        let hydratedMessageBody = hydratingMentions(hydrator: { mentionUUID in
            return .hydrate(
                Self.contactsManager.displayName(
                    for: SignalServiceAddress(uuid: mentionUUID),
                    transaction: transaction.asAnyRead
                ),
                alreadyIncludesPrefix: false
            )
        })
        return (hydratedMessageBody.text as NSString).filterStringForDisplay()
    }

    public func forNewContext(
        _ context: TSThread,
        transaction: GRDBReadTransaction
    ) -> MessageBody {
        guard hasMentions else {
            return self
        }

        let isGroupThread: Bool
        let recipientAddresses: Set<SignalServiceAddress>
        if let groupThread = context as? TSGroupThread, groupThread.isGroupV2Thread {
            isGroupThread = true
            recipientAddresses = Set(groupThread.recipientAddresses(with: transaction.asAnyRead))
        } else {
            isGroupThread = false
            recipientAddresses = .init()
        }

        return hydratingMentions(hydrator: { mentionUuid in
            let address = SignalServiceAddress(uuid: mentionUuid)
            if isGroupThread, recipientAddresses.contains(address) {
                // We don't want to hydrate for mentions in the destination group;
                // these can be hydrated on the fly with group member information.
                // Those not in the group are hydrated with a snapshot of their
                // contact info that we have; the other group members might not
                // even know about them.
                return .preserveMention
            } else {
                let displayName = Self.contactsManager.displayName(
                    for: address,
                    transaction: transaction.asAnyRead
                )
                return .hydrate(displayName, alreadyIncludesPrefix: false)
            }
        })
    }

    internal func hydratingMentions(
        hydrator: (UUID) -> MessageBodyRanges.MentionHydrationOption,
        isRTL: Bool = CurrentAppContext().isRTL
    ) -> MessageBody {
        let text = NSMutableAttributedString(string: self.text)
        let ranges = ranges.hydratingMentions(
            in: text,
            hydrator: hydrator,
            isRTL: isRTL
        )
        return MessageBody(text: text.string, ranges: ranges)
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MessageBody else {
            return false
        }
        guard text == other.text else {
            return false
        }
        guard ranges == other.ranges else {
            return false
        }
        return true
    }
}

@objcMembers
public class MessageBodyRanges: NSObject, NSCopying, NSSecureCoding {
    public static var supportsSecureCoding = true
    public static let mentionPrefix = "@"
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

    // TODO[TextFormatting]: "plaintext" here is misleading; depending on usage we may
    // want to apply some styles.
    public func plaintextBody(text: String, transaction: GRDBReadTransaction) -> String {
        return MessageBody(text: text, ranges: self).plaintextBody(transaction: transaction)
    }

    public enum MentionHydrationOption {
        /// Do not hydrate the mention; this leaves the string as it was in the original,
        /// which we want to do e.g. when forwarding a message with mentions from one
        /// thread context to another, where we hydrate the mentions of members not in
        /// the destination, but preserve mentions of shared members fully intact.
        case preserveMention
        /// Replace the mention range with the populated display name.
        case hydrate(String, alreadyIncludesPrefix: Bool)
        /// Replace the mention range with the populated display name and attributes.
        case hydrateAttributed(NSAttributedString, alreadyIncludesPrefix: Bool)
    }

    /// Hydrates mentions (as determined by the hydrator) and sets the `.owsStyle` attribute
    /// on the string for any styles but *does not* actually apply the styles. (e.g. no font attribute)
    /// `.owsStyle` attributes can be converted to attributes just before display, when the font
    /// and text color are available.
    public func hydrateMentionsAndSetStyleAttributes(
        on string: NSMutableAttributedString,
        hydrator: (UUID) -> MentionHydrationOption,
        isRTL: Bool = CurrentAppContext().isRTL
    ) {
        let newStyles = hydratingMentions(
            in: string,
            hydrator: hydrator,
            isRTL: isRTL
        )
        newStyles.setStyleAttributesWithoutApplying(on: string)
    }

    /// Applies hydrations to the provided `NSMutableAttributedString`, and returns any
    /// ranges left over (styles and preserved mentions) with ranges updated to reflect the new string.
    public func hydratingMentions(
        in text: NSMutableAttributedString,
        hydrator: (UUID) -> MentionHydrationOption,
        isRTL: Bool = CurrentAppContext().isRTL
    ) -> MessageBodyRanges {
        guard hasMentions else {
            return self
        }

        let finalText = text
        var finalMentions = [NSRange: UUID]()
        var finalStyles = [(NSRange, Style)]()

        var mentionsInOriginal = orderedMentions
        var stylesInOriginal = styles

        var rangeOffset = 0

        struct ProcessingStyle {
            let originalRange: NSRange
            let newRange: NSRange
            let style: Style
        }
        var styleAtCurrentIndex: ProcessingStyle?

        let startLength = text.length
        for currentIndex in 0..<startLength {
            // If we are past the end, apply the active style to the final result
            // and drop.
            if
                let style = styleAtCurrentIndex,
                currentIndex >= style.originalRange.upperBound
            {
                finalStyles.append((style.newRange, style.style))
                styleAtCurrentIndex = nil
            }
            // Check for any new styles starting at the current index.
            if stylesInOriginal.first?.0.contains(currentIndex) == true {
                let (originalRange, style) = stylesInOriginal.removeFirst()
                styleAtCurrentIndex = .init(
                    originalRange: originalRange,
                    newRange: NSRange(
                        location: originalRange.location + rangeOffset,
                        length: originalRange.length
                    ),
                    style: style
                )
            }

            // Check for any mentions at the current index.
            // Mentions can't overlap, so we don't need a while loop to check for multiple.
            guard
                let (originalMentionRange, mentionUuid) = mentionsInOriginal.first,
                (
                    originalMentionRange.contains(currentIndex)
                    || originalMentionRange.location == currentIndex
                )
            else {
                // No mentions, so no additional logic needed, just go to the next index.
                continue
            }
            mentionsInOriginal.removeFirst()

            let newMentionRange = NSRange(
                location: originalMentionRange.location + rangeOffset,
                length: originalMentionRange.length
            )

            let finalMentionLength: Int
            let mentionOffsetDelta: Int
            switch hydrator(mentionUuid) {
            case .preserveMention:
                // Preserve the mention without replacement and proceed.
                finalMentions[newMentionRange] = mentionUuid
                continue
            case let .hydrate(displayName, alreadyIncludesPrefix):
                let mentionPlaintext: String
                if alreadyIncludesPrefix {
                    mentionPlaintext = displayName
                } else {
                    if isRTL {
                        mentionPlaintext = displayName + MessageBodyRanges.mentionPrefix
                    } else {
                        mentionPlaintext = MessageBodyRanges.mentionPrefix + displayName
                    }
                }
                finalMentionLength = (mentionPlaintext as NSString).length
                mentionOffsetDelta = finalMentionLength - originalMentionRange.length
                finalText.replaceCharacters(in: newMentionRange, with: mentionPlaintext)
            case let .hydrateAttributed(displayName, alreadyIncludesPrefix):
                let mentionString: NSAttributedString
                if alreadyIncludesPrefix {
                    mentionString = displayName
                } else {
                    let base = NSMutableAttributedString(attributedString: displayName)
                    let replacement = NSAttributedString(string: MessageBodyRanges.mentionPrefix)
                    if isRTL {
                        base.replaceCharacters(in: NSRange(location: 0, length: 0), with: replacement)
                    } else {
                        base.replaceCharacters(in: NSRange(location: base.length, length: 0), with: replacement)
                    }
                    mentionString = base
                }
                finalMentionLength = mentionString.length
                mentionOffsetDelta = finalMentionLength - originalMentionRange.length
                finalText.replaceCharacters(in: newMentionRange, with: mentionString)
            }
            rangeOffset += mentionOffsetDelta

            // We have to adjust style ranges for the active style
            if let style = styleAtCurrentIndex {
                if style.originalRange.upperBound <= originalMentionRange.upperBound {
                    // If the style ended inside (or right at the end of) the mention,
                    // it should now end at the end of the replacement text.

                    let finalLength = (newMentionRange.location + finalMentionLength) - style.newRange.location
                    let finalStyle = (
                        NSRange(
                            location: style.newRange.location,
                            length: finalLength
                        ),
                        style.style
                    )
                    finalStyles.append(finalStyle)

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
            let finalStyle = (
                NSRange(
                    location: style.newRange.location,
                    length: finalText.length - style.newRange.location
                ),
                style.style
            )
            finalStyles.append(finalStyle)
        }

        return MessageBodyRanges(
            mentions: finalMentions,
            styles: finalStyles
        )
    }

    /// Sets the `.owsStyle` attribute on the string for any styles but
    /// *does not* actually apply the styles. (e.g. no font attribute)
    /// `.owsStyle` attributes can be converted to attributes just before display,
    /// when the font and text color are available.
    public func setStyleAttributesWithoutApplying(on string: NSMutableAttributedString) {
        for (range, style) in styles {
            string.addAttributes([.owsStyle: style], range: range)
        }
    }

    public enum SpoilerStyle {
        case revealed
        // TODO[TextFormatting]: instead of highlight, we should use
        // a fancy animation which won't be represented in attributes.
        case concealedWithHighlight(UIColor)
        // TODO[TextFormatting]: add concealed with characters option
    }

    /// Applies styles to the provided string (sets attributes for font, strikethrough, etc).
    /// Font and colors for styles are based on the provided base font and color.
    public func applyStyles(
        to string: NSMutableAttributedString,
        baseFont: UIFont,
        textColor: UIColor,
        spoilerStyler: (Int, NSRange) -> SpoilerStyle
    ) {
        var spoilerCount = 0
        for (range, style) in styles {
            Self.applyStyle(
                style: style,
                to: string,
                range: range,
                baseFont: baseFont,
                textColor: textColor,
                spoilerStyler: spoilerStyler,
                spoilerCount: &spoilerCount
            )
        }
    }

    /// Applies any `.owsStyle` attributes on the string (sets attributes for font, strikethrough, etc).
    /// Font and colors for styles are based on the provided base font and color.
    public static func applyStyleAttributes(
        on string: NSMutableAttributedString,
        baseFont: UIFont,
        textColor: UIColor,
        spoilerStyler: (Int, NSRange) -> SpoilerStyle
    ) {
        let copy = NSAttributedString(attributedString: string)
        var spoilerCount = 0
        copy.enumerateAttributes(
            in: string.entireRange,
            using: { attrs, range, stop in
                guard let style = attrs[.owsStyle] as? Style else {
                    return
                }
                applyStyle(
                    style: style,
                    to: string,
                    range: range,
                    baseFont: baseFont,
                    textColor: textColor,
                    spoilerStyler: spoilerStyler,
                    spoilerCount: &spoilerCount
                )
            }
        )
    }

    private static func applyStyle(
        style: Style,
        to string: NSMutableAttributedString,
        range: NSRange,
        baseFont: UIFont,
        textColor: UIColor,
        spoilerStyler: (Int, NSRange) -> SpoilerStyle,
        spoilerCount: inout Int
    ) {
        var fontTraits: UIFontDescriptor.SymbolicTraits = []
        var attributes: [NSAttributedString.Key: Any] = [
            .owsStyle: style
        ]
        if style.contains(.bold) {
            fontTraits.insert(.traitBold)
        }
        if style.contains(.italic) {
            fontTraits.insert(.traitItalic)
        }
        if style.contains(.monospace) {
            fontTraits.insert(.traitMonoSpace)
        }
        if style.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = textColor
        }
        if style.contains(.spoiler) {
            switch spoilerStyler(spoilerCount, range) {
            case .revealed:
                break
            case .concealedWithHighlight(let highlightColor):
                attributes[.backgroundColor] = highlightColor
            }
            spoilerCount += 1
        }
        if !fontTraits.isEmpty {
            attributes[.font] = baseFont.withTraits(fontTraits)
        }
        string.addAttributes(attributes, range: range)
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

extension UIFont {

    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {

        // create a new font descriptor with the given traits
        guard let fd = fontDescriptor.withSymbolicTraits(traits) else {
            // the given traits couldn't be applied, return self
            return self
        }

        // return a new font with the created font descriptor
        return UIFont(descriptor: fd, size: pointSize)
    }
}

extension NSAttributedString.Key {
    public static let owsStyle = MessageBodyRanges.Style.attributedStringKey
}
