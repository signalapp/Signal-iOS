//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SessionUIKit

protocol AttachmentCaptionToolbarDelegate: AnyObject {
    func attachmentCaptionToolbarDidEdit(_ attachmentCaptionToolbar: AttachmentCaptionToolbar)
    func attachmentCaptionToolbarDidComplete()
}

// MARK: -

class AttachmentCaptionToolbar: UIView, UITextViewDelegate {

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
        self.themeBackgroundColor = .clear

        textView.delegate = self

        // Layout
        let kToolbarMargin: CGFloat = 8

        self.textViewHeightConstraint = textView.autoSetDimension(.height, toSize: kMinTextViewHeight)

        lengthLimitLabel.setContentHuggingHigh()
        lengthLimitLabel.setCompressionResistanceHigh()

        let contentView = UIStackView(arrangedSubviews: [textContainer, lengthLimitLabel])
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

    private lazy var lengthLimitLabel: UILabel = {
        let lengthLimitLabel = UILabel()

        // Length Limit Label shown when the user inputs too long of a message
        lengthLimitLabel.themeTextColor = .textPrimary
        lengthLimitLabel.text = NSLocalizedString("ATTACHMENT_APPROVAL_MESSAGE_LENGTH_LIMIT_REACHED", comment: "One-line label indicating the user can add no more text to the media message field.")
        lengthLimitLabel.textAlignment = .center

        // Add shadow in case overlayed on white content
        lengthLimitLabel.themeShadowColor = .black
        lengthLimitLabel.layer.shadowOffset = .zero
        lengthLimitLabel.layer.shadowOpacity = 0.8
        lengthLimitLabel.layer.shadowRadius = 2.0
        lengthLimitLabel.isHidden = true

        return lengthLimitLabel
    }()

    lazy var textView: UITextView = {
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

    private func buildTextView() -> UITextView {
        let textView = AttachmentTextView()

        textView.themeBackgroundColor = .clear
        textView.themeTintColor = .textPrimary

        textView.font = UIFont.ows_dynamicTypeBody
        textView.themeTextColor = .textPrimary
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)
        
        ThemeManager.onThemeChange(observer: textView) { [weak textView] theme, _ in
            textView?.keyboardAppearance = theme.keyboardAppearance
        }

        return textView
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateHeight(textView: textView)

        attachmentCaptionToolbarDelegate?.attachmentCaptionToolbarDidEdit(self)
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let existingText: String = textView.text ?? ""
        let proposedText: String = (existingText as NSString).replacingCharacters(in: range, with: text)

        // Don't complicate things by mixing media attachments with oversize text attachments
        guard proposedText.utf8.count < kOversizeTextMessageSizeThreshold else {
            Logger.debug("long text was truncated")
            self.lengthLimitLabel.isHidden = false

            // `range` represents the section of the existing text we will replace. We can re-use that space.
            // Range is in units of NSStrings's standard UTF-16 characters. Since some of those chars could be
            // represented as single bytes in utf-8, while others may be 8 or more, the only way to be sure is
            // to just measure the utf8 encoded bytes of the replaced substring.
            let bytesAfterDelete: Int = (existingText as NSString).replacingCharacters(in: range, with: "").utf8.count

            // Accept as much of the input as we can
            let byteBudget: Int = Int(kOversizeTextMessageSizeThreshold) - bytesAfterDelete
            if byteBudget >= 0, let acceptableNewText = text.truncated(toByteCount: UInt(byteBudget)) {
                textView.text = (existingText as NSString).replacingCharacters(in: range, with: acceptableNewText)
            }

            return false
        }
        self.lengthLimitLabel.isHidden = true

        // After verifying the byte-length is sufficiently small, verify the character count is within bounds.
        guard proposedText.count < kMaxCaptionCharacterCount else {
            Logger.debug("hit attachment message body character count limit")

            self.lengthLimitLabel.isHidden = false

            // `range` represents the section of the existing text we will replace. We can re-use that space.
            let charsAfterDelete: Int = (existingText as NSString).replacingCharacters(in: range, with: "").count

            // Accept as much of the input as we can
            let charBudget: Int = Int(kMaxCaptionCharacterCount) - charsAfterDelete
            if charBudget >= 0 {
                let acceptableNewText = String(text.prefix(charBudget))
                textView.text = (existingText as NSString).replacingCharacters(in: range, with: acceptableNewText)
            }

            return false
        }

        // Though we can wrap the text, we don't want to encourage multline captions, plus a "done" button
        // allows the user to get the keyboard out of the way while in the attachment approval view.
        if text == "\n" {
            attachmentCaptionToolbarDelegate?.attachmentCaptionToolbarDidComplete()
            return false
        }
        
        return true
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
