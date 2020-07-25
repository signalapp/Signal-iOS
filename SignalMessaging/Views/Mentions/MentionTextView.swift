//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol MentionTextViewDelegate: UITextViewDelegate {
    func textViewDidBeginTypingMention(_ textView: MentionTextView)
    func textViewDidEndTypingMention(_ textView: MentionTextView)
    func textView(_ textView: MentionTextView, didUpdateMentionText mentionText: String)

    func textView(_ textView: MentionTextView, didTapMention: MentionTextAttachment)
    func textView(_ textView: MentionTextView, didDeleteMention: MentionTextAttachment)
}

@objc
open class MentionTextView: OWSTextView, UITextViewDelegate {
    public static let mentionPrefix = "@"

    public required init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var delegate: UITextViewDelegate? {
        didSet { owsAssertDebug(delegate === self) }
    }

    public weak var mentionDelegate: MentionTextViewDelegate?

    public func appendMention(_ mention: MentionTextAttachment) {
        insertMention(mention, at: textStorage.length)
    }

    public func insertMention(_ mention: MentionTextAttachment, at location: Int) {
        let beforeFont = font
        textStorage.insert(NSAttributedString(attachment: mention), at: location)
        font = beforeFont
    }

    public func replaceCharacters(in range: NSRange, with mention: MentionTextAttachment) {
        let beforeFont = font
        textStorage.replaceCharacters(in: range, with: NSAttributedString(attachment: mention))
        font = beforeFont
    }

    private(set) var isTypingInMentionRange = false
    private func startTypingMention(mentionText: String) {
        guard !isTypingInMentionRange else {
            mentionDelegate?.textView(self, didUpdateMentionText: mentionText)
            return
        }

        isTypingInMentionRange = true

        mentionDelegate?.textViewDidBeginTypingMention(self)
    }

    private func stopTypingMention() {
        guard isTypingInMentionRange else { return }

        isTypingInMentionRange = false

        mentionDelegate?.textViewDidEndTypingMention(self)
    }

    open func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        var deletingMention: MentionTextAttachment?

        textView.textStorage.enumerateAttribute(
            .attachment,
            in: range,
            options: .longestEffectiveRangeNotRequired
        ) { attachment, attachmentRange, stop in
            guard range == attachmentRange, let attachment = attachment as? MentionTextAttachment else { return }

            deletingMention = attachment
            stop.pointee = true
        }

        if let deletingMention = deletingMention {
            textView.textStorage.replaceCharacters(
                in: range,
                with: NSAttributedString(string: Self.mentionPrefix, attributes: textView.typingAttributes)
            )
            textView.selectedRange = NSRange(location: range.location + 1, length: 0)

            mentionDelegate?.textView(self, didDeleteMention: deletingMention)
            startTypingMention(mentionText: "")
            return false
        } else {
            return mentionDelegate?.textView?(textView, shouldChangeTextIn: range, replacementText: text) ?? true
        }
    }

    open func textViewDidChangeSelection(_ textView: UITextView) {
        mentionDelegate?.textViewDidChangeSelection?(textView)

        guard textView.selectedRange.length == 0,
            textView.selectedRange.location > 0 else { return stopTypingMention() }

        var location = textView.selectedRange.location

        var possibleMentionText = ""

        while location > 0 {
            let previousCharacter = textView.attributedText.attributedSubstring(from: NSRange(location: location - 1, length: 1)).string

            if previousCharacter.unicodeScalars.allSatisfy({ NSCharacterSet.whitespacesAndNewlines.contains($0) }) {
                stopTypingMention()
                break
            } else if previousCharacter == Self.mentionPrefix {
                startTypingMention(mentionText: possibleMentionText)
                break
            } else {
                location -= 1
                possibleMentionText = previousCharacter + possibleMentionText
            }
        }
    }

    open func textView(
        _ textView: UITextView,
        shouldInteractWith textAttachment: NSTextAttachment,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if let mention = textAttachment as? MentionTextAttachment {
            mentionDelegate?.textView(self, didTapMention: mention)
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

    open func textViewDidChange(_ textView: UITextView) {
        mentionDelegate?.textViewDidChange?(textView)
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
