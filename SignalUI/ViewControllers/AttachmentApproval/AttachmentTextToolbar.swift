//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging

// Coincides with Android's max text message length
let kMaxMessageBodyCharacterCount = 2000

protocol AttachmentTextToolbarDelegate: AnyObject {
    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar)
}

// MARK: -

class AttachmentTextToolbar: UIView {

    // Forward text editing-related events to AttachmentApprovalToolbar.
    weak var delegate: AttachmentTextToolbarDelegate?

    // Forward mention-related calls directly to the view controller.
    weak var mentionTextViewDelegate: MentionTextViewDelegate?

    private var isViewOnceEnabled: Bool = false
    func setIsViewOnce(enabled: Bool, animated: Bool) {
        guard isViewOnceEnabled != enabled else { return }
        isViewOnceEnabled = enabled
        updateContent(animated: animated)
    }

    var isEditingText: Bool {
        textView.isFirstResponder
    }

    var messageBody: MessageBody? {
        get {
            // Ignore message text if "view-once" is enabled.
            guard !isViewOnceEnabled else {
                return nil
            }
            return textView.messageBody
        }

        set {
            textView.messageBody = newValue
            updateAppearance(animated: false)
        }
    }

    // MARK: - Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Specifying autoresizing mask and an intrinsic content size allows proper
        // sizing when used as an input accessory view.
        autoresizingMask = .flexibleHeight
        preservesSuperviewLayoutMargins = true
        translatesAutoresizingMaskIntoConstraints = false
        layoutMargins.top = 10
        layoutMargins.bottom = 10

        textView.mentionDelegate = self

        // Layout

        addSubview(textViewContainer)
        textViewContainer.autoPinEdgesToSuperviewMargins()

        // We pin edges explicitly rather than doing something like:
        //  textView.autoPinEdges(toSuperviewMarginsExcludingEdge: .right)
        // because that method uses `leading` / `trailing` rather than `left` vs. `right`.
        // So it doesn't work as expected with RTL layouts when we explicitly want something
        // to be on the right side for both RTL and LTR layouts, like with the send button.
        // I believe this is a bug in PureLayout. Filed here: https://github.com/PureLayout/PureLayout/issues/209
        textViewWrapperView.autoPinEdge(toSuperviewMargin: .top)
        textViewWrapperView.autoPinEdge(toSuperviewMargin: .bottom)

        addSubview(addMessageButton)
        addMessageButton.autoPinEdgesToSuperviewMargins()
        addConstraint({
            let constraint = addMessageButton.heightAnchor.constraint(equalToConstant: kMinTextViewHeight)
            constraint.priority = UILayoutPriority.defaultLow
            return constraint
        }())

        addSubview(viewOnceMediaLabel)
        viewOnceMediaLabel.autoPinEdgesToSuperviewMargins()
        addConstraint({
            let constraint = viewOnceMediaLabel.heightAnchor.constraint(equalToConstant: kMinTextViewHeight)
            constraint.priority = UILayoutPriority.defaultLow
            return constraint
        }())

        updateContent(animated: false)
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIView Overrides

    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    override var intrinsicContentSize: CGSize { .zero }

    // MARK: - Subviews

    private let kMinTextViewHeight: CGFloat = 36
    private var maxTextViewHeight: CGFloat {
        // About ~4 lines in portrait and ~3 lines in landscape.
        // Otherwise we risk obscuring too much of the content.
        return UIDevice.current.orientation.isPortrait ? 160 : 100
    }
    private lazy var textViewMinimumHeightConstraint: NSLayoutConstraint = {
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: kMinTextViewHeight)
    }()
    private lazy var textViewHeightConstraint: NSLayoutConstraint = {
        textView.heightAnchor.constraint(equalToConstant: kMinTextViewHeight)
    }()

    private func updateContent(animated: Bool) {
        AssertIsOnMainThread()
        updateAppearance(animated: animated)
        updateHeight()
    }

    private func updateAppearance(animated: Bool) {
        let hasText: Bool = {
            guard let text = self.textView.text else {
                return false
            }
            return !text.isEmpty
        }()

        addMessageButton.setIsHidden(hasText || isEditingText || isViewOnceEnabled, animated: animated)
        viewOnceMediaLabel.setIsHidden(!isViewOnceEnabled, animated: animated)
        textViewContainer.setIsHidden((!hasText && !isEditingText) || isViewOnceEnabled, animated: animated)
        placeholderTextView.setIsHidden(hasText, animated: animated)
        doneButton.setIsHidden(!isEditingText, animated: animated)

        if let blueCircleView = doneButton.subviews.first(where: { $0 is CircleView }) {
            doneButton.sendSubviewToBack(blueCircleView)
        }
    }

    lazy private(set) var textView: MentionTextView = {
        let textView = buildTextView()
        textView.returnKeyType = .done
        textView.scrollIndicatorInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 3)
        textView.mentionDelegate = self
        return textView
    }()

    private let placeholderText = OWSLocalizedString("MEDIA_EDITOR_TEXT_FIELD_ADD_MESSAGE", comment: "Placeholder for message text input field in media editor.")

    private lazy var placeholderTextView: UITextView = {
        let placeholderTextView = buildTextView()
        placeholderTextView.text = placeholderText
        placeholderTextView.isEditable = false
        placeholderTextView.isUserInteractionEnabled = false
        placeholderTextView.textContainer.maximumNumberOfLines = 1
        placeholderTextView.textContainer.lineBreakMode = .byTruncatingTail
        placeholderTextView.textColor = .ows_gray45
        return placeholderTextView
    }()

    private lazy var addMessageButton: UIButton = {
        let button = OWSButton(title: placeholderText) { [weak self] in
            guard let self = self else { return }
            self.didTapAddMessage()
        }
        button.setTitleColor(.ows_white, for: .normal)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.font = .ows_dynamicTypeBodyClamped
        return button
    }()

    private lazy var viewOnceMediaLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString("MEDIA_EDITOR_TEXT_FIELD_VIEW_ONCE_MEDIA", comment: "Shown in place of message input text in media editor when 'View Once' is on.")
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        label.textColor = .ows_whiteAlpha50
        label.font = .ows_dynamicTypeBodyClamped
        return label
    }()

    private lazy var textViewContainer: UIView = {
        let hStackView = UIStackView(arrangedSubviews: [ textViewWrapperView, doneButton ])
        hStackView.axis = .horizontal
        hStackView.alignment = .bottom
        hStackView.spacing = 4
        return hStackView
    }()

    private lazy var doneButton: UIButton = {
        let doneButton = OWSButton(imageName: "check-24", tintColor: .white) { [weak self] in
            guard let self = self else { return }
            self.didTapFinishEditing()
        }
        let visibleButtonSize = kMinTextViewHeight
        doneButton.layoutMargins = UIEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        doneButton.contentEdgeInsets = doneButton.layoutMargins
        doneButton.accessibilityLabel = CommonStrings.doneButton
        let blueCircle = CircleView(diameter: visibleButtonSize)
        blueCircle.backgroundColor = .ows_accentBlue
        blueCircle.isUserInteractionEnabled = false
        doneButton.addSubview(blueCircle)
        doneButton.sendSubviewToBack(blueCircle)
        blueCircle.autoPinEdgesToSuperviewMargins()
        return doneButton
    }()

    private lazy var textViewWrapperView: UIView = {
        let backgroundView = UIView()
        backgroundView.backgroundColor = .ows_gray80
        backgroundView.layer.cornerRadius = kMinTextViewHeight / 2
        backgroundView.clipsToBounds = true

        let wrapperView = UIView()
        wrapperView.addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        wrapperView.addSubview(textView)
        textView.autoPinEdgesToSuperviewEdges()
        wrapperView.addConstraint(textViewHeightConstraint)
        wrapperView.addConstraint(textViewMinimumHeightConstraint)

        wrapperView.addSubview(placeholderTextView)
        placeholderTextView.autoPinEdges(toEdgesOf: textView)

        return wrapperView
    }()

    private func buildTextView() -> MentionTextView {
        let textView = AttachmentTextView()
        textView.keyboardAppearance = Theme.darkThemeKeyboardAppearance
        textView.backgroundColor = .clear
        textView.tintColor = Theme.darkThemePrimaryColor
        textView.font = .ows_dynamicTypeBodyClamped
        textView.textColor = Theme.darkThemePrimaryColor
        textView.textContainerInset.left = 7
        textView.textContainerInset.right = 7
        return textView
    }
}

// MARK: - Actions

extension AttachmentTextToolbar {

    @objc
    private func didTapFinishEditing() {
        textView.acceptAutocorrectSuggestion()
        textView.resignFirstResponder()
    }

    @objc
    private func didTapAddMessage() {
        guard !isViewOnceEnabled else { return }
        textView.becomeFirstResponder()
    }
}

extension AttachmentTextToolbar: MentionTextViewDelegate {

    func textViewDidBeginTypingMention(_ textView: MentionTextView) {
        mentionTextViewDelegate?.textViewDidBeginTypingMention(textView)
    }

    func textViewDidEndTypingMention(_ textView: MentionTextView) {
        mentionTextViewDelegate?.textViewDidEndTypingMention(textView)
    }

    func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        return mentionTextViewDelegate?.textViewMentionPickerParentView(textView)
    }

    func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        return mentionTextViewDelegate?.textViewMentionPickerReferenceView(textView)
    }

    func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        return mentionTextViewDelegate?.textViewMentionPickerPossibleAddresses(textView) ?? []
    }

    func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {}

    func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .composingAttachment
    }
}

extension AttachmentTextToolbar: UITextViewDelegate {

    public func textViewDidChange(_ textView: UITextView) {
        updateContent(animated: false)
        delegate?.attachmentTextToolbarDidChange(self)
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

    public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        // Putting these lines in `textViewDidBeginEditing` doesn't work.
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        return true
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        // Making textView think its content has changed is necessary
        // in order to get correct textView size and expand it to multiple lines if necessary.
        textView.layoutManager.processEditing(for: textView.textStorage,
                                              edited: .editedCharacters,
                                              range: NSRange(location: 0, length: 0),
                                              changeInLength: 0,
                                              invalidatedRange: NSRange(location: 0, length: 0))
        delegate?.attachmentTextToolbarDidBeginEditing(self)
        updateContent(animated: true)
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        textView.textContainer.lineBreakMode = .byTruncatingTail
        textView.textContainer.maximumNumberOfLines = 1
        delegate?.attachmentTextToolbarDidEndEditing(self)
        updateContent(animated: true)
    }
}

extension AttachmentTextToolbar {

    private func updateHeight() {
        // Minimum text area size defines text field size when input field isn't active.
        let placeholderTextViewHeight = clampedHeight(for: placeholderTextView)
        textViewMinimumHeightConstraint.constant = placeholderTextViewHeight

        // Always keep height of the text field in expanded state current.
        let textViewHeight = clampedHeight(for: textView)
        if textViewHeightConstraint.constant != textViewHeight {
            Logger.debug("TextView height changed: \(textViewHeightConstraint.constant) -> \(textViewHeight)")
            textViewHeightConstraint.constant = textViewHeight
            invalidateIntrinsicContentSize()
        }
        textViewHeightConstraint.isActive = isEditingText
    }

    private func clampedHeight(for textView: UITextView) -> CGFloat {
        let fixedWidth = textView.width
        let contentSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
        return CGFloatClamp(contentSize.height, kMinTextViewHeight, maxTextViewHeight)
    }
}
