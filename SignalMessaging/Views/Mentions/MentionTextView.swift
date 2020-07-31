//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol MentionTextViewDelegate: UITextViewDelegate {
    func textViewDidBeginTypingMention(_ textView: MentionTextView)
    func textViewDidEndTypingMention(_ textView: MentionTextView)

    func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView?
    func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView?
    func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress]

    func textView(_ textView: MentionTextView, didTapMention: Mention)
    func textView(_ textView: MentionTextView, didDeleteMention: Mention)

    func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool
    func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style
}

@objc
open class MentionTextView: OWSTextView {
    @objc
    public weak var mentionDelegate: MentionTextViewDelegate? {
        didSet { updateMentionStateAfterCursorMove() }
    }

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

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }

    deinit {
        pickerView?.removeFromSuperview()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    public func insertTypedMention(address: SignalServiceAddress) {
        guard let mentionDelegate = mentionDelegate else {
            return owsFailDebug("Can't replace characters without delegate")
        }

        guard case .typingMention(let range) = state else {
            return owsFailDebug("Can't finish typing when no mention in progress")
        }

        guard range.location >= Mention.mentionPrefixLength else {
            return owsFailDebug("Invalid mention range \(range)")
        }

        replaceCharacters(
            in: NSRange(
                location: range.location - Mention.mentionPrefixLength,
                length: range.length + Mention.mentionPrefixLength
            ),
            with: Mention(
                address: address,
                style: mentionDelegate.textViewMentionStyle(self)
            ),
            alwaysResolveMention: true
        )

        // Add a space after the typed mention
        replaceCharacters(in: selectedRange, with: " ")
    }

    public func replaceCharacters(in range: NSRange, with mention: Mention, alwaysResolveMention: Bool = false) {
        replaceCharacters(in: range, with: mention, inMutableString: textStorage, alwaysResolveMention: alwaysResolveMention)
    }

    public func replaceCharacters(
        in range: NSRange,
        with mention: Mention,
        inMutableString mutableString: NSMutableAttributedString,
        alwaysResolveMention: Bool = false
    ) {
        guard let mentionDelegate = mentionDelegate else {
            return owsFailDebug("Can't replace characters without delegate")
        }

        let replacementString: NSAttributedString
        if alwaysResolveMention || mentionDelegate.textView(self, shouldResolveMentionForAddress: mention.address) {
            replacementString = mention.attributedString
        } else {
            // If we shouldn't resolve the mention, insert the plaintext representation.
            replacementString = NSAttributedString(string: mention.text, attributes: defaultAttributes)
        }

        if mutableString === textStorage {
            replaceCharacters(in: range, with: replacementString)
        } else {
            mutableString.replaceCharacters(in: range, with: replacementString)
        }
    }

    public func replaceCharacters(in range: NSRange, with messageBody: MessageBody) {
        guard let mentionDelegate = mentionDelegate else {
            return owsFailDebug("Can't replace characters without delegate")
        }

        let attributedMentions = NSMutableAttributedString(string: messageBody.text, attributes: defaultAttributes)

        // We must enumerate the ranges in reverse, so as we replace a ranges
        // text we do not change the previous ranges.
        for (range, uuid) in messageBody.ranges.orderedMentions.reversed() {
            guard range.location >= 0 && range.location + range.length <= (messageBody.text as NSString).length else {
                owsFailDebug("Ignoring invalid range in body ranges \(range)")
                continue
            }

            replaceCharacters(
                in: range,
                with: Mention(
                    address: SignalServiceAddress(uuid: uuid),
                    style: mentionDelegate.textViewMentionStyle(self)
                ),
                inMutableString: attributedMentions
            )
        }

        replaceCharacters(in: range, with: attributedMentions)
    }

    public func replaceCharacters(in range: NSRange, with string: String) {
        replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: defaultAttributes))
    }

    public func replaceCharacters(in range: NSRange, with attributedString: NSAttributedString) {
        let previouslySelectedRange = selectedRange

        textStorage.replaceCharacters(in: range, with: attributedString)

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

    public var defaultAttributes: [NSAttributedString.Key: Any] {
        var defaultAttributes = [NSAttributedString.Key: Any]()
        if let font = font { defaultAttributes[.font] = font }
        if let textColor = textColor { defaultAttributes[.foregroundColor] = textColor }
        return defaultAttributes
    }

    @objc
    public var messageBody: MessageBody {
        get { messageBody(in: NSRange(location: 0, length: textStorage.length)) }
        set {
            replaceCharacters(
                in: NSRange(location: 0, length: textStorage.length),
                with: newValue
            )
        }
    }

    @objc
    public func messageBody(in range: NSRange) -> MessageBody {
        return MessageBody(attributedString: attributedText.attributedSubstring(from: range))
    }

    @objc
    public func stopTypingMention() {
        state = .notTypingMention
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
                if oldValue != .notTypingMention { didEndTypingMention() }
            case .typingMention:
                if oldValue == .notTypingMention {
                    didBeginTypingMention()
                } else {
                    guard let currentlyTypingMentionText = currentlyTypingMentionText else {
                        return owsFailDebug("unexpectedly missing mention text while typing a mention")
                    }

                    didUpdateMentionText(currentlyTypingMentionText)
                }
            }
        }
    }

    private weak var pickerView: MentionPicker?
    private weak var pickerViewTopConstraint: NSLayoutConstraint?
    private func didBeginTypingMention() {
        guard let mentionDelegate = mentionDelegate else { return }

        mentionDelegate.textViewDidBeginTypingMention(self)

        pickerView?.removeFromSuperview()

        let mentionableAddresses = mentionDelegate.textViewMentionPickerPossibleAddresses(self)

        guard !mentionableAddresses.isEmpty else { return }

        guard let pickerReferenceView = mentionDelegate.textViewMentionPickerReferenceView(self),
            let pickerParentView = mentionDelegate.textViewMentionPickerParentView(self) else { return }

        let pickerView = MentionPicker(
            mentionableAddresses: mentionableAddresses,
            style: mentionDelegate.textViewMentionStyle(self)
        ) { [weak self] selectedAddress in
            self?.insertTypedMention(address: selectedAddress)
        }
        self.pickerView = pickerView

        pickerParentView.insertSubview(pickerView, belowSubview: pickerReferenceView)
        pickerView.autoPinWidthToSuperview()
        pickerView.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)

        let animationTopConstraint = pickerView.autoPinEdge(.top, to: .top, of: pickerReferenceView)

        didUpdateMentionText(currentlyTypingMentionText ?? "")

        pickerParentView.layoutIfNeeded()

        let style = mentionDelegate.textViewMentionStyle(self)
        if style == .composingAttachment { pickerView.alpha = 0 }

        // Slide up.
        UIView.animate(withDuration: 0.25) {
            pickerView.alpha = 1
            animationTopConstraint.isActive = false
            self.pickerViewTopConstraint = pickerView.autoPinEdge(.bottom, to: .top, of: pickerReferenceView)
            pickerParentView.layoutIfNeeded()
        }
    }

    private func didEndTypingMention() {
        mentionDelegate?.textViewDidEndTypingMention(self)

        guard let pickerView = pickerView else { return }

        self.pickerView = nil

        let pickerViewTopConstraint = self.pickerViewTopConstraint
        self.pickerViewTopConstraint = nil

        guard let mentionDelegate = mentionDelegate,
            let pickerReferenceView = mentionDelegate.textViewMentionPickerReferenceView(self),
            let pickerParentView = mentionDelegate.textViewMentionPickerParentView(self) else {
                pickerView.removeFromSuperview()
                return
        }

        let style = mentionDelegate.textViewMentionStyle(self)

        // Slide down.
        UIView.animate(withDuration: 0.25, animations: {
            pickerViewTopConstraint?.isActive = false
            pickerView.autoPinEdge(.top, to: .top, of: pickerReferenceView)
            pickerParentView.layoutIfNeeded()

            if style == .composingAttachment { pickerView.alpha = 0 }
        }) { _ in
            pickerView.removeFromSuperview()
        }
    }

    private func didUpdateMentionText(_ text: String) {
        if let pickerView = pickerView, !pickerView.mentionTextChanged(text) {
            state = .notTypingMention
        }
    }

    private func shouldUpdateMentionText(in range: NSRange, changedText text: String) -> Bool {
        var deletedMentions = [NSRange: Mention]()

        if range.length > 0 {
            // Locate any mentions in the edited range.
            textStorage.enumerateAttribute(
                .mention,
                in: range,
                options: []
            ) { mention, subrange, _ in
                guard let mention = mention as? Mention else { return }

                // Get the full range of the mention, we may only be editing a part of it.
                var uniqueMentionRange = NSRange()

                guard textStorage.attribute(
                    .mention,
                    at: subrange.location,
                    longestEffectiveRange: &uniqueMentionRange,
                    in: NSRange(location: 0, length: textStorage.length)
                ) != nil else {
                    return owsFailDebug("Unexpectedly missing mention for subrange")
                }

                deletedMentions[uniqueMentionRange] = mention
            }
        } else if range.location > 0,
            let leftMention = textStorage.attribute(.mention, at: range.location - 1, effectiveRange: nil) as? Mention {
            // If there is a mention to the left, the typing attributes will
            // be the mention's attributes. We don't want that, so we need
            // to reset them here.
            typingAttributes = defaultAttributes

            // If we're not at the start of the string, and we're not replacing
            // any existing characters, check if we're typing in the middle of
            // a mention. If so, we need to delete it.
            var uniqueMentionRange = NSRange()
            if range.location < textStorage.length - 1,
                let rightMention = textStorage.attribute(
                    .mention,
                    at: range.location,
                    longestEffectiveRange: &uniqueMentionRange,
                    in: NSRange(location: 0, length: textStorage.length)
                ) as? Mention,
                leftMention == rightMention {
                deletedMentions[uniqueMentionRange] = leftMention
            }
        }

        for (deletedMentionRange, deletedMention) in deletedMentions {
            mentionDelegate?.textView(self, didDeleteMention: deletedMention)

            // Convert the mention to plain-text, in case we only deleted part of it
            textStorage.setAttributes(defaultAttributes, range: deletedMentionRange)
        }

        // If the deleted range was the last character of a mention, we'll
        // handle the delete internally. We remove the mention and replace it
        // with an @ so the user can start typing a new mention to replace the
        // deleted mention immediately.
        if deletedMentions.count == 1,
            let deletedMentionRange = deletedMentions.keys.first,
            range.length == 1,
            text.isEmpty,
            range.location == deletedMentionRange.location + deletedMentionRange.length - 1 {
            replaceCharacters(in: deletedMentionRange, with: Mention.mentionPrefix)
            selectedRange = NSRange(location: deletedMentionRange.location + Mention.mentionPrefixLength, length: 0)
            return false
        }

        return true
    }

    private func updateMentionStateAfterCursorMove() {
        // If we don't yet have a delegate, we can ignore any updates.
        // We'll check again when the delegate is assigned.
        guard mentionDelegate != nil else { return }

        guard selectedRange.length == 0, selectedRange.location > 0, textStorage.length > 0 else {
            state = .notTypingMention
            return
        }

        var location = selectedRange.location

        while location > 0 {
            let possibleAttributedPrefix = attributedText.attributedSubstring(
                from: NSRange(location: location - Mention.mentionPrefixLength, length: Mention.mentionPrefixLength)
            )

            // If the previous character is part of a mention, we're not typing a mention
            if possibleAttributedPrefix.attribute(.mention, at: 0, effectiveRange: nil) != nil {
                state = .notTypingMention
                return
            }

            let possiblePrefix = possibleAttributedPrefix.string

            // If we find whitespace before the selected range, we're not typing a mention.
            // Mention typing breaks on whitespace.
            if possiblePrefix.unicodeScalars.allSatisfy({ NSCharacterSet.whitespacesAndNewlines.contains($0) }) {
                state = .notTypingMention
                return

            // If we find the mention prefix before the selected range, we may be typing a mention.
            } else if possiblePrefix == Mention.mentionPrefix {

                // If there's more text before the mention prefix, check if it's whitespace. Mentions
                // only start at the beginning of the string OR after a whitespace character.
                if location - Mention.mentionPrefixLength > 0 {
                    let characterPrecedingPrefix = attributedText.attributedSubstring(
                        from: NSRange(location: location - Mention.mentionPrefixLength - 1, length: Mention.mentionPrefixLength)
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

    // MARK: -

    @objc
    private func didTap(_ sender: UITapGestureRecognizer) {
        var tapPoint = sender.location(in: self)
        tapPoint.x -= textContainerInset.left
        tapPoint.y -= textContainerInset.right

        let tappedCharacterIndex = layoutManager.characterIndex(
            for: tapPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard tappedCharacterIndex > 0, tappedCharacterIndex < textStorage.length else { return }

        guard let tappedMention = textStorage.attribute(
            .mention,
            at: tappedCharacterIndex,
            effectiveRange: nil
        ) as? Mention else { return }

        mentionDelegate?.textView(self, didTapMention: tappedMention)
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
        guard let plaintextData = attributedText.attributedSubstring(from: selectedRange).string.data(using: .utf8) else {
            return owsFailDebug("Failed to calculate plaintextData on copy")
        }

        let messageBody = self.messageBody(in: selectedRange)

        if messageBody.hasRanges {
            let encodedMessageBody = NSKeyedArchiver.archivedData(withRootObject: messageBody)
            UIPasteboard.general.setItems([[Self.pasteboardType: encodedMessageBody]], options: [.localOnly: true])
        } else {
            UIPasteboard.general.setItems([], options: [:])
        }

        UIPasteboard.general.addItems([["public.utf8-plain-text": plaintextData]])
    }

    open override func paste(_ sender: Any?) {
        if let encodedMessageBody = UIPasteboard.general.data(forPasteboardType: Self.pasteboardType),
            let messageBody = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MessageBody.self, from: encodedMessageBody) {
            replaceCharacters(in: selectedRange, with: messageBody)
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

    open func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        return mentionDelegate?.textView?(textView, shouldInteractWith: textAttachment, in: characterRange, interaction: interaction) ?? true
    }

    open func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
        return mentionDelegate?.textView?(textView, shouldInteractWith: URL, in: characterRange) ?? true
    }

    open func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange) -> Bool {
        return mentionDelegate?.textView?(textView, shouldInteractWith: textAttachment, in: characterRange) ?? true
    }
}

extension MentionTextView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
