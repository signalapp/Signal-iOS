//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI
import UIKit

// Coincides with Android's max text message length
let kMaxMessageBodyCharacterCount = 2000

protocol StoryReplyInputToolbarDelegate: AnyObject {
    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarDidTapReact(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarMentionPickerPossibleAddresses(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> [SignalServiceAddress]
    func storyReplyInputToolbarMentionPickerReferenceView(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> UIView?
    func storyReplyInputToolbarMentionPickerParentView(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> UIView?
}

// MARK: -

class StoryReplyInputToolbar: UIView {

    weak var delegate: StoryReplyInputToolbarDelegate?
    let quotedReplyModel: QuotedReplyModel?

    var messageBody: MessageBody? {
        get { textView.messageBody }
        set {
            textView.messageBody = newValue
            updateContent(animated: false)
        }
    }

    override var bounds: CGRect {
        didSet {
            guard oldValue.height != bounds.height else { return }
            delegate?.storyReplyInputToolbarHeightDidChange(self)
        }
    }

    private let minTextViewHeight: CGFloat = 36
    private var maxTextViewHeight: CGFloat {
        // About ~4 lines in portrait and ~3 lines in landscape.
        // Otherwise we risk obscuring too much of the content.
        return UIDevice.current.orientation.isPortrait ? 160 : 100
    }
    private var textViewHeightConstraint: NSLayoutConstraint?

    // MARK: - Initializers

    init(quotedReplyModel: QuotedReplyModel? = nil) {
        self.quotedReplyModel = quotedReplyModel
        super.init(frame: CGRect.zero)

        // When presenting or dismissing the keyboard, there may be a slight
        // gap between the keyboard and the bottom of the input bar during
        // the animation. Extend the background below the toolbar's bounds
        // by this much to mask that extra space.
        let backgroundExtension: CGFloat = 500

        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundColor = .ows_black

            let extendedBackground = UIView()
            addSubview(extendedBackground)
            extendedBackground.autoPinWidthToSuperview()
            extendedBackground.autoPinEdge(.top, to: .bottom, of: self)
            extendedBackground.autoSetDimension(.height, toSize: backgroundExtension)
        } else {
            backgroundColor = .clear

            let blurEffect: UIBlurEffect
            if quotedReplyModel != nil {
                blurEffect = UIBlurEffect(style: .systemThickMaterialDark)
            } else {
                blurEffect = Theme.darkThemeBarBlurEffect
            }
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            blurEffectView.layer.zPosition = -1
            addSubview(blurEffectView)
            blurEffectView.autoPinWidthToSuperview()
            blurEffectView.autoPinEdge(toSuperviewEdge: .top)
            blurEffectView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -backgroundExtension)
        }

        textView.mentionDelegate = self

        // The input toolbar should *always* be laid out left-to-right, even when using
        // a right-to-left language. The convention for messaging apps is for the send
        // button to always be to the right of the input field, even in RTL layouts.
        // This means, in most places you'll want to pin deliberately to left/right
        // instead of leading/trailing. You'll also want to the semanticContentAttribute
        // to ensure horizontal stack views layout left-to-right.

        let containerView = UIView.container()
        addSubview(containerView)
        containerView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        containerView.autoPinEdge(toSuperviewSafeArea: .bottom)

        containerView.addSubview(textContainer)
        textContainer.autoPinEdge(toSuperviewMargin: .left, withInset: OWSTableViewController2.defaultHOuterMargin)
        textContainer.autoPinHeightToSuperview(withMargin: 8)

        containerView.addSubview(sendButton)
        sendButton.autoPinEdge(toSuperviewEdge: .right, withInset: 2)
        sendButton.autoPinEdge(toSuperviewEdge: .bottom)
        sendButton.autoPinEdge(.left, to: .right, of: textContainer, withOffset: 2)

        containerView.addSubview(reactButton)
        reactButton.autoAlignAxis(.vertical, toSameAxisOf: sendButton)
        reactButton.autoAlignAxis(.horizontal, toSameAxisOf: sendButton)

        textViewHeightConstraint = textView.autoSetDimension(.height, toSize: minTextViewHeight)

        updateContent(animated: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIView Overrides

    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    override var intrinsicContentSize: CGSize { .zero }

    // MARK: - Subviews

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.accessibilityLabel = MessageStrings.sendButton
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "sendButton")
        button.setImage(UIImage(imageLiteralResourceName: "send-blue-32"), for: .normal)
        button.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)
        button.autoSetDimensions(to: CGSize(square: 48))
        return button
    }()

    private lazy var reactButton: UIButton = {
        let button = OWSButton(imageName: "add-reaction-outline-24", tintColor: Theme.darkThemePrimaryColor) { [weak self] in
            self?.didTapReact()
        }
        button.autoSetDimensions(to: CGSize(square: 48))
        return button
    }()

    private lazy var textView: MentionTextView = {
        let textView = buildTextView()
        textView.scrollIndicatorInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 3)
        textView.mentionDelegate = self
        return textView
    }()

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        textView.resignFirstResponder()
    }

    private lazy var placeholderTextView: UITextView = {
        let placeholderTextView = buildTextView()

        placeholderTextView.text = OWSLocalizedString(
            "STORY_REPLY_TEXT_FIELD_PLACEHOLDER",
            comment: "placeholder text for replying to a story"
        )
        placeholderTextView.isEditable = false
        placeholderTextView.textContainer.maximumNumberOfLines = 1
        placeholderTextView.textContainer.lineBreakMode = .byTruncatingTail
        placeholderTextView.textColor = .ows_whiteAlpha60

        return placeholderTextView
    }()

    private lazy var textContainer: UIView = {
        let textContainer = UIStackView()
        textContainer.axis = .vertical

        if let headerLabel = buildHeaderLabel() {
            textContainer.addArrangedSubview(headerLabel)
        }

        let bubbleView = UIStackView()
        bubbleView.axis = .vertical
        bubbleView.addBackgroundView(withBackgroundColor: .ows_gray75, cornerRadius: minTextViewHeight / 2)
        textContainer.addArrangedSubview(bubbleView)

        if let quotedReplyModel = quotedReplyModel {
            let previewView = StoryReplyPreviewView(quotedReplyModel: quotedReplyModel)
            let previewViewContainer = UIView()
            previewViewContainer.addSubview(previewView)
            previewView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 8, leading: 8, bottom: 2, trailing: 8))
            bubbleView.addArrangedSubview(previewViewContainer)
        }

        let textAndPlaceholderContainer = UIView()
        bubbleView.addArrangedSubview(textAndPlaceholderContainer)

        textAndPlaceholderContainer.addSubview(placeholderTextView)
        textAndPlaceholderContainer.addSubview(textView)

        textView.autoPinEdgesToSuperviewEdges()
        placeholderTextView.autoPinEdges(toEdgesOf: textView)

        return textContainer
    }()

    private func buildTextView() -> MentionTextView {
        let textView = MentionTextView()

        textView.keyboardAppearance = Theme.darkThemeKeyboardAppearance
        textView.backgroundColor = .clear
        textView.tintColor = Theme.darkThemePrimaryColor

        let textViewFont = UIFont.dynamicTypeBody
        textView.font = textViewFont
        textView.textColor = Theme.darkThemePrimaryColor
        return textView
    }

    private func buildHeaderLabel() -> UIView? {
        guard let headerText: String = {
            switch quotedReplyModel {
            case .some(let quotedReplyModel):
                guard !quotedReplyModel.authorAddress.isLocalAddress else {
                    fallthrough
                }
                let format = OWSLocalizedString(
                    "STORY_REPLY_TEXT_FIELD_HEADER_FORMAT",
                    comment: "header text for replying to private story. Embeds {{author name}}"
                )
                let authorName = contactsManager.displayName(for: quotedReplyModel.authorAddress)
                return String(format: format, authorName)
            case .none:
                return nil
            }
        }() else {
            return nil
        }

        let label = UILabel()
        label.textColor = Theme.darkThemeSecondaryTextAndIconColor
        label.font = .dynamicTypeFootnote
        label.text = headerText

        let container = UIView()
        container.addSubview(label)
        label.autoPinEdgesToSuperviewEdges(with: .init(top: 2, leading: 4, bottom: 10, trailing: 4))

        return container
    }

    // MARK: - Actions

    @objc
    private func didTapSend() {
        textView.acceptAutocorrectSuggestion()
        delegate?.storyReplyInputToolbarDidTapSend(self)
    }

    private func didTapReact() {
        delegate?.storyReplyInputToolbarDidTapReact(self)
    }

    // MARK: - Helpers

    private func updateContent(animated: Bool) {
        AssertIsOnMainThread()

        updateHeight(textView: textView)

        let hasAnyText = !textView.text.isEmptyOrNil
        placeholderTextView.isHidden = hasAnyText

        let hasNonWhitespaceText = !textView.text.ows_stripped().isEmpty
        setSendButtonHidden(!hasNonWhitespaceText, animated: animated)
    }

    private var isSendButtonHidden: Bool = false

    private func setSendButtonHidden(_ isHidden: Bool, animated: Bool) {
        guard isHidden != isSendButtonHidden else { return }

        let setButtonHidden: (UIButton, Bool) -> Void = { button, isHidden in
            button.alpha = isHidden ? 0 : 1
            button.transform = isHidden ? .scale(0.1) : .identity
        }

        isSendButtonHidden = isHidden

        guard animated else {
            setButtonHidden(sendButton, isHidden)
            setButtonHidden(reactButton, !isHidden)
            return
        }

        let animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 0.645, springResponse: 0.25)
        animator.addAnimations {
            setButtonHidden(self.sendButton, isHidden)
            setButtonHidden(self.reactButton, !isHidden)
        }
        animator.startAnimation()
    }

    private func updateHeight(textView: UITextView) {
        guard let textViewHeightConstraint else {
            owsFailDebug("Missing constraint.")
            return
        }

        let contentSize = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude))
        let newHeight = CGFloatClamp(contentSize.height, minTextViewHeight, maxTextViewHeight)
        guard textViewHeightConstraint.constant != newHeight else { return }

        if let superview {
            let animator = UIViewPropertyAnimator(
                duration: ConversationInputToolbar.heightChangeAnimationDuration,
                springDamping: 1,
                springResponse: 0.25
            )
            animator.addAnimations {
                textViewHeightConstraint.constant = newHeight
                superview.setNeedsLayout()
                superview.layoutIfNeeded()
            }
            animator.startAnimation()
        } else {
            textViewHeightConstraint.constant = newHeight
        }
    }
}

extension StoryReplyInputToolbar: MentionTextViewDelegate {

    func textViewDidBeginTypingMention(_ textView: MentionTextView) {}

    func textViewDidEndTypingMention(_ textView: MentionTextView) {}

    func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        delegate?.storyReplyInputToolbarMentionPickerParentView(self)
    }

    func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        delegate?.storyReplyInputToolbarMentionPickerReferenceView(self)
    }

    func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        delegate?.storyReplyInputToolbarMentionPickerPossibleAddresses(self) ?? []
    }

    public func textViewMentionDisplayConfiguration(_ textView: MentionTextView) -> MentionDisplayConfiguration {
        return .groupReply
    }

    public func mentionPickerStyle(_ textView: MentionTextView) -> MentionPickerStyle {
        return .groupReply
    }

    public func textViewDidChange(_ textView: UITextView) {
        updateHeight(textView: textView)
        updateContent(animated: true)
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        delegate?.storyReplyInputToolbarDidBeginEditing(self)
    }
}
