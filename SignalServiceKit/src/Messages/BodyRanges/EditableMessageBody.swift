//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol EditableMessageBodyDelegate: AnyObject {

    func editableMessageBodyHydrator(tx: DBReadTransaction) -> MentionHydrator

    func editableMessageSelectedRange() -> NSRange

    func editableMessageBodyDidRequestNewSelectedRange(_ newSelectedRange: NSRange)

    func editableMessageBodyDisplayConfig() -> HydratedMessageBody.DisplayConfiguration

    func isEditableMessageBodyDarkThemeEnabled() -> Bool

    // If this key changes, the cached mentions will be invalidated at read-time.
    func mentionCacheInvalidationKey() -> String
}

public class EditableMessageBodyTextStorage: NSTextStorage {

    public typealias Style = MessageBodyRanges.Style
    public typealias SingleStyle = MessageBodyRanges.SingleStyle

    /// Abstraction so callers can either provide an already-open transaction or allow
    /// opening a new transaction.
    public typealias ReadTxProvider = ((DBReadTransaction) -> Void) -> Void

    // MARK: - Init

    // DB reference so we can hydrate mentions.
    private let db: DB

    public weak var editableBodyDelegate: EditableMessageBodyDelegate?

    public init(
        db: DB
    ) {
        self.db = db
        super.init()
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        owsFail("Use another initializer")
    }

    // MARK: - NSTextStorage

    public override var string: String {
        return body.hydratedText
    }

    public var naturalTextAlignment: NSTextAlignment {
        guard body.hydratedText.isEmpty else {
            return .natural
        }
        return body.hydratedText.naturalTextAlignment
    }

    public override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        return displayString.attributes(at: location, effectiveRange: range)
    }

    public override func replaceCharacters(in range: NSRange, with str: String) {
        self.replaceCharacters(
            in: range,
            with: str,
            selectedRange: editableBodyDelegate?.editableMessageSelectedRange()
                ?? NSRange(location: (body.hydratedText as NSString).length, length: 0)
        )
    }

    public override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        guard isFixingAttributes else {
            // Don't allow external attribute setting except from
            // fixing, which is applied for emojis.
            return
        }
        displayString.setAttributes(attrs, range: range)
    }

    private var isFixingAttributes = false

    public override func fixAttributes(in range: NSRange) {
        isFixingAttributes = true
        super.fixAttributes(in: range)
        isFixingAttributes = false
    }

    private var isEditing = false

    private var selectionAfterEdits: NSRange?

    public override func beginEditing() {
        super.beginEditing()
        isEditing = true
        self.selectionAfterEdits = nil
    }

    public override func endEditing() {
        super.endEditing()
        isEditing = false
        DispatchQueue.main.async {
            if let selectionAfterEdits = self.selectionAfterEdits {
                self.selectionAfterEdits = nil
                self.editableBodyDelegate?.editableMessageBodyDidRequestNewSelectedRange(selectionAfterEdits)
            }
        }
    }

    // MARK: - State Representation

    internal struct Body: Equatable {
        var hydratedText: String
        var mentions: [NSRange: UUID]
        var flattenedStyles: [NSRangedValue<SingleStyle>]
    }

    private var body = Body(hydratedText: "", mentions: [:], flattenedStyles: []) {
        didSet {
            cachedMessageBody = nil
        }
    }

    private var displayString: NSMutableAttributedString = NSMutableAttributedString(string: "")

    public var hydratedPlaintext: String {
        return body.hydratedText
    }

    public var attributedString: NSAttributedString {
        return displayString
    }

    // Unordered
    public var mentionRanges: [NSRange] {
        return body.mentions.keys.map({ $0 })
    }

    // MARK: - Making Updates

    public func didUpdateTheming() {
        let selectedRange = editableBodyDelegate?.editableMessageSelectedRange() ?? NSRange(location: displayString.length, length: 0)
        regenerateDisplayString(
            hydratedTextBeforeChange: body.hydratedText,
            hydrator: makeMentionHydratorForCurrentBody(),
            modifiedRange: NSRange(location: 0, length: (body.hydratedText as NSString).length),
            selectedRangeAfterChange: selectedRange
        )
    }

    /// Replace characters in the provided range with a plaintext string. The string will not
    /// have any formatting properties applied, even if inserted in the middle of a formatted range.
    /// If any change is made to a mention range, the mention will be removed (but its representation
    /// as plaintext will persist).
    public func replaceCharacters(in range: NSRange, with string: String, selectedRange: NSRange) {
        replaceCharacters(
            in: range,
            with: string,
            selectedRange: selectedRange,
            forceIgnoreStylesInReplacedRange: false,
            txProvider: db.readTxProvider
        )
    }

    private func replaceCharacters(
        in range: NSRange,
        with string: String,
        selectedRange: NSRange,
        forceIgnoreStylesInReplacedRange: Bool,
        txProvider: ReadTxProvider
    ) {
        let string = string.removingPlaceholders()
        let hydratedTextBeforeChange = body.hydratedText
        let changeInLength = (string as NSString).length - range.length
        var modifiedRange = range
        // For append-only, we can efficiently update without recomputing anything.
        if range.location == displayString.length, range.length == 0 {
            self.efficientAppendText(string, range: range, changeInLength: changeInLength)
            return
        }
        // If the change is within a mention, that mention is eliminated.
        // Note that the hydrated text of the mention is preserved; its just plaintext now.
        var intersectingMentionRanges = [NSRange]()
        body.mentions.forEach { (mentionRange, mentionUuid) in
            if
                // An insert, which can happen in the middle of a mention.
                (range.length == 0 && mentionRange.contains(range.location))
                || (mentionRange.intersection(range)?.length ?? 0) > 0
            {
                intersectingMentionRanges.append(mentionRange)
            } else if range.upperBound <= mentionRange.location {
                // If the change is before a mention, we have to shift the mention.
                body.mentions[mentionRange] = nil
                body.mentions[NSRange(location: mentionRange.location + changeInLength, length: mentionRange.length)] = mentionUuid
            }
        }
        if
            string.isEmpty,
            selectedRange.length <= 1,
            let intersectingMentionRange = intersectingMentionRanges.first,
            range.length == 1,
            range.upperBound == intersectingMentionRange.upperBound
        {
            // Backspace at the end of a mention, just clear the whole mention minus the prefix.
            self.replaceCharacters(in: intersectingMentionRange, with: Mention.prefix, selectedRange: selectedRange)
            // Put the selection after the prefix so a new mention can be typed.
            let newSelectedRange = NSRange(
                location: intersectingMentionRange.location + (Mention.prefix as NSString).length,
                length: 0
            )
            self.selectionAfterEdits = newSelectedRange
            return
        }
        intersectingMentionRanges.forEach {
            body.mentions.removeValue(forKey: $0)
            modifiedRange.formUnion($0)
        }

        // Styles need updated ranges.
        body.flattenedStyles = Self.updateFlattenedStyles(
            body.flattenedStyles,
            forReplacementOf: range,
            with: string,
            preserveStyleInReplacement: (!forceIgnoreStylesInReplacedRange && string.shouldContinueExistingStyle)
        )

        body.hydratedText = (body.hydratedText as NSString)
            .replacingCharacters(in: range, with: string)
            .removingPlaceholders()

        regenerateDisplayString(
            hydratedTextBeforeChange: hydratedTextBeforeChange,
            hydrator: makeMentionHydrator(for: Array(self.body.mentions.values), txProvider: txProvider),
            modifiedRange: modifiedRange,
            selectedRangeAfterChange: nil
        )
    }

    private func efficientAppendText(_ string: String, range: NSRange, changeInLength: Int) {
        self.body.hydratedText = body.hydratedText + string
        guard let editableBodyDelegate else {
            owsFailDebug("Should have delegate")
            self.displayString.append(string)
            return
        }

        // See if there are styles to preserve.
        var stylesToApply: Style?
        if string.shouldContinueExistingStyle, range.location > 0 {
            let indexToCheck = range.location - 1
            for (i, style) in body.flattenedStyles.enumerated() {
                if style.range.contains(indexToCheck) {
                    // Extend the existing style.
                    let newStyle = NSRangedValue<SingleStyle>(
                        style.value,
                        range: NSRange(
                            location: style.range.location,
                            length: style.range.length + range.length + changeInLength
                        )
                    )
                    // Safe to reinsert in place as its sorted by location,
                    // which didn't change as we only touched length.
                    body.flattenedStyles[i] = newStyle
                    if stylesToApply != nil {
                        stylesToApply?.insert(style: style.value)
                    } else {
                        stylesToApply = style.value.asStyle
                    }
                }
            }
        }

        let config = editableBodyDelegate.editableMessageBodyDisplayConfig()
        let isDarkThemeEnabled = editableBodyDelegate.isEditableMessageBodyDarkThemeEnabled()
        let stringToAppend: NSAttributedString
        let editActions: NSTextStorage.EditActions
        if let stylesToApply {
            stringToAppend = StyleOnlyMessageBody(text: string, styles: stylesToApply).asAttributedStringForDisplay(
                config: config.style,
                textAlignment: string.nilIfEmpty?.naturalTextAlignment ?? .natural,
                isDarkThemeEnabled: isDarkThemeEnabled
            )
            editActions = [.editedAttributes, .editedCharacters]
        } else {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = string.nilIfEmpty?.naturalTextAlignment ?? .natural
            stringToAppend = NSAttributedString(
                string: string,
                attributes: [
                    .font: config.mention.font,
                    .foregroundColor: config.baseTextColor.color(isDarkThemeEnabled: isDarkThemeEnabled),
                    .paragraphStyle: paragraphStyle
                ]
            )
            editActions = .editedCharacters
        }
        self.displayString.append(stringToAppend)
        super.edited(editActions, range: range, changeInLength: changeInLength)
    }

    public func replaceCharacters(in range: NSRange, withMentionUUID mentionUuid: UUID, txProvider: ReadTxProvider) {
        let hydrator = makeMentionHydrator(for: Array(body.mentions.values) + [mentionUuid], txProvider: txProvider)
        replaceCharacters(in: range, withMentionUUID: mentionUuid, hydrator: hydrator, insertSpaceAfter: true)
    }

    private func replaceCharacters(
        in range: NSRange,
        withMentionUUID mentionUuid: UUID,
        hydrator: CacheMentionHydrator,
        insertSpaceAfter: Bool
    ) {
        let hydratedTextBeforeChange = body.hydratedText
        var modifiedRange = range
        let hydratedMention: String
        switch hydrator.hydrator(mentionUuid) {
        case .hydrate(let mentionString):
            if CurrentAppContext().isRTL {
                hydratedMention = mentionString + Mention.prefix
            } else {
                hydratedMention = Mention.prefix + mentionString
            }
        case .preserveMention:
            return
        }

        // If the change is within an existing mention, that mention is eliminated.
        // Note that the hydrated text of the mention is preserved; its just plaintext now.
        let intersectingMentionRanges = body.mentions.keys.filter { mentionRange in
            if range.length == 0 {
                // An insert, which can happen in the middle of a mention.
                return mentionRange.contains(range.location)
            } else {
                return (mentionRange.intersection(range)?.length ?? 0) > 0
            }
        }
        intersectingMentionRanges.forEach {
            body.mentions.removeValue(forKey: $0)
            modifiedRange.formUnion($0)
        }

        // Add a space after the inserted mention
        let suffix = insertSpaceAfter ? " " : ""
        let finalMentionText = hydratedMention + suffix

        // Styles need updated ranges.
        body.flattenedStyles = Self.updateFlattenedStyles(
            body.flattenedStyles,
            forReplacementOf: range,
            with: finalMentionText,
            preserveStyleInReplacement: true
        )

        body.hydratedText = (body.hydratedText as NSString).replacingCharacters(
            in: range,
            with: finalMentionText
        ).removingPlaceholders()
        // Any space isn't included in the mention's range.
        let mentionRange = NSRange(location: range.location, length: (hydratedMention as NSString).length)
        body.mentions[mentionRange] = mentionUuid

        // Put the cursor after the space, if any
        let newSelectedRange = NSRange(location: mentionRange.upperBound + (suffix as NSString).length, length: 0)

        regenerateDisplayString(
            hydratedTextBeforeChange: hydratedTextBeforeChange,
            hydrator: hydrator,
            modifiedRange: modifiedRange,
            selectedRangeAfterChange: newSelectedRange
        )
    }

    public func hasFormatting(in range: NSRange) -> Bool {
        return body.flattenedStyles.contains(where: { ($0.range.intersection(range)?.length ?? 0) > 0 })
    }

    public func clearFormatting(in range: NSRange) {
        // Check for overlaps with mentions; any styles we apply to a mention applies
        // to the whole mention.
        var range = range
        for mentionRange in mentionRanges {
            if let intersection = mentionRange.intersection(range), intersection.length > 0 {
                range.formUnion(mentionRange)
            }
        }

        let previouslySelectedRange = editableBodyDelegate?.editableMessageSelectedRange()
        // Reverse order so we can modify indexes in the for loop and not hit problems.
        for (i, style) in body.flattenedStyles.enumerated().reversed() {
            guard style.range.upperBound > range.location else {
                // We got past all relevant ranges, safe to stop now.
                break
            }
            guard let intersection = style.range.intersection(range), intersection.length > 0 else {
                continue
            }
            body.flattenedStyles.remove(at: i)
            if range.location > style.range.location {
                // Chop off the start of the existing range and reinsert it.
                let newStyle = NSRangedValue(
                    style.value,
                    range: NSRange(
                        location: style.range.location,
                        length: range.location - style.range.location
                    )
                )
                insertStylePreservingSort(newStyle)
            }
            if range.upperBound < style.range.upperBound {
                // Chop off the end of the existing range and reinsert it.
                let newStyle = NSRangedValue(
                    style.value,
                    range: NSRange(
                        location: range.upperBound,
                        length: style.range.upperBound - range.upperBound
                    )
                )
                insertStylePreservingSort(newStyle)
            }
        }

        let newSelectedRange: NSRange
        if let previouslySelectedRange {
            newSelectedRange = NSRange(location: previouslySelectedRange.upperBound, length: 0)
        } else {
            // Put it at the end.
            newSelectedRange = NSRange(location: (body.hydratedText as NSString).length, length: 0)
        }

        regenerateDisplayString(
            hydratedTextBeforeChange: body.hydratedText /* text doesn't change */,
            hydrator: makeMentionHydratorForCurrentBody(),
            modifiedRange: range,
            selectedRangeAfterChange: newSelectedRange
        )
    }

    public func toggleStyle(_ style: SingleStyle, in range: NSRange) {
        toggleStyle(style, in: range, txProvider: db.readTxProvider)
    }

    private func toggleStyle(_ style: SingleStyle, in range: NSRange, txProvider: ReadTxProvider) {
        let hydratedTextBeforeChange = body.hydratedText
        // We want to put the selection at the end of the previously selected range.
        let previouslySelectedRange = editableBodyDelegate?.editableMessageSelectedRange()

        // Check for overlaps with mentions; any styles we apply to a mention applies
        // to the whole mention.
        var range = range
        for mentionRange in mentionRanges {
            if let intersection = mentionRange.intersection(range), intersection.length > 0 {
                range.formUnion(mentionRange)
            }
        }

        let newStyle = NSRangedValue<SingleStyle>(style, range: range)
        let overlaps = NSRangedValue<Any>.overlaps(
            of: newStyle,
            in: self.body.flattenedStyles,
            isEqual: ==
        )

        switch overlaps {
        case .none(let insertionIndex):
            // Easiest case; no overlaps so just insert as a new style.
            body.flattenedStyles.insert(newStyle, at: insertionIndex)

        case .withinExistingRange(let containingRangeIndex):
            // Contained within one range, so we want to un-apply.
            // Remove the existing range, then determine if there are any
            // non-overlapping sections to chop off and reinsert.
            let containingStyle = self.body.flattenedStyles[containingRangeIndex]
            self.body.flattenedStyles.remove(at: containingRangeIndex)
            if range.location > containingStyle.range.location {
                // Chop off the start of the existing range and reinsert it.
                let newStyle = NSRangedValue(
                    style,
                    range: NSRange(
                        location: containingStyle.range.location,
                        length: range.location - containingStyle.range.location
                    )
                )
                insertStylePreservingSort(newStyle)
            }
            if range.upperBound < containingStyle.range.upperBound {
                // Chop off the end of the existing range and reinsert it.
                let newStyle = NSRangedValue(
                    style,
                    range: NSRange(
                        location: range.upperBound,
                        length: containingStyle.range.upperBound - range.upperBound
                    )
                )
                insertStylePreservingSort(newStyle)
            }

        case .acrossExistingRanges(let overlapIndexes, let gaps):
            let shouldUnapply: Bool
            if gaps.isEmpty {
                // If there are no gaps, we will un-apply.
                shouldUnapply = true
            } else {
                // There are gaps. For some styles, we ignore whitespace gaps.
                switch style {
                case .strikethrough, .monospace, .spoiler:
                    // Styles visually apply to all gaps, so we should apply.
                    shouldUnapply = false
                case .bold, .italic:
                    // Ignore gaps if they're all whitespace, so its like
                    // if we had no gaps.
                    shouldUnapply = gaps.allSatisfy({ gap in
                        return self.body.hydratedText.substring(withRange: gap).allSatisfy(\.isWhitespace)
                    })
                }
            }

            if shouldUnapply {
                // If unapplying, remove existing styles but be careful to keep
                // any hanging head or tail sections.
                var newRangesToInsert = [NSRangedValue<SingleStyle>]()
                if let firstIndex = overlapIndexes.first {
                    // Chop off the start of the first overlapping range and reinsert it.
                    let existingRange = self.body.flattenedStyles[firstIndex]
                    let newStyle = NSRangedValue(
                        style,
                        range: NSRange(
                            location: existingRange.range.location,
                            length: range.location - existingRange.range.location
                        )
                    )
                    if newStyle.range.length > 0 {
                        newRangesToInsert.append(newStyle)
                    }
                }
                if let lastIndex = overlapIndexes.last {
                    // Chop off the end of the last overlapping range and reinsert it.
                    let existingRange = self.body.flattenedStyles[lastIndex]
                    let newStyle = NSRangedValue(
                        style,
                        range: NSRange(
                            location: range.upperBound,
                            length: existingRange.range.upperBound - range.upperBound
                        )
                    )
                    if newStyle.range.length > 0 {
                        newRangesToInsert.append(newStyle)
                    }
                }
                // Remove the overlaps.
                for i in overlapIndexes.reversed() {
                    self.body.flattenedStyles.remove(at: i)
                }
                newRangesToInsert.forEach(insertStylePreservingSort(_:))
            } else {
                // If applying, merge all styles into one.
                var mergedRange = range
                for i in overlapIndexes.reversed() {
                    let existingRange = self.body.flattenedStyles.remove(at: i)
                    mergedRange.formUnion(existingRange.range)
                }
                insertStylePreservingSort(.init(style, range: mergedRange))
            }
        }

        let newSelectedRange: NSRange
        if let previouslySelectedRange {
            newSelectedRange = NSRange(location: previouslySelectedRange.upperBound, length: 0)
        } else {
            // Put it at the end.
            newSelectedRange = NSRange(location: (body.hydratedText as NSString).length, length: 0)
        }

        regenerateDisplayString(
            hydratedTextBeforeChange: hydratedTextBeforeChange,
            hydrator: makeMentionHydrator(for: Array(self.body.mentions.values), txProvider: txProvider),
            modifiedRange: range,
            selectedRangeAfterChange: newSelectedRange
        )
    }

    /// Be careful using this method; styles cannot overlap with styles of the same type and that
    /// invariant must be enforced by callers of this method.
    private func insertStylePreservingSort(_ newStyle: NSRangedValue<SingleStyle>) {
        var low = self.body.flattenedStyles.startIndex
        var high = self.body.flattenedStyles.endIndex
        while low != high {
            let mid = self.body.flattenedStyles.index(
                low,
                offsetBy: self.body.flattenedStyles.distance(from: low, to: high) / 2
            )
            let element = self.body.flattenedStyles[mid]
            if newStyle.range.location == element.range.location {
                // Good insertion point; we can stop
                self.body.flattenedStyles.insert(newStyle, at: mid)
                return
            } else if newStyle.range.location > element.range.location {
                low = self.body.flattenedStyles.index(after: mid)
            } else {
                high = mid
            }
        }
        self.body.flattenedStyles.insert(newStyle, at: low)
    }

    public func replaceCharacters(in range: NSRange, withPastedMessageBody messageBody: MessageBody, txProvider: ReadTxProvider) {
        let hydrator = self.makeMentionHydrator(for: Array(messageBody.ranges.mentions.values), txProvider: txProvider)
        let hydrated = messageBody.hydrating(mentionHydrator: hydrator.hydrator)
        let insertedBody = hydrated.asEditableMessageBody()

        // First replace with plaintext, then apply the styles and mentions.
        self.replaceCharacters(
            in: range,
            with: insertedBody.hydratedText,
            selectedRange: range,
            forceIgnoreStylesInReplacedRange: true,
            txProvider: txProvider
        )
        for mention in insertedBody.mentions {
            self.replaceCharacters(
                in: NSRange(location: range.location + mention.key.location, length: mention.key.length),
                withMentionUUID: mention.value,
                hydrator: hydrator,
                insertSpaceAfter: false
            )
        }
        for style in insertedBody.flattenedStyles {
            self.toggleStyle(
                style.value,
                in: NSRange(location: range.location + style.range.location, length: style.range.length),
                txProvider: txProvider
            )
        }
        let hydratedTextBeforeChange = body.hydratedText
        let wholeBodyHydrator = makeMentionHydrator(for: Array(self.body.mentions.values), txProvider: txProvider)
        // Put the range at the very end.
        let newSelectedRange = NSRange(location: range.location + (insertedBody.hydratedText as NSString).length, length: 0)
        self.regenerateDisplayString(
            hydratedTextBeforeChange: hydratedTextBeforeChange,
            hydrator: wholeBodyHydrator,
            modifiedRange: range,
            selectedRangeAfterChange: newSelectedRange
        )
    }

    /// If `preserveStyleInReplacement` is true, any styles existing
    /// in the first character of the range being replaced will be applied to the
    /// entirety of the new text.
    /// For replacement ranges of length 0 (aka insertions), we look a the style
    /// on the preceding character and extend it.
    /// Only false if inserting a copy-pasted MessageBody that has styles
    /// of its own.
    private static func updateFlattenedStyles(
        _ flattenedStyles: [NSRangedValue<SingleStyle>],
        forReplacementOf range: NSRange,
        with string: String,
        preserveStyleInReplacement: Bool
    ) -> [NSRangedValue<SingleStyle>] {
        let stringLength = (string as NSString).length
        let changeLengthDiff = stringLength - range.length

        var finalStyles = [NSRangedValue<SingleStyle>]()
        func appendToFinalStyles(_ style: NSRangedValue<SingleStyle>) {
            guard style.range.length > 0 else {
                return
            }
            finalStyles.append(style)
        }

        let targetIndexForPreservation: Int?
        if range.length == 0 {
            if range.location > 0 {
                targetIndexForPreservation = range.location - 1
            } else {
                targetIndexForPreservation = nil
            }
        } else {
            targetIndexForPreservation = range.location
        }

        for style in flattenedStyles {
            if
                preserveStyleInReplacement,
                let targetIndexForPreservation,
                style.range.contains(targetIndexForPreservation)
            {
                // We should preserve this style, and apply it to the entire new range.
                let newLength =
                    range.location - style.range.location /* part before the range start */
                    + range.length + changeLengthDiff /* applies to the entire range */
                    + max(0, style.range.upperBound - range.upperBound) /* part after the end, if any */
                appendToFinalStyles(.init(
                    style.value,
                    range: NSRange(
                        location: style.range.location,
                        length: newLength
                    )
                ))
            } else if style.range.upperBound <= range.location {
                // Its before the changed region, no changes needed.
                appendToFinalStyles(style)
            } else if style.range.location >= range.upperBound {
                // Its after the changed region, just update the location.
                appendToFinalStyles(.init(
                    style.value,
                    range: NSRange(
                        location: style.range.location + changeLengthDiff,
                        length: style.range.length
                    )
                ))
            } else if style.range.location >= range.location, style.range.upperBound <= range.upperBound {
                // Total overlap; the range being replaced fully contains the existing style.
                // But we already determined this style _isn't_ to be preserved since this
                // is an "else" after the first "if". So we can skip this style.
                continue
            } else if style.range.location < range.location, style.range.upperBound > range.upperBound {
                // The style contains the changed range. We have to split it two on either side of the eliminated region.
                appendToFinalStyles(.init(
                    style.value,
                    range: NSRange(
                        location: style.range.location,
                        length: range.location - style.range.location
                    )
                ))
                appendToFinalStyles(.init(
                    style.value,
                    range: NSRange(
                        location: range.upperBound + changeLengthDiff,
                        length: style.range.upperBound - range.upperBound
                    )
                ))
            } else if style.range.location < range.location {
                // The style hangs off the start of the affected range.
                // Slice off the overlapping bit and keep the start.
                appendToFinalStyles(.init(
                    style.value,
                    range: NSRange(
                        location: style.range.location,
                        length: range.location - style.range.location
                    )
                ))
            } else {
                // The style hangs off the end of the affected range.
                // Slice off the overlapping bit and keep the end.
                appendToFinalStyles(.init(
                    style.value,
                    range: NSRange(
                        location: range.upperBound + changeLengthDiff,
                        length: style.range.upperBound - range.upperBound
                    )
                ))
            }
        }
        return finalStyles
    }

    // MARK: - MessageBody

    public var messageBody: MessageBody { return getOrMakeMessageBody() }

    public func messageBody(forHydratedTextSubrange subrange: NSRange) -> MessageBody {
        return Self.makeMessageBody(body: self.body, subrange: subrange)
    }

    public func setMessageBody(_ messageBody: MessageBody?, txProvider: ReadTxProvider) {
        let hydratedTextBeforeChange = body.hydratedText
        let messageBody = messageBody ?? MessageBody(text: "", ranges: .empty)
        let hydrator = self.makeMentionHydrator(for: Array(messageBody.ranges.mentions.values), txProvider: txProvider)
        let hydrated = messageBody.hydrating(mentionHydrator: hydrator.hydrator)
        self.body = hydrated.asEditableMessageBody()
        // While this could open a _second_ transaction, in practice it won't because
        // we have the cached values from the hydator above
        regenerateDisplayString(
            hydratedTextBeforeChange: hydratedTextBeforeChange,
            hydrator: hydrator,
            modifiedRange: NSRange(location: 0, length: (hydratedTextBeforeChange as NSString).length),
            selectedRangeAfterChange: NSRange(location: (body.hydratedText as NSString).length, length: 0)
        )
        // Immediately apply any selection changes; otherwise the selected range
        // may end up with out of range values.
        if let selectionAfterEdits = self.selectionAfterEdits {
            self.selectionAfterEdits = nil
            self.editableBodyDelegate?.editableMessageBodyDidRequestNewSelectedRange(selectionAfterEdits)
        }
    }

    // Constructing this is expensive and is used as input to the displayed string. Cache it.
    private var cachedMessageBody: MessageBody?

    private func getOrMakeMessageBody() -> MessageBody {
        Self.getOrMakeMessageBody(cache: &cachedMessageBody, body: body)
    }

    private static func getOrMakeMessageBody(cache: inout MessageBody?, body: Body) -> MessageBody {
        if let cache {
            return cache
        }
        let body = makeMessageBody(body: body, subrange: nil)
        cache = body
        return body
    }

    // Note: subrange is denoted in the _hydrated_ text, not in the final
    // message body text after un-hydrating.
    private static func makeMessageBody(body: Body, subrange: NSRange?) -> MessageBody {
        // Un-hydrate the mentions first.
        var text: NSString = (body.hydratedText as NSString)
        var flattenedStyles = body.flattenedStyles
        if let subrange {
            text = text.substring(with: subrange) as NSString
            flattenedStyles = flattenedStyles.compactMap { flattenedStyle in
                guard
                    let intersection = flattenedStyle.range.intersection(subrange),
                    intersection.length > 0
                else {
                    return nil
                }
                return .init(
                    flattenedStyle.value,
                    range: NSRange(
                        location: intersection.location - subrange.location,
                        length: intersection.length
                    )
                )
            }
        }
        let orderedMentions: [NSRangedValue<UUID>] = body.mentions.lazy
            .compactMap({ (range: NSRange, uuid: UUID) -> NSRangedValue<UUID>? in
                guard let subrange else {
                    return .init(uuid, range: range)
                }
                guard
                    let intersection = range.intersection(subrange),
                    // We need total overlap or we won't preserve the mention.
                    intersection.length == range.length
                else {
                    return nil
                }
                return .init(
                    uuid,
                    range: NSRange(
                        location: intersection.location - subrange.location,
                        length: intersection.length
                    )
                )
            })
            .sorted(by: {
                return $0.range.location < $1.range.location
            })

        let mentionPlaceholderLength = (MessageBody.mentionPlaceholder as NSString).length
        var finalMentions = [NSRange: UUID]()
        var mentionOffset = 0
        for mention in orderedMentions {
            let effectiveRange = NSRange(location: mention.range.location + mentionOffset, length: mention.range.length)
            text = text.replacingCharacters(in: effectiveRange, with: MessageBody.mentionPlaceholder) as NSString
            finalMentions[NSRange(location: effectiveRange.location, length: mentionPlaceholderLength)] = mention.value
            flattenedStyles = Self.updateFlattenedStyles(
                flattenedStyles,
                forReplacementOf: effectiveRange,
                with: MessageBody.mentionPlaceholder,
                preserveStyleInReplacement: true
            )
            mentionOffset += mentionPlaceholderLength - mention.range.length
        }
        return MessageBody(
            text: text as String,
            ranges: MessageBodyRanges(
                mentions: finalMentions,
                styles: flattenedStyles
            )
        )
    }

    private func regenerateDisplayString(
        hydratedTextBeforeChange: String,
        hydrator: CacheMentionHydrator,
        modifiedRange: NSRange,
        selectedRangeAfterChange: NSRange?
    ) {
        guard let editableBodyDelegate else {
            owsFailDebug("Should have delegate")
            return
        }
        let config = editableBodyDelegate.editableMessageBodyDisplayConfig()
        let isDarkThemeEnabled = editableBodyDelegate.isEditableMessageBodyDarkThemeEnabled()
        let displayString = getOrMakeMessageBody()
            .hydrating(mentionHydrator: hydrator.hydrator, filterStringForDisplay: false)
            .asAttributedStringForDisplay(
                config: config,
                textAlignment: hydratedPlaintext.nilIfEmpty?.naturalTextAlignment ?? .natural,
                isDarkThemeEnabled: isDarkThemeEnabled
            )
        self.displayString = (displayString as? NSMutableAttributedString) ?? NSMutableAttributedString(attributedString: displayString)
        self.fixAttributes(in: NSRange(location: 0, length: displayString.length))

        let changeInLength = (body.hydratedText as NSString).length - (hydratedTextBeforeChange as NSString).length
        super.edited(
            body.hydratedText != hydratedTextBeforeChange ? [.editedCharacters, .editedAttributes] : .editedAttributes,
            range: modifiedRange,
            changeInLength: changeInLength
        )
        self.selectionAfterEdits = selectedRangeAfterChange
        if !isEditing, let selectedRangeAfterChange {
            self.selectionAfterEdits = nil
            editableBodyDelegate.editableMessageBodyDidRequestNewSelectedRange(selectedRangeAfterChange)
        }
    }

    // MARK: - Hydrating

    private var mentionCacheKey: String?
    private var mentionCache = [UUID: String]()
    private var skippedMentionUUIDS = Set<UUID>()

    /// This object represents the results of already having opened, and finished with, a
    /// transaction to read mention hydrated names. We cache the results, put them in this
    /// object, and make them available for reading without needing to open a new transaction.
    ///
    /// Cache mention hydration results so we don't constantly fetch; we avoid even opening
    /// a transaction until we absolutely have to.
    /// Note that if this gets out of sync with the DB because some contact name changes that's ultimately fine;
    /// we un-hydrate mentions before we send them so this state is only for display of the message being composed.
    class CacheMentionHydrator {
        private let mentionCache: [UUID: String]

        init(mentionCache: [UUID: String]) {
            self.mentionCache = mentionCache
        }

        var hydrator: MentionHydrator {
            return { [mentionCache] uuid in
                guard let mentionString = mentionCache[uuid] else {
                    return .preserveMention
                }
                return .hydrate(mentionString)
            }
        }
    }

    private func makeMentionHydratorForCurrentBody() -> CacheMentionHydrator {
        return makeMentionHydrator(for: Array(self.body.mentions.values), txProvider: db.readTxProvider)
    }

    private func makeMentionHydrator(for mentions: [UUID], txProvider: ReadTxProvider) -> CacheMentionHydrator {
        var mentionCache: [UUID: String]
        if let mentionCacheKey, mentionCacheKey == editableBodyDelegate?.mentionCacheInvalidationKey() {
            mentionCache = self.mentionCache
        } else {
            self.mentionCache = [:]
            mentionCache = [:]
        }
        // If all mentions are in the cache, no need to recompute.
        if !mentions.allSatisfy({ mentionCache[$0] != nil || skippedMentionUUIDS.contains($0) }) {
            // If any are missing, we have to open a transaction and put them in the cache.
            txProvider { tx in
                let hydrator = editableBodyDelegate?.editableMessageBodyHydrator(tx: tx) ?? ContactsMentionHydrator.mentionHydrator(transaction: tx)
                mentions.forEach { uuid in
                    switch hydrator(uuid) {
                    case .hydrate(let hydratedString):
                        mentionCache[uuid] = hydratedString
                    case .preserveMention:
                        skippedMentionUUIDS.insert(uuid)
                    }
                }
            }
        }
        self.mentionCache = mentionCache
        self.mentionCacheKey = editableBodyDelegate?.mentionCacheInvalidationKey()

        return .init(mentionCache: mentionCache)
    }
}

extension DB {

    public var readTxProvider: EditableMessageBodyTextStorage.ReadTxProvider {
        return { self.read(block: $0) }
    }
}

extension SDSDatabaseStorage {

    public var readTxProvider: EditableMessageBodyTextStorage.ReadTxProvider {
        return { block in self.read(block: { block($0.asV2Read) }) }
    }
}

extension String {
    fileprivate func removingPlaceholders() -> String {
        return (self as NSString).replacingOccurrences(of: "\u{fffc}", with: "")
    }

    // We preserve style as long as we are not adding a single whitespace.
    fileprivate var shouldContinueExistingStyle: Bool {
        return !(self.count == 1 && self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
