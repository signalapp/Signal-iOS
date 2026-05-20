//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

// Coincides with Android's max text message length
let kMaxMessageBodyCharacterCount = 2000

protocol StoryReplyInputToolbarDelegate: MessageReactionPickerDelegate {
    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar) async throws
    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar)
    func storyReplyInputToolbarMentionPickerPossibleAcis(_ storyReplyInputToolbar: StoryReplyInputToolbar, tx: DBReadTransaction) -> [Aci]
    func storyReplyInputToolbarMentionCacheInvalidationKey() -> String
    func storyReplyInputToolbarMentionPickerReferenceView(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> UIView?
    func storyReplyInputToolbarMentionPickerParentView(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> UIView?
}

class StoryReplyInputToolbar: UIView, BodyRangesTextViewDelegate {

    // MARK: - Public

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

    // MARK: - UIView

    init(
        isGroupStory: Bool,
        quotedReplyModel: QuotedReplyModel? = nil,
        spoilerState: SpoilerRenderState,
    ) {
        self.isGroupStory = isGroupStory
        self.quotedReplyModel = quotedReplyModel
        self.spoilerState = spoilerState

        super.init(frame: CGRect.zero)

        // Blur background on legacy (pre-iOS 26 iOS versions).
        if #unavailable(iOS 26) {
            // When presenting or dismissing the keyboard, there may be a slight
            // gap between the keyboard and the bottom of the input bar during
            // the animation. Extend the background below the toolbar's bounds
            // by this much to mask that extra space.
            let backgroundExtension: CGFloat = 500

            if UIAccessibility.isReduceTransparencyEnabled {
                backgroundColor = .Signal.background

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
        }

        let containerView: UIView
        let contentView: UIView
        if #available(iOS 26, *) {
            let glassContainer = UIVisualEffectView(effect: UIGlassContainerEffect())

            containerView = glassContainer
            contentView = glassContainer.contentView
        } else {
            containerView = UIView()
            contentView = containerView
        }
        contentView.semanticContentAttribute = .forceLeftToRight

        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
        ])

        // On iOS 26 and later reaction picker must be wrapped into a glass panel.
        let reactionPickerHMargin: CGFloat
        let reactionPickerBottomPadding: CGFloat
        let reactionPickerView: UIView
        if #available(iOS 26, *) {
            let glassEffect = ConversationInputToolbar.Style.glassEffect(isInteractive: true)
            let reactionPickerPanel = UIVisualEffectView(effect: glassEffect)
            reactionPickerPanel.directionalLayoutMargins = .zero
            reactionPickerPanel.cornerConfiguration = .capsule()
            reactionPickerPanel.contentView.addSubview(reactionPicker)
            reactionPicker.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                reactionPicker.topAnchor.constraint(equalTo: reactionPickerPanel.layoutMarginsGuide.topAnchor),
                reactionPicker.leadingAnchor.constraint(equalTo: reactionPickerPanel.layoutMarginsGuide.leadingAnchor),
                reactionPicker.trailingAnchor.constraint(equalTo: reactionPickerPanel.layoutMarginsGuide.trailingAnchor),
                reactionPicker.bottomAnchor.constraint(equalTo: reactionPickerPanel.layoutMarginsGuide.bottomAnchor),
            ])

            reactionPickerView = reactionPickerPanel
            reactionPickerHMargin = OWSTableViewController2.defaultHOuterMargin
            reactionPickerBottomPadding = 8
        } else {
            reactionPickerView = reactionPicker
            reactionPickerHMargin = 0
            reactionPickerBottomPadding = 0
        }

        reactionPickerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(reactionPickerView)

        textContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textContainer)

        sendButtonWrapper.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sendButtonWrapper)

        // No Send button visible: text view's trailing edge is pinned to containerView's trailing edge.
        textViewContainerTrailingEdgeConstraintNoSendButton = textContainer.trailingAnchor.constraint(
            equalTo: containerView.trailingAnchor,
        )
        // Send button visible: trailing edge of text view's background (which is defined by textContainer.layoutMarginsGuide)
        // is pinned to the leading edge of the `rightEdgeControlsView`.
        // RightEdgeControlsView has a leading margin that defines spacing between send button and text view.
        textViewContainerTrailingEdgeConstraintSendButton = textContainer.layoutMarginsGuide.trailingAnchor.constraint(
            equalTo: sendButtonWrapper.leadingAnchor,
        )

        NSLayoutConstraint.activate([
            // Reaction picker: full width, above text view.
            reactionPickerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            reactionPickerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: reactionPickerHMargin),
            reactionPickerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -reactionPickerHMargin),

            // Text container:
            // under reaction picker, pinned to the left edge, with Send button on the right.
            textContainer.topAnchor.constraint(equalTo: reactionPickerView.bottomAnchor, constant: reactionPickerBottomPadding),
            textContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            sendButtonWrapper.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            sendButtonWrapper.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            textViewContainerTrailingEdgeConstraintNoSendButton,
        ])

        updateContent(animated: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var bounds: CGRect {
        didSet {
            guard oldValue.height != bounds.height else { return }
            delegate?.storyReplyInputToolbarHeightDidChange(self)
        }
    }

    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    override var intrinsicContentSize: CGSize { .zero }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        textView.resignFirstResponder()
    }

    // MARK: - Subviews

    // Copied from ConversationInputToolbar
    private enum LayoutMetrics {
        static let initialTextBoxHeight: CGFloat = 40
        static let minTextViewHeight: CGFloat = 35
        static var maxTextViewHeight: CGFloat {
            // About ~4 lines in portrait and ~3 lines in landscape.
            // Otherwise we risk obscuring too much of the content.
            UIDevice.current.orientation.isPortrait ? 160 : 100
        }
    }

    private var textViewHeightConstraint: NSLayoutConstraint!
    private var textViewContainerTrailingEdgeConstraintNoSendButton: NSLayoutConstraint!
    private var textViewContainerTrailingEdgeConstraintSendButton: NSLayoutConstraint!

    private lazy var sendButtonWrapper: SendButtonWrapper = {
        let view = SendButtonWrapper()
        view.sendButton.addAction(
            UIAction { [weak self] _ in
                self?.didTapSend()
            },
            for: .primaryActionTriggered,
        )
        return view
    }()

    private class SendButtonWrapper: UIView {
        var sendButtonHidden = true {
            didSet {
                sendButton.alpha = sendButtonHidden ? 0 : 1
                sendButton.transform = sendButtonHidden ? .scale(0.1) : .identity
                invalidateIntrinsicContentSize()
            }
        }

        private static let legacySendButtonInnerHMargin: CGFloat = 8 // 48 dp button width
        private static let legacySendButtonInnerVMargin: CGFloat = 4 // 40 dp (LayoutMetrics.initialTextBoxHeight) button height

        @available(iOS, deprecated: 26)
        private func buildSendButtonLegacy() -> UIButton {
            let button = UIButton(configuration: .plain())
            button.accessibilityLabel = MessageStrings.sendButton
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "sendButton")
            button.configurationUpdateHandler = { button in
                button.alpha = button.isHighlighted ? 0.5 : 1
            }
            button.configuration?.image = UIImage(named: "send-blue-32")
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(
                hMargin: SendButtonWrapper.legacySendButtonInnerHMargin,
                vMargin: SendButtonWrapper.legacySendButtonInnerVMargin,
            )
            return button
        }

        @available(iOS 26, *)
        private func buildSendButton() -> UIButton {
            let buttonSize = LayoutMetrics.initialTextBoxHeight
            let buttonImage = Theme.iconImage(.arrowUp)

            let button = UIButton(configuration: .prominentGlass())
            button.tintColor = .Signal.accent
            button.configuration?.image = buttonImage
            button.configuration?.baseForegroundColor = .white
            button.configuration?.cornerStyle = .capsule
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(
                hMargin: 0.5 * (buttonSize - buttonImage.size.width),
                vMargin: 0.5 * (buttonSize - buttonImage.size.height),
            )
            button.accessibilityLabel = MessageStrings.sendButton
            return button
        }

        lazy var sendButton: UIButton = if #available(iOS 26, *) { buildSendButton() } else { buildSendButtonLegacy() }

        override init(frame: CGRect) {
            super.init(frame: frame)

            directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: 0,
                // Spacing between text view and send button.
                leading: 12,
                // Same as in `textContainer`
                bottom: 8,
                // Spacing between Send button and trailing edge of the screen.
                trailing: OWSTableViewController2.defaultHOuterMargin,
            )

            // Legacy button has 8 dp margins around circular icon.
            // Subtract that amount from leading and trailing margings to compensate for it.
            if #unavailable(iOS 26) {
                directionalLayoutMargins.leading -= SendButtonWrapper.legacySendButtonInnerHMargin
                directionalLayoutMargins.trailing -= SendButtonWrapper.legacySendButtonInnerHMargin
            }

            sendButton.setContentHuggingHorizontalHigh()
            sendButton.setCompressionResistanceHorizontalHigh()
            addSubview(sendButton)
            sendButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                sendButton.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
                sendButton.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
                sendButton.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                sendButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            ])
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
        textView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 3)
        textView.bodyRangesDelegate = self
        return textView
    }()

    private lazy var reactionPicker: MessageReactionPicker = MessageReactionPicker(selectedEmoji: nil, delegate: delegate, style: .inline)

    private lazy var placeholderTextView: UITextView = {
        let placeholderTextView = buildTextView()

        let placeholderText = {
            if isGroupStory {
                return OWSLocalizedString(
                    "STORY_REPLY_TO_GROUP_TEXT_FIELD_PLACEHOLDER",
                    comment: "placeholder text for replying to a group story",
                )
            } else if let quotedReplyModel {
                let format = OWSLocalizedString(
                    "STORY_REPLY_TO_PRIVATE_TEXT_FIELD_PLACEHOLDER",
                    comment: "placeholder text for replying to a private story. Embeds {{author name}}",
                )
                let authorName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                    return SSKEnvironment.shared.contactManagerRef.displayName(for: quotedReplyModel.originalMessageAuthorAddress, tx: tx).resolvedValue()
                }
                return String.nonPluralLocalizedStringWithFormat(format, authorName)
            } else {
                return OWSLocalizedString(
                    "STORY_REPLY_TEXT_FIELD_PLACEHOLDER",
                    comment: "placeholder text for replying to a story",
                )
            }
        }()

        placeholderTextView.setMessageBody(.init(text: placeholderText, ranges: .empty), txProvider: SSKEnvironment.shared.databaseStorageRef.readTxProvider)
        placeholderTextView.isEditable = false
        placeholderTextView.textContainer.maximumNumberOfLines = 1
        placeholderTextView.textContainer.lineBreakMode = .byTruncatingTail
        placeholderTextView.textColor = .Signal.secondaryLabel

        return placeholderTextView
    }()

    private lazy var textContainer: UIView = {
        let textContainer = UIView()

        // Controls padding around the text view background.
        textContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: OWSTableViewController2.defaultHOuterMargin,
            bottom: 8, // spacing to keyboard
            trailing: OWSTableViewController2.defaultHOuterMargin,
        )

        let backgroundView: UIView
        if #available(iOS 26, *) {
            let glassEffect = ConversationInputToolbar.Style.glassEffect(isInteractive: true)
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.cornerConfiguration = .uniformCorners(radius: .fixed(LayoutMetrics.initialTextBoxHeight / 2))

            glassEffectView.translatesAutoresizingMaskIntoConstraints = false
            textContainer.addSubview(glassEffectView)

            placeholderTextView.translatesAutoresizingMaskIntoConstraints = false
            glassEffectView.contentView.addSubview(placeholderTextView)

            textView.translatesAutoresizingMaskIntoConstraints = false
            glassEffectView.contentView.addSubview(textView)

            backgroundView = glassEffectView
        } else {
            backgroundView = UIView()
            backgroundView.backgroundColor = UIColor.Signal.tertiaryFill
            backgroundView.layer.cornerRadius = LayoutMetrics.initialTextBoxHeight / 2

            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            textContainer.addSubview(backgroundView)

            placeholderTextView.translatesAutoresizingMaskIntoConstraints = false
            textContainer.addSubview(placeholderTextView)

            textView.translatesAutoresizingMaskIntoConstraints = false
            textContainer.addSubview(textView)
        }

        backgroundView.directionalLayoutMargins = .zero

        textView.translatesAutoresizingMaskIntoConstraints = false
        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: LayoutMetrics.minTextViewHeight)

        NSLayoutConstraint.activate([
            // Background view is constrained to container's layout margins.
            // Change those to adjust outer padding around the background.
            backgroundView.topAnchor.constraint(equalTo: textContainer.layoutMarginsGuide.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: textContainer.layoutMarginsGuide.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: textContainer.layoutMarginsGuide.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: textContainer.layoutMarginsGuide.bottomAnchor),

            // This sets minimum height on visual text view box. This height can exceed height of an empty inputTextView.
            // We don't want `textView` to grow above it's content size because that causes
            // incorrect (top) alignment of text when there's just a single line of it.
            backgroundView.heightAnchor.constraint(greaterThanOrEqualToConstant: LayoutMetrics.initialTextBoxHeight),

            // This defines height of `textView` which is always set to content size. Calculated in `updateHeight(textView:)`
            textViewHeightConstraint,

            // This lets `textContainer` grow with `textView` when height of the latter increases with text.
            // Working in conjuction with the next constraint they center `textView` vertically
            // when it's height is below the minimum height of `backgroundView`.
            textView.topAnchor.constraint(greaterThanOrEqualTo: backgroundView.topAnchor),
            textView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),

            // Adjust trailing and leading margins on the backgroundView to control inner horizontal padding.
            textView.leadingAnchor.constraint(equalTo: backgroundView.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: backgroundView.layoutMarginsGuide.trailingAnchor),

            // Placeholder text view is always same frame as active text view.
            placeholderTextView.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderTextView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderTextView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            placeholderTextView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
        ])

        return textContainer
    }()

    private func buildTextView() -> BodyRangesTextView {
        let textView = BodyRangesTextView()
        textView.textColor = .Signal.label
        textView.tintColor = .Signal.label // cursor color
        textView.backgroundColor = .clear
        textView.font = .dynamicTypeBody
        return textView
    }

    // MARK: - Actions

    private func didTapSend() {
        textView.acceptAutocorrectSuggestion()
        Task {
            try await delegate?.storyReplyInputToolbarDidTapSend(self)
        }
    }

    // MARK: - Helpers

    private func updateContent(animated: Bool) {
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
            sendButtonWrapper.sendButtonHidden = isHidden
            textViewContainerTrailingEdgeConstraintSendButton.isActive = isHidden == false
            textViewContainerTrailingEdgeConstraintNoSendButton.isActive = isHidden == true
            return
        }

        let animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 0.645, springResponse: 0.25)
        animator.addAnimations {
            self.sendButtonWrapper.sendButtonHidden = isHidden
            self.textViewContainerTrailingEdgeConstraintSendButton.isActive = isHidden == false
            self.textViewContainerTrailingEdgeConstraintNoSendButton.isActive = isHidden == true
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
        let newHeight = CGFloat.clamp(
            contentSize.height,
            min: LayoutMetrics.minTextViewHeight,
            max: LayoutMetrics.maxTextViewHeight,
        )
        guard textViewHeightConstraint.constant != newHeight else { return }

        if let superview {
            let animator = UIViewPropertyAnimator(
                duration: ConversationInputToolbar.heightChangeAnimationDuration,
                springDamping: 1,
                springResponse: 0.25,
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

    // MARK: - BodyRangesTextViewDelegate

    func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) {}

    func textViewDidEndTypingMention(_ textView: BodyRangesTextView) {}

    func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        delegate?.storyReplyInputToolbarMentionPickerParentView(self)
    }

    func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        delegate?.storyReplyInputToolbarMentionPickerReferenceView(self)
    }

    func textViewMentionPickerPossibleAcis(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [Aci] {
        delegate?.storyReplyInputToolbarMentionPickerPossibleAcis(self, tx: tx) ?? []
    }

    func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        return delegate?.storyReplyInputToolbarMentionCacheInvalidationKey() ?? UUID().uuidString
    }

    func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        return .composingGroupStoryReply()
    }

    func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
        return .groupReply
    }

    func textViewDidChange(_ textView: UITextView) {
        updateHeight(textView: textView)
        updateContent(animated: true)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        delegate?.storyReplyInputToolbarDidBeginEditing(self)
    }
}
