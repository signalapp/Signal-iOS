//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI
import UIKit

// Coincides with Android's max text message length
let kMaxMessageBodyCharacterCount = 2000

protocol StoryReplyInputToolbarDelegate: MessageReactionPickerDelegate {
    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarDidTapReact(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarMentionPickerPossibleAddresses(_ storyReplyInputToolbar: StoryReplyInputToolbar, tx: DBReadTransaction) -> [SignalServiceAddress]
    func storyReplyInputToolbarMentionCacheInvalidationKey() -> String
    func storyReplyInputToolbarMentionPickerReferenceView(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> UIView?
    func storyReplyInputToolbarMentionPickerParentView(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> UIView?
}

// MARK: -

class StoryReplyInputToolbar: UIView {

    weak var delegate: StoryReplyInputToolbarDelegate? {
        didSet {
            reactionPicker.delegate = delegate
        }
    }
    let isGroupStory: Bool
    let quotedReplyModel: QuotedReplyModel?

    let spoilerState: SpoilerRenderState

    var messageBodyForSending: MessageBody? {
        textView.messageBodyForSending
    }

    func setMessageBody(_ messageBody: MessageBody?, txProvider: EditableMessageBodyTextStorage.ReadTxProvider) {
        textView.setMessageBody(messageBody, txProvider: txProvider)
        updateContent(animated: true)
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

    init(
        isGroupStory: Bool,
        quotedReplyModel: QuotedReplyModel? = nil,
        spoilerState: SpoilerRenderState
    ) {
        self.isGroupStory = isGroupStory
        self.quotedReplyModel = quotedReplyModel
        self.spoilerState = spoilerState
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

        containerView.addSubview(reactionPicker)
        reactionPicker.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)

        containerView.addSubview(textContainer)
        textContainer.autoPinEdge(toSuperviewMargin: .left, withInset: OWSTableViewController2.defaultHOuterMargin)
        textContainer.autoPinEdge(.top, to: .bottom, of: reactionPicker)
        textContainer.autoPinEdge(toSuperviewMargin: .bottom, withInset: 8)
        textContainer.autoPinEdge(toSuperviewEdge: .right, withInset: OWSTableViewController2.defaultHOuterMargin, relation: .greaterThanOrEqual)

        containerView.addSubview(rightEdgeControlsView)
        rightEdgeControlsView.autoPinEdge(toSuperviewEdge: .right, withInset: 2)
        rightEdgeControlsView.autoPinEdge(toSuperviewEdge: .bottom)
        rightEdgeControlsView.autoPinEdge(.left, to: .right, of: textContainer, withOffset: 2)
        rightEdgeControlsView.autoAlignAxis(.horizontal, toSameAxisOf: textContainer)

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

    private lazy var rightEdgeControlsView: RightEdgeControlsView = {
        let view = RightEdgeControlsView()
        view.sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)
        return view
    }()

    private class RightEdgeControlsView: UIView {
        var sendButtonHidden = true {
            didSet {
                sendButton.alpha = sendButtonHidden ? 0 : 1
                sendButton.transform = sendButtonHidden ? .scale(0.1) : .identity
                invalidateIntrinsicContentSize()
            }
        }

        lazy var sendButton: UIButton = {
            let button = UIButton(type: .system)
            button.accessibilityLabel = MessageStrings.sendButton
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "sendButton")
            button.setImage(UIImage(imageLiteralResourceName: "send-blue-32"), for: .normal)
            button.bounds.size = .init(width: 48, height: 48)
            return button
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            sendButton.setContentHuggingHorizontalHigh()
            sendButton.setCompressionResistanceHorizontalHigh()
            addSubview(sendButton)
            sendButton.autoCenterInSuperview()

            setContentHuggingHigh()
            setCompressionResistanceHigh()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            .init(width: sendButtonHidden ? 0 : 48, height: 48)
        }
    }

    private lazy var textView: BodyRangesTextView = {
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

    private lazy var reactionPicker: MessageReactionPicker = MessageReactionPicker(selectedEmoji: nil, delegate: delegate, style: .inline, forceDarkTheme: true)

    private lazy var placeholderTextView: UITextView = {
        let placeholderTextView = buildTextView()

        let placeholderText = {
            if isGroupStory {
                return OWSLocalizedString(
                    "STORY_REPLY_TO_GROUP_TEXT_FIELD_PLACEHOLDER",
                    comment: "placeholder text for replying to a group story"
                )
            } else if let quotedReplyModel {
                let format = OWSLocalizedString(
                    "STORY_REPLY_TO_PRIVATE_TEXT_FIELD_PLACEHOLDER",
                    comment: "placeholder text for replying to a private story. Embeds {{author name}}"
                )
                let authorName = contactsManager.displayName(for: quotedReplyModel.authorAddress)
                return String(format: format, authorName)
            } else {
                return OWSLocalizedString(
                    "STORY_REPLY_TEXT_FIELD_PLACEHOLDER",
                    comment: "placeholder text for replying to a story"
                )
            }
        }()

        placeholderTextView.setMessageBody(.init(text: placeholderText, ranges: .empty), txProvider: databaseStorage.readTxProvider)
        placeholderTextView.isEditable = false
        placeholderTextView.textContainer.maximumNumberOfLines = 1
        placeholderTextView.textContainer.lineBreakMode = .byTruncatingTail
        placeholderTextView.textColor = .ows_whiteAlpha60

        return placeholderTextView
    }()

    private lazy var textContainer: UIView = {
        let textContainer = UIStackView()
        textContainer.axis = .vertical

        let bubbleView = UIStackView()
        bubbleView.axis = .vertical
        bubbleView.addBackgroundView(withBackgroundColor: .ows_gray75, cornerRadius: minTextViewHeight / 2)
        textContainer.addArrangedSubview(bubbleView)

        let textAndPlaceholderContainer = UIView()
        bubbleView.addArrangedSubview(textAndPlaceholderContainer)

        textAndPlaceholderContainer.addSubview(placeholderTextView)
        textAndPlaceholderContainer.addSubview(textView)

        textView.autoPinEdgesToSuperviewEdges()
        placeholderTextView.autoPinEdges(toEdgesOf: textView)

        return textContainer
    }()

    private func buildTextView() -> BodyRangesTextView {
        let textView = BodyRangesTextView()

        textView.keyboardAppearance = Theme.darkThemeKeyboardAppearance
        textView.backgroundColor = .clear
        textView.tintColor = Theme.darkThemePrimaryColor

        let textViewFont = UIFont.dynamicTypeBody
        textView.font = textViewFont
        textView.textColor = Theme.darkThemePrimaryColor
        return textView
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

        let hasAnyText = !textView.isEmpty
        placeholderTextView.isHidden = hasAnyText

        let hasNonWhitespaceText = !textView.isWhitespaceOrEmpty
        setSendButtonHidden(!hasNonWhitespaceText, animated: animated)
    }

    private var isSendButtonHidden: Bool = false

    private func setSendButtonHidden(_ isHidden: Bool, animated: Bool) {
        guard isHidden != isSendButtonHidden else { return }

        isSendButtonHidden = isHidden

        guard animated else {
            self.rightEdgeControlsView.sendButtonHidden = isHidden
            return
        }

        let animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 0.645, springResponse: 0.25)
        animator.addAnimations {
            self.rightEdgeControlsView.sendButtonHidden = isHidden
            self.layoutIfNeeded()
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

extension StoryReplyInputToolbar: BodyRangesTextViewDelegate {

    func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) {}

    func textViewDidEndTypingMention(_ textView: BodyRangesTextView) {}

    func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        delegate?.storyReplyInputToolbarMentionPickerParentView(self)
    }

    func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        delegate?.storyReplyInputToolbarMentionPickerReferenceView(self)
    }

    func textViewMentionPickerPossibleAddresses(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [SignalServiceAddress] {
        delegate?.storyReplyInputToolbarMentionPickerPossibleAddresses(self, tx: tx) ?? []
    }

    func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        return delegate?.storyReplyInputToolbarMentionCacheInvalidationKey() ?? UUID().uuidString
    }

    public func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        return .composingGroupStoryReply()
    }

    public func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
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
