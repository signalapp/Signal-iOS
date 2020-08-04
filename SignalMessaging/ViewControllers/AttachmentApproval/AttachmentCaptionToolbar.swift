//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

protocol AttachmentCaptionToolbarDelegate: class {
    func attachmentCaptionToolbarDidEdit(_ attachmentCaptionToolbar: AttachmentCaptionToolbar)
    func attachmentCaptionToolbarDidComplete()
}

// MARK: -

class AttachmentCaptionToolbar: UIView, MentionTextViewDelegate {

    private let kMaxCaptionCharacterCount = 240

    weak var attachmentCaptionToolbarDelegate: AttachmentCaptionToolbarDelegate?

    var messageText: String? {
        get { return textView.text }

        set {
            textView.text = newValue
        }
    }

    // Layout Constants

    let kMinTextViewHeight: CGFloat = 38
    var maxTextViewHeight: CGFloat {
        // About ~4 lines in portrait and ~3 lines in landscape.
        // Otherwise we risk obscuring too much of the content.
        return UIDevice.current.orientation.isPortrait ? 160 : 100
    }
    var textViewHeightConstraint: NSLayoutConstraint!
    var textViewHeight: CGFloat

    // MARK: - Initializers

    init() {
        self.textViewHeight = kMinTextViewHeight

        super.init(frame: CGRect.zero)

        // Specifying autorsizing mask and an intrinsic content size allows proper
        // sizing when used as an input accessory view.
        self.autoresizingMask = .flexibleHeight
        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = UIColor.clear

        textView.mentionDelegate = self

        // Layout
        let kToolbarMargin: CGFloat = 8

        self.textViewHeightConstraint = textView.autoSetDimension(.height, toSize: kMinTextViewHeight)

        let contentView = UIStackView(arrangedSubviews: [textContainer])
        // We have to wrap the toolbar items in a content view because iOS (at least on iOS10.3) assigns the inputAccessoryView.layoutMargins
        // when resigning first responder (verified by auditing with `layoutMarginsDidChange`).
        // The effect of this is that if we were to assign these margins to self.layoutMargins, they'd be blown away if the
        // user dismisses the keyboard, giving the input accessory view a wonky layout.
        contentView.layoutMargins = UIEdgeInsets(top: kToolbarMargin, left: kToolbarMargin, bottom: kToolbarMargin, right: kToolbarMargin)
        contentView.axis = .vertical
        addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - UIView Overrides

    override var intrinsicContentSize: CGSize {
        get {
            // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
            // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
            return CGSize.zero
        }
    }

    // MARK: - Subviews

    lazy var textView: MentionTextView = {
        let textView = buildTextView()

        textView.returnKeyType = .done
        textView.scrollIndicatorInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 3)

        return textView
    }()

    private lazy var textContainer: UIView = {
        let textContainer = UIView()
        textContainer.clipsToBounds = true
        textContainer.addSubview(textView)
        textView.autoPinEdgesToSuperviewEdges()
        return textContainer
    }()

    private func buildTextView() -> MentionTextView {
        let textView = AttachmentTextView()

        textView.keyboardAppearance = Theme.darkThemeKeyboardAppearance
        textView.backgroundColor = .clear
        textView.tintColor = Theme.darkThemePrimaryColor

        textView.font = UIFont.ows_dynamicTypeBody
        textView.textColor = Theme.darkThemePrimaryColor
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)

        return textView
    }

    // MARK: - MentionTextViewDelegate

    func textViewDidBeginTypingMention(_ textView: MentionTextView) {}

    func textViewDidEndTypingMention(_ textView: MentionTextView) {}

    func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        return nil
    }

    func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        return nil
    }

    func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        return []
    }

    func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {}

    func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool {
        return false
    }

    func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .composing
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateHeight(textView: textView)

        attachmentCaptionToolbarDelegate?.attachmentCaptionToolbarDidEdit(self)
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Though we can wrap the text, we don't want to encourage multline captions, plus a "done" button
        // allows the user to get the keyboard out of the way while in the attachment approval view.
        if text == "\n" {
            attachmentCaptionToolbarDelegate?.attachmentCaptionToolbarDidComplete()
            return false
        } else {
            return true
        }
    }

    // MARK: - Helpers

    private func updateHeight(textView: UITextView) {
        // compute new height assuming width is unchanged
        let currentSize = textView.frame.size
        let newHeight = clampedTextViewHeight(fixedWidth: currentSize.width)

        if newHeight != textViewHeight {
            Logger.debug("TextView height changed: \(textViewHeight) -> \(newHeight)")
            textViewHeight = newHeight
            textViewHeightConstraint?.constant = textViewHeight
            invalidateIntrinsicContentSize()
        }
    }

    private func clampedTextViewHeight(fixedWidth: CGFloat) -> CGFloat {
        let contentSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
        return CGFloatClamp(contentSize.height, kMinTextViewHeight, maxTextViewHeight)
    }
}
