//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging

public protocol MentionTextViewDelegate: UITextViewDelegate {
    func textViewDidBeginTypingMention(_ textView: MentionTextView)
    func textViewDidEndTypingMention(_ textView: MentionTextView)

    func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView?
    func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView?
    func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress]

    func textView(_ textView: MentionTextView, didDeleteMention: Mention)

    func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style
}

open class MentionTextView: OWSTextView {

    public weak var mentionDelegate: MentionTextViewDelegate? {
        didSet { updateMentionState() }
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
        updateTextContainerInset()
        delegate = self
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
            with: Mention.withSneakyTransaction(
                address: address,
                style: mentionDelegate.textViewMentionStyle(self)
            )
        )

        // Add a space after the typed mention
        replaceCharacters(in: selectedRange, with: " ")
    }

    public func replaceCharacters(
        in range: NSRange,
        with mention: Mention
    ) {
        guard let mentionDelegate = mentionDelegate else {
            return owsFailDebug("Can't replace characters without delegate")
        }

        let replacementString: NSAttributedString
        if mentionDelegate.textViewMentionPickerPossibleAddresses(self).contains(mention.address) {
            replacementString = mention.attributedString
        } else {
            // If we shouldn't resolve the mention, insert the plaintext representation.
            replacementString = NSAttributedString(string: mention.text, attributes: defaultAttributes)
        }

        replaceCharacters(in: range, with: replacementString)
    }

    public func replaceCharacters(in range: NSRange, with messageBody: MessageBody) {
        guard let mentionDelegate = mentionDelegate else {
            return owsFailDebug("Can't replace characters without delegate")
        }

        // This might perform a sneaky transaction, so needs to be outside the
        // read block below.
        let possibleMentionAddresses = mentionDelegate.textViewMentionPickerPossibleAddresses(self)

        let attributedBody = SDSDatabaseStorage.shared.read { transaction in
            messageBody.attributedBody(
                style: mentionDelegate.textViewMentionStyle(self),
                attributes: self.defaultAttributes,
                shouldResolveAddress: { possibleMentionAddresses.contains($0) },
                transaction: transaction.unwrapGrdbRead
            )
        }

        replaceCharacters(in: range, with: attributedBody)
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

    public var messageBody: MessageBody? {
        get { MessageBody(attributedString: attributedText) }
        set {
            guard let newValue = newValue else {
                replaceCharacters(
                    in: textStorage.entireRange,
                    with: ""
                )
                typingAttributes = defaultAttributes
                return
            }
            replaceCharacters(
                in: textStorage.entireRange,
                with: newValue
            )
        }
    }

    public func stopTypingMention() {
        state = .notTypingMention
    }

    public func reloadMentionState() {
        stopTypingMention()
        updateMentionState()
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
        pickerView.autoPinEdge(toSuperviewSafeArea: .top, withInset: 0, relation: .greaterThanOrEqual)

        let animationTopConstraint = pickerView.autoPinEdge(.top, to: .top, of: pickerReferenceView)

        guard let currentlyTypingMentionText = currentlyTypingMentionText,
            pickerView.mentionTextChanged(currentlyTypingMentionText) else {
                pickerView.removeFromSuperview()
                self.pickerView = nil
                state = .notTypingMention
                return
        }

        ImpactHapticFeedback.impactOccured(style: .light)

        pickerParentView.layoutIfNeeded()

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
            textStorage.enumerateMentions(in: range) { mention, subrange, _ in
                guard let mention = mention else { return }

                // Get the full range of the mention, we may only be editing a part of it.
                var uniqueMentionRange = NSRange()

                guard textStorage.attribute(
                    .mention,
                    at: subrange.location,
                    longestEffectiveRange: &uniqueMentionRange,
                    in: textStorage.entireRange
                ) != nil else {
                    return owsFailDebug("Unexpectedly missing mention for subrange")
                }

                deletedMentions[uniqueMentionRange] = mention
            }
        } else if range.location > 0,
            let leftMention = textStorage.attribute(
                .mention,
                at: range.location - 1,
                effectiveRange: nil
            ) as? Mention {
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
                    in: textStorage.entireRange
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

    private func updateMentionState() {
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

    // MARK: - Text Container Insets

    open var defaultTextContainerInset: UIEdgeInsets {
        UIEdgeInsets(hMargin: 7, vMargin: 7 - CGHairlineWidth())
    }

    public func updateTextContainerInset() {
        var newTextContainerInset = defaultTextContainerInset

        let currentFont = font ?? UIFont.ows_dynamicTypeBody
        let systemDefaultFont = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: .init(preferredContentSizeCategory: .large)
        )
        guard systemDefaultFont.pointSize > currentFont.pointSize else {
            textContainerInset = newTextContainerInset
            return
        }

        // Increase top and bottom insets so that textView has the same one-line height
        // for any content size category smaller than the default (Large).
        // Simply fixing textView at a minimum height doesn't work well because
        // smaller text will be top-aligned (and we want center).
        let insetFontAdjustment = (systemDefaultFont.ascender - systemDefaultFont.descender) - (currentFont.ascender - currentFont.descender)
        newTextContainerInset.top += insetFontAdjustment * 0.5
        newTextContainerInset.bottom = newTextContainerInset.top - 1
        textContainerInset = newTextContainerInset
    }
}

// MARK: - Picker Keyboard Interaction

extension MentionTextView {
    open override var keyCommands: [UIKeyCommand]? {
        guard pickerView != nil else { return nil }

        return [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(upArrowPressed(_:))),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(downArrowPressed(_:))),
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(returnPressed(_:))),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabPressed(_:)))
        ]
    }

    @objc
    func upArrowPressed(_ sender: UIKeyCommand) {
        guard let pickerView = pickerView else { return }
        pickerView.didTapUpArrow()
    }

    @objc
    func downArrowPressed(_ sender: UIKeyCommand) {
        guard let pickerView = pickerView else { return }
        pickerView.didTapDownArrow()
    }

    @objc
    func returnPressed(_ sender: UIKeyCommand) {
        guard let pickerView = pickerView else { return }
        pickerView.didTapReturn()
    }

    @objc
    func tabPressed(_ sender: UIKeyCommand) {
        guard let pickerView = pickerView else { return }
        pickerView.didTapTab()
    }
}

// MARK: - Cut/Copy/Paste

extension MentionTextView {
    open override func cut(_ sender: Any?) {
        copy(sender)
        replaceCharacters(in: selectedRange, with: "")
    }

    public class func copyAttributedStringToPasteboard(_ attributedString: NSAttributedString) {
        guard let plaintextData = attributedString.string.data(using: .utf8) else {
            return owsFailDebug("Failed to calculate plaintextData on copy")
        }

        let messageBody = MessageBody(attributedString: attributedString)

        // TODO[TextFormatting]: apply text styles to copy pasted things?
        if messageBody.hasMentions, let encodedMessageBody = try? NSKeyedArchiver.archivedData(withRootObject: messageBody, requiringSecureCoding: true) {
            UIPasteboard.general.setItems([[Self.pasteboardType: encodedMessageBody]], options: [.localOnly: true])
        } else {
            UIPasteboard.general.setItems([], options: [:])
        }

        UIPasteboard.general.addItems([["public.utf8-plain-text": plaintextData]])
    }

    public static var pasteboardType: String { SignalAttachment.mentionPasteboardType }

    open override func copy(_ sender: Any?) {
        Self.copyAttributedStringToPasteboard(attributedText.attributedSubstring(from: selectedRange))
    }

    open override func paste(_ sender: Any?) {
        if let encodedMessageBody = UIPasteboard.general.data(forPasteboardType: Self.pasteboardType),
            let messageBody = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MessageBody.self, from: encodedMessageBody) {
            replaceCharacters(in: selectedRange, with: messageBody)
        } else if let string = UIPasteboard.general.strings?.first {
            replaceCharacters(in: selectedRange, with: string)
        }

        if !textStorage.isEmpty {
            // Pasting very long text generates an obscure UI error producing an UITextView where the lower
            // part contains invisible characters. The exact root of the issue is still unclear but the following
            // lines of code work as a workaround.
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) { [weak self] in
                if let self = self {
                    let oldRange = self.selectedRange
                    self.selectedRange = NSRange.init(location: 0, length: 0)
                    // inserting blank text into the text storage will remove the invisible characters
                    self.textStorage.insert(NSAttributedString(string: ""), at: 0)
                    // setting the range (again) will ensure scrolling to the correct position
                    self.selectedRange = oldRange
                }
            }
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
        updateMentionState()
    }

    open func textViewDidChange(_ textView: UITextView) {
        mentionDelegate?.textViewDidChange?(textView)
        if textStorage.length == 0 { updateMentionState() }
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
}
