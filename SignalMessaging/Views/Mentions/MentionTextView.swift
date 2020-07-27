//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol MentionTextViewDelegate: UITextViewDelegate {
    func textViewDidBeginTypingMention(_ textView: MentionTextView)
    func textViewDidEndTypingMention(_ textView: MentionTextView)
    func textView(_ textView: MentionTextView, didUpdateMentionText mentionText: String)

    func textView(_ textView: MentionTextView, didTapMention: MentionRange)
    func textView(_ textView: MentionTextView, didDeleteMention: MentionRange)

    func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool
    func textViewMentionStyle(_ textView: MentionTextView) -> MentionStyle
}

@objc
open class MentionTextView: OWSTextView {
    public static let mentionPrefix = "@"
    public static let mentionPrefixLength = 1

    @objc
    public weak var mentionDelegate: MentionTextViewDelegate?

    public override var delegate: UITextViewDelegate? {
        didSet {
            if let delegate = delegate {
                owsAssertDebug(delegate === self)
            }
        }
    }

    public required init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    public func insertTypedMention(address: SignalServiceAddress) {
        guard case .typingMention(let range) = state else {
            return owsFailDebug("Can't finish typing when no mention in progress")
        }

        guard range.location >= Self.mentionPrefixLength else {
            return owsFailDebug("Invalid mention range \(range)")
        }

        replaceCharacters(
            with: MentionRange(
                location: range.location - Self.mentionPrefixLength,
                length: range.length + Self.mentionPrefixLength,
                address: address
            ),
            alwaysResolveMention: true
        )
    }

    public func replaceCharacters(with mention: MentionRange, alwaysResolveMention: Bool = false) {
        replaceCharacters(with: mention, inMutableString: textStorage, alwaysResolveMention: alwaysResolveMention)
    }

    public func replaceCharacters(
        with mention: MentionRange,
        inMutableString mutableString: NSMutableAttributedString,
        alwaysResolveMention: Bool = false
    ) {
        guard let mentionDelegate = mentionDelegate else {
            return owsFailDebug("Can't replace characters without delegate")
        }

        let replacementString: NSAttributedString
        if alwaysResolveMention || mentionDelegate.textView(self, shouldResolveMentionForAddress: mention.address) {
            let mentionAttachemnt = MentionTextAttachment(
                address: mention.address,
                style: mentionDelegate.textViewMentionStyle(self)
            )

            replacementString = NSAttributedString(attachment: mentionAttachemnt)
        } else {
            // If we shouldn't resolve the mention, insert the plaintext representation.
            let displayName = Self.mentionPrefix + Environment.shared.contactsManager.displayName(for: mention.address)
            replacementString = NSAttributedString(string: displayName, attributes: typingAttributes)
        }

        if mutableString === textStorage {
            replaceCharacters(in: mention.nsRange, with: replacementString)
        } else {
            mutableString.replaceCharacters(in: mention.nsRange, with: replacementString)
        }
    }

    public func replaceCharacters(in range: NSRange, with mentionText: MentionText) {
        let attributedMentions = NSMutableAttributedString(string: mentionText.text, attributes: typingAttributes)

        // We must enumerate the ranges in reverse, so as we replace a ranges
        // text we do not change the previous ranges.
        for mention in mentionText.ranges.sorted(by: { $0.location > $1.location }) {
            replaceCharacters(with: mention, inMutableString: attributedMentions)
        }

        replaceCharacters(in: range, with: attributedMentions)
    }

    public func replaceCharacters(in range: NSRange, with string: String) {
        replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: typingAttributes))
    }

    public func replaceCharacters(in range: NSRange, with attributedString: NSAttributedString) {
        let previouslySelectedRange = selectedRange
        let previousFont = font

        textStorage.replaceCharacters(in: range, with: attributedString)

        // There is a bug where the font gets reset after inserting an NSTextAttachment.
        // We restore the font afterwards to work around this bug.
        font = previousFont

        updateSelectedRangeAfterReplacement(
            previouslySelectedRange: previouslySelectedRange,
            replacedRange: range,
            replacementLength: attributedString.length
        )

        textViewDidChange(self)
    }

    private func updateSelectedRangeAfterReplacement(previouslySelectedRange: NSRange, replacedRange: NSRange, replacementLength: Int) {
        let replacedRangeEnd = replacedRange.location + replacedRange.length

        let replacedRangeIntersectsSelectedRange = previouslySelectedRange.location <= replacedRange.location
            && previouslySelectedRange.location < replacedRangeEnd

        let replacedRangeIsEntirelyBeforeSelectedRange = replacedRangeEnd <= previouslySelectedRange.location

        // If the replaced range intersected the selected range, move the cursor after the replacement text
        if replacedRangeIntersectsSelectedRange {
            selectedRange = NSRange(location: replacedRange.location + replacementLength, length: 0)

        // If the replaced range was entirely before the selected range, shift the selected range to
        // account for our newly inserted text.
        } else if replacedRangeIsEntirelyBeforeSelectedRange {
            selectedRange = NSRange(
                location: previouslySelectedRange.location + (replacementLength - replacedRange.length),
                length: previouslySelectedRange.length
            )
        }
    }

    public var currentlyTypingMentionText: String? {
        guard case .typingMention(let range) = state else { return nil }
        guard textStorage.length >= range.location + range.length else { return nil }
        guard range.length > 0 else { return "" }

        return attributedText.attributedSubstring(from: range).string
    }

    override open var text: String! {
        get {
            textWithPlaintextMentions(in: NSRange(location: 0, length: textStorage.length))
        }
        set {
            attributedText = NSAttributedString(string: newValue ?? "", attributes: typingAttributes)
        }
    }

    public func textWithPlaintextMentions(in range: NSRange) -> String {
        guard range.length > 0 else { return "" }

        guard range.location >= 0, range.location + range.length <= textStorage.length else {
            owsFailDebug("unexpected range \(range)")
            return ""
        }

        var text = attributedText.attributedSubstring(from: range).string
        // Replace all mention placeholders with their plaintext representation.
        textStorage.enumerateAttribute(
            .attachment,
            in: range,
            options: [.longestEffectiveRangeNotRequired, .reverse]
        ) { attachment, attachmentRange, _ in
            guard let attachment = attachment as? MentionTextAttachment else { return }
            text = (text as NSString).replacingCharacters(
                in: NSRange(location: attachmentRange.location - range.location, length: attachmentRange.length),
                with: attachment.text
            )
        }
        return text
    }

    @objc
    public var mentionText: MentionText? {
        get { mentionText(in: NSRange(location: 0, length: textStorage.length)) }
        set {
            guard let mentionText = newValue else {
                text = nil
                return
            }
            replaceCharacters(
                in: NSRange(location: 0, length: textStorage.length),
                with: mentionText
            )
        }
    }

    @objc
    public func mentionText(in range: NSRange) -> MentionText? {
        var ranges = [MentionRange]()

        textStorage.enumerateAttribute(
            .attachment,
            in: range,
            options: .longestEffectiveRangeNotRequired
        ) { attachment, attachmentRange, _ in
            guard let attachment = attachment as? MentionTextAttachment else { return }
            ranges.append(.init(
                location: attachmentRange.location - range.location,
                length: attachmentRange.length,
                address: attachment.address
            ))
        }

        guard !ranges.isEmpty else { return nil }

        return MentionText(text: attributedText.attributedSubstring(from: range).string, ranges: ranges)
    }

    // MARK: - Mention State

    private enum State: Equatable {
        case typingMention(range: NSRange)
        case notTypingMention
    }
    private var state: State = .notTypingMention {
        didSet {
            switch state {
            case .notTypingMention:
                if oldValue != .notTypingMention {
                    mentionDelegate?.textViewDidEndTypingMention(self)
                }
            case .typingMention:
                if oldValue == .notTypingMention {
                    mentionDelegate?.textViewDidBeginTypingMention(self)
                }

                guard let currentlyTypingMentionText = currentlyTypingMentionText else {
                    return owsFailDebug("unexpectedly missing mention text while typing a mention")
                }

                mentionDelegate?.textView(self, didUpdateMentionText: currentlyTypingMentionText)
            }
        }
    }

    private func shouldUpdateMentionText(in range: NSRange, changedText text: String) -> Bool {
        var deletedMentions = [MentionRange]()
        var deletedExactlyOneMention = false

        textStorage.enumerateAttribute(
            .attachment,
            in: range,
            options: .longestEffectiveRangeNotRequired
        ) { attachment, attachmentRange, _ in
            guard let attachment = attachment as? MentionTextAttachment else { return }

            deletedMentions.append(
                MentionRange(nsRange: attachmentRange, address: attachment.address)
            )

            if attachmentRange == range { deletedExactlyOneMention = true }
        }

        for deletedMention in deletedMentions {
            mentionDelegate?.textView(self, didDeleteMention: deletedMention)
        }

        // If the deleted range matched exactly one mention, we'll handle the
        // delete internally. We remove the mention and replace it with an @
        // so the user can start typing a new mention to replace the deleted
        // mention immediately.
        if deletedExactlyOneMention {
            replaceCharacters(in: range, with: Self.mentionPrefix)
            selectedRange = NSRange(location: range.location + Self.mentionPrefixLength, length: 0)
            return false
        }

        return true
    }

    private func updateMentionStateAfterCursorMove() {
        guard selectedRange.length == 0, selectedRange.location > 0, textStorage.length > 0 else {
            state = .notTypingMention
            return
        }

        var location = selectedRange.location

        while location > 0 {
            let possiblePrefix = attributedText.attributedSubstring(
                from: NSRange(location: location - Self.mentionPrefixLength, length: Self.mentionPrefixLength)
            ).string

            // If we find whitespace before the selected range, we're not typing a mention.
            // Mention typing breaks on whitespace.
            if possiblePrefix.unicodeScalars.allSatisfy({ NSCharacterSet.whitespacesAndNewlines.contains($0) }) {
                state = .notTypingMention
                return

            // If we find the mention prefix before the selected range, we may be typing a mention.
            } else if possiblePrefix == Self.mentionPrefix {

                // If there's more text before the mention prefix, check if it's whitespace. Mentions
                // only start at the beginning of the string OR after a whitespace character.
                if location - Self.mentionPrefixLength > 0 {
                    let characterPrecedingPrefix = attributedText.attributedSubstring(
                        from: NSRange(location: location - Self.mentionPrefixLength - 1, length: Self.mentionPrefixLength)
                    ).string

                    // If it's not whitespace, keep looking back. Mention text can contain an "@" character,
                    // for example when trying to match a profile name that contains "@"
                    if !characterPrecedingPrefix.unicodeScalars.allSatisfy({ NSCharacterSet.whitespacesAndNewlines.contains($0) }) {
                        location -= 1
                        continue
                    }
                }

                state = .typingMention(
                    range: NSRange(location: location, length: selectedRange.location - location)
                )
                return
            } else {
                location -= 1
            }
        }

        // We checked everything, so we're not typing
        state = .notTypingMention
    }
}

// MARK: - Cut/Copy/Paste

extension MentionTextView {
    open override func cut(_ sender: Any?) {
        copy(sender)
        replaceCharacters(in: selectedRange, with: "")
    }

    public static let pasteboardType = "private.archived-mention-text"
    open override func copy(_ sender: Any?) {
        guard let plaintextData = textWithPlaintextMentions(in: selectedRange).data(using: .utf8) else {
            return owsFailDebug("Failed to calculate plaintextData on copy")
        }

        if let mentionText = mentionText(in: selectedRange) {
            let encodedMentionText = NSKeyedArchiver.archivedData(withRootObject: mentionText)
            UIPasteboard.general.setItems([[Self.pasteboardType: encodedMentionText]], options: [.localOnly: true])
        } else {
            UIPasteboard.general.setItems([], options: [:])
        }

        UIPasteboard.general.addItems([["public.utf8-plain-text": plaintextData]])
    }

    open override func paste(_ sender: Any?) {
        if let encodedMentionText = UIPasteboard.general.data(forPasteboardType: Self.pasteboardType),
            let mentionText = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MentionText.self, from: encodedMentionText) {
            replaceCharacters(in: selectedRange, with: mentionText)
        } else if let string = UIPasteboard.general.strings?.first {
            replaceCharacters(in: selectedRange, with: string)
        }
    }
}

// MARK: - UITextViewDelegate

extension MentionTextView: UITextViewDelegate {
    open func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard shouldUpdateMentionText(in: range, changedText: text) else { return false }
        return mentionDelegate?.textView?(textView, shouldChangeTextIn: range, replacementText: text) ?? true
    }

    open func textViewDidChangeSelection(_ textView: UITextView) {
        mentionDelegate?.textViewDidChangeSelection?(textView)
        updateMentionStateAfterCursorMove()
    }

    open func textViewDidChange(_ textView: UITextView) {
        mentionDelegate?.textViewDidChange?(textView)
        if textStorage.length == 0 { updateMentionStateAfterCursorMove() }
    }

    open func textView(
        _ textView: UITextView,
        shouldInteractWith textAttachment: NSTextAttachment,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if let mention = textAttachment as? MentionTextAttachment {
            mentionDelegate?.textView(
                self,
                didTapMention: MentionRange(
                    nsRange: characterRange,
                    address: mention.address
                )
            )
        }

        return mentionDelegate?.textView?(
            textView,
            shouldInteractWith: textAttachment,
            in: characterRange,
            interaction: interaction
        ) ?? true
    }

    open func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return mentionDelegate?.textViewShouldBeginEditing?(textView) ?? true
    }

    open func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        return mentionDelegate?.textViewShouldEndEditing?(textView) ?? true
    }

    open func textViewDidBeginEditing(_ textView: UITextView) {
        mentionDelegate?.textViewDidBeginEditing?(textView)
    }

    open func textViewDidEndEditing(_ textView: UITextView) {
        mentionDelegate?.textViewDidEndEditing?(textView)
    }

    open func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        return mentionDelegate?.textView?(textView, shouldInteractWith: URL, in: characterRange, interaction: interaction) ?? true
    }

    open func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
        return mentionDelegate?.textView?(textView, shouldInteractWith: URL, in: characterRange) ?? true
    }

    open func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange) -> Bool {
        return mentionDelegate?.textView?(textView, shouldInteractWith: textAttachment, in: characterRange) ?? true
    }
}
