//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

// Coincides with Android's max text message length
let kMaxMessageBodyCharacterCount = 2000

protocol AttachmentTextToolbarDelegate: class {
    func attachmentTextToolbarDidTapSend(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar)
}

// MARK: -

class AttachmentTextToolbar: UIView, UITextViewDelegate {

    // MARK: - Dependencies

    private var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    // MARK: - Properties

    private let options: AttachmentApprovalViewControllerOptions

    weak var attachmentTextToolbarDelegate: AttachmentTextToolbarDelegate?

    var hasPerMessageExpiration: Bool {
        return (options.contains(.canToggleExpiration) &&
                preferences.isPerMessageExpirationEnabled())
    }

    var messageText: String? {
        get {
            // Ignore message text if "per-message expiration" is enabled.
            guard !hasPerMessageExpiration else {
                return nil
            }
            return textView.text
        }

        set {
            textView.text = newValue
            updatePlaceholderTextViewVisibility()
        }
    }

    // Layout Constants

    let kMinTextViewHeight: CGFloat = 38
    var maxTextViewHeight: CGFloat {
        // About ~4 lines in portrait and ~3 lines in landscape.
        // Otherwise we risk obscuring too much of the content.
        return UIDevice.current.orientation.isPortrait ? 160 : 100
    }
    var textViewHeightConstraint: NSLayoutConstraint?
    let kToolbarMargin: CGFloat = 8

    // MARK: - Initializers

    init(options: AttachmentApprovalViewControllerOptions) {
        self.options = options

        super.init(frame: CGRect.zero)

        // Specifying autorsizing mask and an intrinsic content size allows proper
        // sizing when used as an input accessory view.
        self.autoresizingMask = .flexibleHeight
        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = UIColor.clear

        textView.delegate = self

        let sendButton = UIButton(type: .system)
        let sendTitle = NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON", comment: "Label for 'send' button in the 'attachment approval' dialog.")
        sendButton.setTitle(sendTitle, for: .normal)
        sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)
        sendButton.titleLabel?.font = UIFont.ows_mediumFont(withSize: 16)
        sendButton.titleLabel?.textAlignment = .center
        sendButton.tintColor = Theme.galleryHighlightColor
        // Increase hit area of send button
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        perMessageExpirationButton.block = { [weak self] in
            self?.didTapPerMessageExpirationButton()
        }
        // Increase hit area of button
        perMessageExpirationButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        // TODO: Revisit this copy.
        perMessageExpirationLabel.text = NSLocalizedString("PER_MESSAGE_EXPIRATION_ACTIVE_INDICATOR", comment: "Label that indicates that 'per-message expiration' is active.")
        perMessageExpirationLabel.font = UIFont.ows_dynamicTypeSubheadline
        perMessageExpirationLabel.textColor = Theme.darkThemePrimaryColor
        perMessageExpirationLabel.lineBreakMode = .byTruncatingTail
        perMessageExpirationLabel.textAlignment = .center

        // Layout

        // We have to wrap the toolbar items in a content view because iOS (at least on iOS10.3) assigns the inputAccessoryView.layoutMargins
        // when resigning first responder (verified by auditing with `layoutMarginsDidChange`).
        // The effect of this is that if we were to assign these margins to self.layoutMargins, they'd be blown away if the
        // user dismisses the keyboard, giving the input accessory view a wonky layout.
        self.layoutMargins = UIEdgeInsets(top: kToolbarMargin, left: kToolbarMargin, bottom: kToolbarMargin, right: kToolbarMargin)

        let sendWrapper = UIView()
        sendWrapper.addSubview(sendButton)
        let perMessageExpirationWrapper = UIView()
        perMessageExpirationWrapper.addSubview(perMessageExpirationButton)

        let hStackView = UIStackView()
        hStackView.axis = .horizontal
        hStackView.alignment = .fill
        hStackView.spacing = kToolbarMargin
        self.addSubview(hStackView)
        hStackView.autoPinEdgesToSuperviewMargins()

        var views = [ perMessageExpirationWrapper, perMessageExpirationLabel, textContainer, sendWrapper ]
        // UIStackView's horizontal layout is leading-to-trailing.
        // We want left-to-right ordering, so reverse if RTL.
        if CurrentAppContext().isRTL {
            views.reverse()
        }
        for view in views {
            hStackView.addArrangedSubview(view)
        }

        textViewHeightConstraint = textView.autoSetDimension(.height, toSize: kMinTextViewHeight)
        perMessageExpirationLabel.autoSetDimension(.height, toSize: kMinTextViewHeight, relation: .greaterThanOrEqual)

        // We pin edges explicitly rather than doing something like:
        //  textView.autoPinEdges(toSuperviewMarginsExcludingEdge: .right)
        // because that method uses `leading` / `trailing` rather than `left` vs. `right`.
        // So it doesn't work as expected with RTL layouts when we explicitly want something
        // to be on the right side for both RTL and LTR layouts, like with the send button.
        // I believe this is a bug in PureLayout. Filed here: https://github.com/PureLayout/PureLayout/issues/209
        textContainer.autoPinEdge(toSuperviewMargin: .top)
        textContainer.autoPinEdge(toSuperviewMargin: .bottom)

        let layoutButtonWithinWrapper = { (button: UIView) in
            button.autoPinWidthToSuperview()
            button.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
            button.setContentHuggingHigh()
            button.setCompressionResistanceHigh()
        }
        layoutButtonWithinWrapper(sendButton)
        layoutButtonWithinWrapper(perMessageExpirationButton)

        perMessageExpirationWrapper.isHidden = !options.contains(.canToggleExpiration)

        updateContent()
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

    private func updateContent() {
        AssertIsOnMainThread()

        let isPerMessageExpirationEnabled = preferences.isPerMessageExpirationEnabled()
        let imageName = isPerMessageExpirationEnabled ? "timer-24" : "timer-disabled-24"
        perMessageExpirationButton.setTemplateImageName(imageName, tintColor: Theme.darkThemePrimaryColor)

        perMessageExpirationLabel.isHidden = !hasPerMessageExpiration
        textContainer.isHidden = hasPerMessageExpiration

        updateHeight(textView: textView)
    }

    lazy var textView: UITextView = {
        let textView = buildTextView()

        textView.returnKeyType = .done
        textView.scrollIndicatorInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 3)

        return textView
    }()

    private lazy var placeholderTextView: UITextView = {
        let placeholderTextView = buildTextView()

        placeholderTextView.text = NSLocalizedString("MESSAGE_TEXT_FIELD_PLACEHOLDER", comment: "placeholder text for the editable message field")
        placeholderTextView.isEditable = false

        return placeholderTextView
    }()

    private lazy var textContainer: UIView = {
        let textContainer = UIView()

        textContainer.layer.borderColor = Theme.darkThemePrimaryColor.cgColor
        textContainer.layer.borderWidth = CGHairlineWidthFraction(1.4)
        textContainer.layer.cornerRadius = kMinTextViewHeight / 2
        textContainer.clipsToBounds = true

        textContainer.addSubview(placeholderTextView)
        placeholderTextView.autoPinEdgesToSuperviewEdges()

        textContainer.addSubview(textView)
        textView.autoPinEdgesToSuperviewEdges()

        return textContainer
    }()

    private func buildTextView() -> UITextView {
        let textView = AttachmentTextView()

        textView.keyboardAppearance = Theme.darkThemeKeyboardAppearance
        textView.backgroundColor = .clear
        textView.tintColor = Theme.darkThemePrimaryColor

        textView.font = UIFont.ows_dynamicTypeBody
        textView.textColor = Theme.darkThemePrimaryColor
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)

        return textView
    }

    private let perMessageExpirationButton = OWSButton()

    private let perMessageExpirationLabel = UILabel()

    // MARK: - Actions

    @objc
    func didTapSend() {
        assert(attachmentTextToolbarDelegate != nil)

        textView.acceptAutocorrectSuggestion()
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidTapSend(self)
    }

    @objc
    func didTapPerMessageExpirationButton() {
        AssertIsOnMainThread()

        // Toggle value.
        let isPerMessageExpirationEnabled = !preferences.isPerMessageExpirationEnabled()
        preferences.setIsPerMessageExpirationEnabled(isPerMessageExpirationEnabled)

        updateContent()
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateHeight(textView: textView)
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidChange(self)
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Though we can wrap the text, we don't want to encourage multline captions, plus a "done" button
        // allows the user to get the keyboard out of the way while in the attachment approval view.
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        } else {
            return true
        }
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidBeginEditing(self)
        updatePlaceholderTextViewVisibility()
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidEndEditing(self)
        updatePlaceholderTextViewVisibility()
    }

    // MARK: - Helpers

    func updatePlaceholderTextViewVisibility() {
        let isHidden: Bool = {
            guard !self.textView.isFirstResponder else {
                return true
            }

            guard let text = self.textView.text else {
                return false
            }

            guard text.count > 0 else {
                return false
            }

            return true
        }()

        placeholderTextView.isHidden = isHidden
    }

    private func updateHeight(textView: UITextView) {
        guard let textViewHeightConstraint = textViewHeightConstraint else {
            owsFailDebug("Missing constraint.")
            return
        }

        // compute new height assuming width is unchanged
        let currentSize = textView.frame.size
        let textViewHeight = clampedTextViewHeight(fixedWidth: currentSize.width)

        if textViewHeightConstraint.constant != textViewHeight {
            Logger.debug("TextView height changed: \(textViewHeightConstraint.constant) -> \(textViewHeight)")
            textViewHeightConstraint.constant = textViewHeight
            invalidateIntrinsicContentSize()
        }
        textViewHeightConstraint.isActive = !hasPerMessageExpiration
    }

    private func clampedTextViewHeight(fixedWidth: CGFloat) -> CGFloat {
        let contentSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
        return CGFloatClamp(contentSize.height, kMinTextViewHeight, maxTextViewHeight)
    }
}
