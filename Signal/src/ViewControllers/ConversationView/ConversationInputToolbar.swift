//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalMessaging
import SignalUI
import UIKit

public protocol ConversationInputToolbarDelegate: AnyObject {

    func sendButtonPressed()

    func sendSticker(_ sticker: StickerInfo)

    func presentManageStickersView()

    func updateToolbarHeight()

    func isBlockedConversation() -> Bool

    func isGroup() -> Bool

    // MARK: Voice Memo

    func voiceMemoGestureDidStart()

    func voiceMemoGestureDidLock()

    func voiceMemoGestureDidComplete()

    func voiceMemoGestureDidCancel()

    func voiceMemoGestureWasInterrupted()

    func sendVoiceMemoDraft(_ draft: VoiceMessageModel)

    // MARK: Attachments

    func cameraButtonPressed()

    func galleryButtonPressed()

    func gifButtonPressed()

    func fileButtonPressed()

    func contactButtonPressed()

    func locationButtonPressed()

    func paymentButtonPressed()

    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment)

    func showUnblockConversationUI(completion: ((Bool) -> Void)?)
}

public class ConversationInputToolbar: UIView, LinkPreviewViewDraftDelegate, QuotedReplyPreviewDelegate {

    private var conversationStyle: ConversationStyle

    private let mediaCache: CVMediaCache

    private weak var inputToolbarDelegate: ConversationInputToolbarDelegate?

    public init(
        conversationStyle: ConversationStyle,
        mediaCache: CVMediaCache,
        messageDraft: MessageBody?,
        quotedReply: OWSQuotedReplyModel?,
        inputToolbarDelegate: ConversationInputToolbarDelegate,
        inputTextViewDelegate: ConversationInputTextViewDelegate,
        mentionDelegate: MentionTextViewDelegate
    ) {
        self.conversationStyle = conversationStyle
        self.mediaCache = mediaCache
        self.inputToolbarDelegate = inputToolbarDelegate

        super.init(frame: .zero)

        createContentsWithMessageDraft(
            messageDraft,
            quotedReply: quotedReply,
            inputTextViewDelegate: inputTextViewDelegate,
            mentionDelegate: mentionDelegate
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(notification:)),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameDidChange(notification:)),
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    public override var intrinsicContentSize: CGSize {
        // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
        // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
        .zero
    }

    public override var frame: CGRect {
        didSet {
            guard oldValue.size.height != frame.size.height else { return }

            inputToolbarDelegate?.updateToolbarHeight()
        }
    }

    public override var bounds: CGRect {
        didSet {
            guard oldValue.size.height != bounds.size.height else { return }

            // Compensate for autolayout frame/bounds changes when animating in/out the quoted reply view.
            // This logic ensures the input toolbar stays pinned to the keyboard visually
            if isAnimatingQuotedReply && inputTextView.isFirstResponder {
                var frame = frame
                frame.origin.y = 0
                // In this conditional, bounds change is captured in an animation block, which we don't want here.
                UIView.performWithoutAnimation {
                    self.frame = frame
                }
            }

            inputToolbarDelegate?.updateToolbarHeight()
        }
    }

    func update(conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()
        self.conversationStyle = conversationStyle
    }

    private var receivedSafeAreaInsets = UIEdgeInsets.zero

    private enum LayoutMetrics {
        static let minTextViewHeight: CGFloat = 36
        static let minToolbarItemHeight: CGFloat = 44
        static let maxTextViewHeight: CGFloat = 98
        static let maxIPadTextViewHeight: CGFloat = 142
    }

    private lazy var inputTextView: ConversationInputTextView = {
        let inputTextView = ConversationInputTextView()
        inputTextView.textViewToolbarDelegate = self
        inputTextView.font = .ows_dynamicTypeBody
        inputTextView.backgroundColor = Theme.conversationInputBackgroundColor
        inputTextView.setContentHuggingLow()
        inputTextView.setCompressionResistanceLow()
        inputTextView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "inputTextView")
        return inputTextView
    }()

    private lazy var cameraButton: UIButton = {
        let button = UIButton()
        button.accessibilityLabel = NSLocalizedString(
            "CAMERA_BUTTON_LABEL",
            comment: "Accessibility label for camera button."
        )
        button.accessibilityHint = NSLocalizedString(
            "CAMERA_BUTTON_HINT",
            comment: "Accessibility hint describing what you can do with the camera button"
        )
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "cameraButton")
        button.setTemplateImage(Theme.iconImage(.cameraButton), tintColor: Theme.primaryIconColor)
        button.addTarget(self, action: #selector(cameraButtonPressed), for: .touchUpInside)
        button.autoSetDimensions(to: CGSize(width: 40, height: LayoutMetrics.minToolbarItemHeight))
        return button
    }()

    private lazy var attachmentButton: LottieToggleButton = {
        let button = LottieToggleButton()
        button.accessibilityLabel = NSLocalizedString(
            "ATTACHMENT_LABEL",
            comment: "Accessibility label for attaching photos"
        )
        button.accessibilityHint = NSLocalizedString(
            "ATTACHMENT_HINT",
            comment: "Accessibility hint describing what you can do with the attachment button"
        )
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "attachmentButton")
        button.addTarget(self, action: #selector(attachmentButtonPressed), for: .touchUpInside)
        button.animationName = Theme.isDarkThemeEnabled ? "attachment_dark" : "attachment_light"
        button.animationSize = CGSize(square: 28)
        button.autoSetDimensions(to: CGSize(width: 55, height: LayoutMetrics.minToolbarItemHeight))
        return button
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton()
        button.accessibilityLabel = MessageStrings.sendButton
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "sendButton")
        button.addTarget(self, action: #selector(sendButtonPressed), for: .touchUpInside)
        button.setTemplateImageName("send-solid-24", tintColor: .ows_accentBlue)
        button.autoSetDimensions(to: CGSize(width: 50, height: LayoutMetrics.minToolbarItemHeight))
        return button
    }()

    private lazy var voiceMemoButton: UIButton = {
        let button = UIButton(type: .custom)
        button.accessibilityLabel = NSLocalizedString(
            "INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_LABEL",
            comment: "accessibility label for the button which records voice memos"
        )
        button.accessibilityHint = NSLocalizedString(
            "INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_HINT",
            comment: "accessibility hint for the button which records voice memos"
        )
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "voiceMemoButton")
        button.setTemplateImage(Theme.iconImage(.micButton), tintColor: Theme.primaryIconColor)
        button.autoSetDimensions(to: CGSize(width: 40, height: LayoutMetrics.minToolbarItemHeight))
        // We want to be permissive about the voice message gesture, so we hang
        // the long press GR on the button's wrapper, not the button itself.
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleVoiceMemoLongPress(gesture:)))
        longPressGestureRecognizer.minimumPressDuration = 0
        button.addGestureRecognizer(longPressGestureRecognizer)
        return button
    }()

    private lazy var stickerButton: UIButton = {
        let button = UIButton(type: .custom)
        button.accessibilityLabel = NSLocalizedString(
            "INPUT_TOOLBAR_STICKER_BUTTON_ACCESSIBILITY_LABEL",
            comment: "accessibility label for the button which shows the sticker picker")
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "stickerButton")
        button.setTemplateImage(Theme.iconImage(.stickerButton), tintColor: Theme.primaryIconColor)
        button.addTarget(self, action: #selector(stickerButtonPressed), for: .touchUpInside)
        button.autoSetDimensions(to: CGSize(width: 40, height: LayoutMetrics.minToolbarItemHeight))
        return button
    }()

    private lazy var quotedReplyWrapper: UIView = {
        let view = UIView.container()
        view.backgroundColor = Theme.conversationInputBackgroundColor
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "quotedReplyWrapper")
        return view
    }()

    private lazy var linkPreviewWrapper: UIView = {
        let view = UIView.container()
        view.isHidden = true
        view.backgroundColor = Theme.conversationInputBackgroundColor
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "linkPreviewWrapper")
        return view
    }()

    private lazy var voiceMemoContentView: UIView = {
        let view = UIView.container()
        view.isHidden = true
        view.backgroundColor = Theme.conversationInputBackgroundColor
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "voiceMemoContentView")
        return view
    }()

    private lazy var voiceMemoContentViewLeftSpacer: UIView = {
        let view = UIView.container()
        view.isHidden = true
        view.autoSetDimension(.height, toSize: LayoutMetrics.minToolbarItemHeight)
        view.autoSetDimension(.width, toSize: 16)
        return view
    }()

    private lazy var voiceMemoContentViewRightSpacer: UIView = {
        let view = UIView.container()
        view.isHidden = true
        view.autoSetDimension(.height, toSize: LayoutMetrics.minToolbarItemHeight)
        view.autoSetDimension(.width, toSize: 16)
        return view
    }()

    private lazy var mediaAndSendStack: UIView = {
        let stackView =  UIStackView(arrangedSubviews: [
            voiceMemoContentViewRightSpacer,
            sendButton,
            cameraButton,
            voiceMemoButton
        ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.semanticContentAttribute = .forceLeftToRight
        stackView.setContentHuggingHorizontalHigh()
        stackView.setCompressionResistanceHorizontalHigh()
        return stackView
    }()

    private lazy var suggestedStickerView: StickerHorizontalListView = {
        let suggestedStickerSize: CGFloat = 48
        let suggestedStickerSpacing: CGFloat = 12
        let stickerListContentInset = UIEdgeInsets(hMargin: 24, vMargin: suggestedStickerSpacing)
        let view = StickerHorizontalListView(cellSize: suggestedStickerSize, cellInset: 0, spacing: suggestedStickerSpacing)
        view.backgroundColor = Theme.conversationButtonBackgroundColor
        view.contentInset = stickerListContentInset
        view.isHiddenInStackView = true
        view.autoSetDimension(.height, toSize: suggestedStickerSize + stickerListContentInset.bottom + stickerListContentInset.top)
        return view
    }()

    private lazy var outerStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [])
        stackView.axis = .vertical
        stackView.alignment = .fill
        return stackView
    }()

    private var isConfigurationComplete = false

    private var textViewHeight: CGFloat = 0
    private var textViewHeightConstraint: NSLayoutConstraint?

    private var layoutConstraints: [NSLayoutConstraint]?

    func createContentsWithMessageDraft(
        _ messageDraft: MessageBody?,
        quotedReply: OWSQuotedReplyModel?,
        inputTextViewDelegate: ConversationInputTextViewDelegate,
        mentionDelegate: MentionTextViewDelegate
    ) {
        // The input toolbar should *always* be laid out left-to-right, even when using
        // a right-to-left language. The convention for messaging apps is for the send
        // button to always be to the right of the input field, even in RTL layouts.
        // This means, in most places you'll want to pin deliberately to left/right
        // instead of leading/trailing. You'll also want to the semanticContentAttribute
        // to ensure horizontal stack views layout left-to-right.

        layoutMargins = .zero
        autoresizingMask = .flexibleHeight
        isUserInteractionEnabled = true

        // When presenting or dismissing the keyboard, there may be a slight
        // gap between the keyboard and the bottom of the input bar during
        // the animation. Extend the background below the toolbar's bounds
        // by this much to mask that extra space.
        let backgroundExtension: CGFloat = 500

        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundColor = Theme.toolbarBackgroundColor

            let extendedBackground = UIView()
            extendedBackground.backgroundColor = Theme.toolbarBackgroundColor
            addSubview(extendedBackground)
            extendedBackground.autoPinWidthToSuperview()
            extendedBackground.autoPinEdge(.top, to: .bottom, of: self)
            extendedBackground.autoSetDimension(.height, toSize: backgroundExtension)
        } else {
            backgroundColor = Theme.toolbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)

            let blurEffectView = UIVisualEffectView(effect: Theme.barBlurEffect)
            blurEffectView.layer.zPosition = -1
            addSubview(blurEffectView)
            blurEffectView.autoPinWidthToSuperview()
            blurEffectView.autoPinEdge(toSuperviewEdge: .top)
            blurEffectView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -backgroundExtension)
        }

        // NOTE: Don't set inputTextViewDelegate until configuration is complete.
        inputTextView.mentionDelegate = mentionDelegate
        inputTextView.inputTextViewDelegate = inputTextViewDelegate

        textViewHeightConstraint = inputTextView.autoSetDimension(.height, toSize: LayoutMetrics.minTextViewHeight)

        if DebugFlags.internalLogging {
            OWSLogger.info("")
        }

        quotedReplyWrapper.isHidden = quotedReply == nil
        self.quotedReply = quotedReply

        // V Stack
        let vStack = UIStackView(arrangedSubviews: [ quotedReplyWrapper, linkPreviewWrapper, inputTextView ])
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.setContentHuggingHorizontalLow()
        vStack.setCompressionResistanceHorizontalLow()
        vStack.addSubview(voiceMemoContentView)
        voiceMemoContentView.autoPinEdges(toEdgesOf: inputTextView)

        for button in [ cameraButton, attachmentButton, stickerButton, voiceMemoButton, sendButton ] {
            button.setContentHuggingHorizontalHigh()
            button.setCompressionResistanceHorizontalHigh()
        }

        // V Stack Wrapper
        let vStackRoundingView = UIView.container()
        vStackRoundingView.layer.cornerRadius = 18
        vStackRoundingView.clipsToBounds = true
        vStackRoundingView.addSubview(vStack)
        vStack.autoPinEdgesToSuperviewEdges()
        vStackRoundingView.setContentHuggingHorizontalLow()
        vStackRoundingView.setCompressionResistanceHorizontalLow()

        let vStackRoundingOffsetView = UIView.container()
        vStackRoundingOffsetView.addSubview(vStackRoundingView)
        let textViewCenterInset = 0.5 * (LayoutMetrics.minToolbarItemHeight - LayoutMetrics.minTextViewHeight)
        vStackRoundingView.autoPinEdge(toSuperviewEdge: .bottom, withInset: textViewCenterInset)
        vStackRoundingView.autoPinEdge(toSuperviewEdge: .top)
        vStackRoundingView.autoPinEdge(toSuperviewEdge: .left)
        vStackRoundingView.autoPinEdge(toSuperviewEdge: .right, withInset: 8)

        // H Stack
        let hStack = UIStackView(arrangedSubviews: [
            voiceMemoContentViewLeftSpacer,
            attachmentButton,
            vStackRoundingOffsetView,
            mediaAndSendStack
        ])
        hStack.axis = .horizontal
        hStack.alignment = .bottom
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(margin: 6)
        hStack.semanticContentAttribute = .forceLeftToRight

        // "Outer" Stack
        outerStack.addArrangedSubviews([ suggestedStickerView, hStack ])
        addSubview(outerStack)
        outerStack.autoPinEdge(toSuperviewEdge: .top)
        outerStack.autoPinEdge(toSuperviewSafeArea: .bottom)

        // See comments on updateContentLayout:.
        suggestedStickerView.insetsLayoutMarginsFromSafeArea = false
        vStack.insetsLayoutMarginsFromSafeArea = false
        vStackRoundingOffsetView.insetsLayoutMarginsFromSafeArea = false
        hStack.insetsLayoutMarginsFromSafeArea = false
        outerStack.insetsLayoutMarginsFromSafeArea = false
        insetsLayoutMarginsFromSafeArea = false

        suggestedStickerView.preservesSuperviewLayoutMargins = false
        vStack.preservesSuperviewLayoutMargins = false
        vStackRoundingOffsetView.preservesSuperviewLayoutMargins = false
        hStack.preservesSuperviewLayoutMargins = false
        outerStack.preservesSuperviewLayoutMargins = false
        preservesSuperviewLayoutMargins = false

        // Input buttons
        addSubview(stickerButton)
        stickerButton.autoAlignAxis(.horizontal, toSameAxisOf: inputTextView)
        stickerButton.autoPinEdge(.trailing, to: .trailing, of: vStackRoundingView, withOffset: -4)

        setMessageBody(messageDraft, animated: false, doLayout: false)

        isConfigurationComplete = true
    }

    private func ensureButtonVisibility(withAnimation isAnimated: Bool, doLayout: Bool) {
        var didChangeLayout = false
        let ensureViewHiddenState: (UIView, Bool) -> Void = { subview, isHidden in
            if subview.isHidden != isHidden {
                subview.isHidden = isHidden
                didChangeLayout = true
            }
        }

        // NOTE: We use untrimmedText, so that the sticker button disappears
        //       even if the user just enters whitespace.
        let hasTextInput = !inputTextView.untrimmedText.isEmpty
        // We used trimmed text for determining all the other button visibility.
        let hasNonWhitespaceTextInput = !inputTextView.trimmedText.isEmpty
        let isShowingVoiceMemoUI = isShowingVoiceMemoUI

        ensureViewHiddenState(attachmentButton, false)
        if isShowingVoiceMemoUI {
            let hideSendButton = voiceMemoRecordingState == .recordingHeld
            ensureViewHiddenState(linkPreviewWrapper, true)
            ensureViewHiddenState(voiceMemoContentView, false)
            ensureViewHiddenState(voiceMemoContentViewLeftSpacer, false)
            ensureViewHiddenState(voiceMemoContentViewRightSpacer, !hideSendButton)
            ensureViewHiddenState(cameraButton, true)
            ensureViewHiddenState(voiceMemoButton, true)
            ensureViewHiddenState(sendButton, hideSendButton)
            ensureViewHiddenState(attachmentButton, true)
        } else if hasNonWhitespaceTextInput {
            ensureViewHiddenState(linkPreviewWrapper, false)
            ensureViewHiddenState(voiceMemoContentView, true)
            ensureViewHiddenState(voiceMemoContentViewLeftSpacer, true)
            ensureViewHiddenState(voiceMemoContentViewRightSpacer, true)
            ensureViewHiddenState(cameraButton, true)
            ensureViewHiddenState(voiceMemoButton, true)
            ensureViewHiddenState(sendButton, false)
            ensureViewHiddenState(attachmentButton, false)
        } else {
            ensureViewHiddenState(linkPreviewWrapper, false)
            ensureViewHiddenState(voiceMemoContentView, true)
            ensureViewHiddenState(voiceMemoContentViewLeftSpacer, true)
            ensureViewHiddenState(voiceMemoContentViewRightSpacer, true)
            ensureViewHiddenState(cameraButton, false)
            ensureViewHiddenState(voiceMemoButton, false)
            ensureViewHiddenState(sendButton, true)
            ensureViewHiddenState(attachmentButton, false)
        }

        // If the layout has changed, update the layout
        // of the "media and send" stack immediately,
        // to avoid a janky animation where these buttons
        // move around far from their final positions.
        if doLayout && didChangeLayout {
            mediaAndSendStack.setNeedsLayout()
            mediaAndSendStack.layoutIfNeeded()
        }

        let updateBlock: () -> Void = {
            let hideStickerButton = hasTextInput || isShowingVoiceMemoUI || self.quotedReply != nil
            ensureViewHiddenState(self.stickerButton, hideStickerButton)
            if !hideStickerButton {
                self.stickerButton.imageView?.tintColor = self.desiredKeyboardType == .sticker ? UIColor.ows_accentBlue : Theme.primaryIconColor
            }

            self.attachmentButton.setSelected(self.desiredKeyboardType == .attachment, animated: isAnimated)

            self.updateSuggestedStickers()
        }

        // we had some strange effects (invisible text areas) animating the final [self layoutIfNeeded] block
        // this approach seems to be a valid workaround
        if isAnimated {
            UIView.animate(
                withDuration: 0.1,
                animations: updateBlock,
                completion: { _ in
                    guard doLayout else { return }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.layoutIfNeeded()
                    }
                }
            )
        } else {
            updateBlock()
            if doLayout {
                layoutIfNeeded()
            }
        }
    }

    private func updateContentLayout() {
        // iOS doesn't always update the safeAreaInsets correctly & in a timely
        // way for the inputAccessoryView after a orientation change.  The best
        // workaround appears to be to use the safeAreaInsets from
        // ConversationViewController's view.  ConversationViewController updates
        // this input toolbar using updateLayoutWithIsLandscape:.

        if let layoutConstraints = layoutConstraints {
            NSLayoutConstraint.deactivate(layoutConstraints)
        }

        layoutConstraints = [
            outerStack.autoPinEdge(toSuperviewEdge: .left, withInset: receivedSafeAreaInsets.left),
            outerStack.autoPinEdge(toSuperviewEdge: .right, withInset: receivedSafeAreaInsets.right)
        ]
    }

    func updateLayout(withSafeAreaInsets safeAreaInsets: UIEdgeInsets) -> Bool {
        let insetsChanged = receivedSafeAreaInsets != safeAreaInsets
        let needLayoutConstraints = layoutConstraints == nil
        guard insetsChanged || needLayoutConstraints else {
            return false
        }

        receivedSafeAreaInsets = safeAreaInsets
        updateContentLayout()
        return true
    }

    func updateFontSizes() {
        inputTextView.font = .ows_dynamicTypeBody
    }

    // MARK: Message Body

    var messageBody: MessageBody? { inputTextView.messageBody }

    func setMessageBody(_ messageBody: MessageBody?, animated: Bool, doLayout: Bool = true) {
        inputTextView.messageBody = messageBody

        // It's important that we set the textViewHeight before
        // doing any animation in `ensureButtonVisibility(withAnimation:doLayout)`
        // Otherwise, the resultant keyboard frame posted in `keyboardWillChangeFrame`
        // could reflect the inputTextView height *before* the new text was set.
        //
        // This bug was surfaced to the user as:
        //  - have a quoted reply draft in the input toolbar
        //  - type a multiline message
        //  - hit send
        //  - quoted reply preview and message text is cleared
        //  - input toolbar is shrunk to it's expected empty-text height
        //  - *but* the conversation's bottom content inset was too large. Specifically, it was
        //    still sized as if the input textview was multiple lines.
        // Presumably this bug only surfaced when an animation coincides with more complicated layout
        // changes (in this case while simultaneous with removing quoted reply subviews, hiding the
        // wrapper view *and* changing the height of the input textView
        ensureTextViewHeight()
        updateInputLinkPreview()

        if let text = messageBody?.text, !text.isEmpty {
            clearDesiredKeyboard()
        }

        ensureButtonVisibility(withAnimation: animated, doLayout: doLayout)
    }

    func ensureTextViewHeight() {
        updateHeightWithTextView(inputTextView)
    }

    func acceptAutocorrectSuggestion() {
        inputTextView.acceptAutocorrectSuggestion()
    }

    func clearTextMessage(animated: Bool) {
        setMessageBody(nil, animated: animated)
        inputTextView.undoManager?.removeAllActions()
        wasLinkPreviewCancelled = false
    }

    // MARK: Quoted Reply

    class var quotedReplyAnimationDuration: TimeInterval { 0.2 }

    private(set) var isAnimatingQuotedReply = false

    var quotedReply: OWSQuotedReplyModel? {
        didSet {
            guard oldValue != quotedReply else { return }

            layer.removeAllAnimations()

            guard let quotedReply = quotedReply else {
                isAnimatingQuotedReply = true
                UIView.animate(
                    withDuration: ConversationInputToolbar.quotedReplyAnimationDuration,
                    animations: {
                        self.quotedReplyWrapper.isHidden = true
                    },
                    completion: { _ in
                        self.isAnimatingQuotedReply = false
                        self.quotedReplyWrapper.removeAllSubviews()
                        self.layoutIfNeeded()
                    }
                )
                ensureButtonVisibility(withAnimation: false, doLayout: true)
                return
            }

            quotedReplyWrapper.removeAllSubviews()

            let quotedMessagePreview = QuotedReplyPreview(quotedReply: quotedReply, conversationStyle: conversationStyle)
            quotedMessagePreview.delegate = self
            quotedMessagePreview.setContentHuggingHorizontalLow()
            quotedMessagePreview.setCompressionResistanceHorizontalLow()
            quotedMessagePreview.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "quotedMessagePreview")

            quotedReplyWrapper.layoutMargins = .zero
            quotedReplyWrapper.addSubview(quotedMessagePreview)
            quotedMessagePreview.autoPinEdgesToSuperviewMargins()

            // hasAsymmetricalRounding may have changed.
            clearLinkPreviewView()
            updateInputLinkPreview()
            if quotedReplyWrapper.isHidden {
                isAnimatingQuotedReply = true
                UIView.animate(
                    withDuration: ConversationInputToolbar.quotedReplyAnimationDuration,
                    animations: {
                        self.quotedReplyWrapper.isHidden = false
                    },
                    completion: { _ in
                        self.isAnimatingQuotedReply = false
                    }
                )
            }

            clearDesiredKeyboard()
        }
    }

    var draftReply: ThreadReplyInfo? {
        guard let quotedReply = quotedReply else { return nil }
        return ThreadReplyInfo(timestamp: quotedReply.timestamp, authorAddress: quotedReply.authorAddress)
    }

    func quotedReplyPreviewDidPressCancel(_ preview: QuotedReplyPreview) {
        if DebugFlags.internalLogging {
            OWSLogger.info("")
        }
        quotedReply = nil
    }

    // MARK: Link Preview

    private class InputLinkPreview: Equatable {
        let previewUrl: URL
        var linkPreviewDraft: OWSLinkPreviewDraft?

        required init(previewUrl: URL) {
            self.previewUrl = previewUrl
        }

        static func == (lhs: ConversationInputToolbar.InputLinkPreview, rhs: ConversationInputToolbar.InputLinkPreview) -> Bool {
            return lhs.previewUrl == rhs.previewUrl
        }
    }

    private var inputLinkPreview: InputLinkPreview?

    private var linkPreviewView: LinkPreviewView?

    private var wasLinkPreviewCancelled = false

    var linkPreviewDraft: OWSLinkPreviewDraft? {
        AssertIsOnMainThread()

        guard !wasLinkPreviewCancelled else { return nil }

        return inputLinkPreview?.linkPreviewDraft
    }

    private func updateInputLinkPreview() {
        AssertIsOnMainThread()

        guard let bodyText = messageBody?.text.trimmingCharacters(in: .whitespacesAndNewlines), !bodyText.isEmpty else {
            clearLinkPreviewStateAndView()
            wasLinkPreviewCancelled = false
            return
        }

        guard !wasLinkPreviewCancelled else {
            clearLinkPreviewStateAndView()
            return
        }

        // Don't include link previews for oversize text messages.
        guard bodyText.lengthOfBytes(using: .utf8) < kOversizeTextMessageSizeThreshold else {
            clearLinkPreviewStateAndView()
            return
        }

        guard
            let previewUrl = linkPreviewManager.findFirstValidUrl(in: inputTextView.text, bypassSettingsCheck: false),
            !previewUrl.absoluteString.isEmpty else
        {
            clearLinkPreviewStateAndView()
            return
        }

        guard previewUrl != inputLinkPreview?.previewUrl else {
            // No need to update.
            return
        }

        let inputLinkPreview = InputLinkPreview(previewUrl: previewUrl)
        self.inputLinkPreview = inputLinkPreview

        ensureLinkPreviewView(withState: LinkPreviewLoading(linkType: .preview))

        linkPreviewManager.fetchLinkPreview(for: previewUrl)
            .done { [weak self] linkPreviewDraft in
                guard let self = self else { return }
                guard self.inputLinkPreview == inputLinkPreview else {
                    // Obsolete callback.
                    return
                }
                inputLinkPreview.linkPreviewDraft = linkPreviewDraft
                self.ensureLinkPreviewView(withState: LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft))
            }
            .catch { [weak self] _ in
                // The link preview could not be loaded.
                self?.clearLinkPreviewView()
            }
    }

    private func ensureLinkPreviewView(withState state: LinkPreviewState) {
        AssertIsOnMainThread()

        // TODO: We could re-use LinkPreviewView now.
        clearLinkPreviewView()

        let linkPreviewView = LinkPreviewView(draftDelegate: self)
        linkPreviewView.configureForNonCVC(state: state, isDraft: true, hasAsymmetricalRounding: quotedReply == nil)
        self.linkPreviewView = linkPreviewView

        linkPreviewWrapper.isHidden = false
        linkPreviewWrapper.addSubview(linkPreviewView)
        linkPreviewView.autoPinEdgesToSuperviewMargins()
        linkPreviewWrapper.layoutIfNeeded()
    }

    private func clearLinkPreviewStateAndView() {
        AssertIsOnMainThread()

        inputLinkPreview = nil
        linkPreviewView = nil
        clearLinkPreviewView()
    }

    private func clearLinkPreviewView() {
        AssertIsOnMainThread()

        linkPreviewWrapper.removeAllSubviews()
        linkPreviewWrapper.isHidden = true
    }

    // MARK: LinkPreviewViewDraftDelegate

    public func linkPreviewCanCancel() -> Bool {
        return true
    }

    public func linkPreviewDidCancel() {
        AssertIsOnMainThread()

        wasLinkPreviewCancelled = true
        inputLinkPreview = nil
        clearLinkPreviewStateAndView()
    }

    // MARK: Stickers

    private let suggestedStickerViewCache = StickerViewCache(maxSize: 12)

    private var suggestedStickerInfos: [StickerInfo] = [] {
        didSet {
            guard suggestedStickerInfos != oldValue else { return }
            updateSuggestedStickerView()
        }
    }

    private func updateSuggestedStickers() {
        suggestedStickerInfos = StickerManager.shared.suggestedStickers(forTextInput: inputTextView.trimmedText).map { $0.info }
    }

    private func updateSuggestedStickerView() {
        guard !suggestedStickerInfos.isEmpty else {
            suggestedStickerView.isHiddenInStackView = true
            layoutIfNeeded()
            return
        }

        let shouldReset = suggestedStickerView.isHidden
        suggestedStickerView.items = suggestedStickerInfos.map { stickerInfo in
            StickerHorizontalListViewItemSticker(
                stickerInfo: stickerInfo,
                didSelectBlock: { [weak self] in
                    self?.didSelectSuggestedSticker(stickerInfo)
                },
                cache: suggestedStickerViewCache
            )
        }
        suggestedStickerView.isHiddenInStackView = false
        layoutIfNeeded()

        if shouldReset {
            suggestedStickerView.contentOffset = CGPoint(
                x: -suggestedStickerView.contentInset.left,
                y: -suggestedStickerView.contentInset.top
            )
        }
    }

    private func didSelectSuggestedSticker(_ stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        clearTextMessage(animated: true)
        inputToolbarDelegate?.sendSticker(stickerInfo)
    }

    // MARK: Voice Memo

    private enum VoiceMemoRecordingState {
        case idle
        case recordingHeld
        case recordingLocked
        case draft
    }

    private var voiceMemoRecordingState: VoiceMemoRecordingState = .idle {
        didSet {
            guard oldValue != voiceMemoRecordingState else { return }
            ensureButtonVisibility(withAnimation: true, doLayout: true)
        }
    }
    private var voiceMemoGestureStartLocation: CGPoint?

    private var isShowingVoiceMemoUI: Bool = false {
        didSet {
            guard isShowingVoiceMemoUI != oldValue else { return }
            ensureButtonVisibility(withAnimation: true, doLayout: true)
        }
    }

    var voiceMemoDraft: VoiceMessageModel?
    private var voiceMemoStartTime: Date?
    private var voiceMemoUpdateTimer: Timer?
    private var voiceMemoTooltipView: UIView?
    private var voiceMemoRecordingLabel: UILabel?
    private var voiceMemoCancelLabel: UILabel?
    private var voiceMemoRedRecordingCircle: UIView?
    private var voiceMemoLockView: VoiceMemoLockView?

    func showVoiceMemoUI() {
        AssertIsOnMainThread()

        isShowingVoiceMemoUI = true

        removeVoiceMemoTooltip()

        voiceMemoStartTime = Date()

        voiceMemoRedRecordingCircle?.removeFromSuperview()
        voiceMemoLockView?.removeFromSuperview()

        voiceMemoContentView.removeAllSubviews()

        let recordingLabel = UILabel()
        recordingLabel.textAlignment = .left
        recordingLabel.textColor = Theme.primaryTextColor
        recordingLabel.font = .ows_dynamicTypeBodyClamped.ows_medium.ows_monospaced
        recordingLabel.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "recordingLabel")
        voiceMemoContentView.addSubview(recordingLabel)
        self.voiceMemoRecordingLabel = recordingLabel

        updateVoiceMemo()

        let cancelArrowFontSize = ScaleFromIPhone5To7Plus(18.4, 20)
        let cancelString = NSMutableAttributedString(
            string: "\u{F104}",
            attributes: [
                .font: UIFont.ows_fontAwesomeFont(cancelArrowFontSize),
                .foregroundColor: Theme.secondaryTextAndIconColor,
                .baselineOffset: -1
            ]
        )
        cancelString.append(
            NSAttributedString(
                string: "  ",
                attributes: [
                    .font: UIFont.ows_fontAwesomeFont(cancelArrowFontSize),
                    .foregroundColor: Theme.secondaryTextAndIconColor,
                    .baselineOffset: -1
                ]
            )
        )
        cancelString.append(
            NSAttributedString(
                string: NSLocalizedString("VOICE_MESSAGE_CANCEL_INSTRUCTIONS", comment: "Indicates how to cancel a voice message."),
                attributes: [
                    .font: UIFont.ows_dynamicTypeSubheadlineClamped,
                    .foregroundColor: Theme.secondaryTextAndIconColor
                ]
            )
        )
        let cancelLabel = UILabel()
        cancelLabel.textAlignment = .right
        cancelLabel.attributedText = cancelString
        voiceMemoContentView.addSubview(cancelLabel)
        self.voiceMemoCancelLabel = cancelLabel

        let redCircleView = CircleView(diameter: 80)
        redCircleView.backgroundColor = .ows_accentRed
        let whiteIconView = UIImageView(image: UIImage(imageLiteralResourceName: "mic-solid-36"))
        redCircleView.addSubview(whiteIconView)
        whiteIconView.autoCenterInSuperview()
        addSubview(redCircleView)
        redCircleView.autoAlignAxis(.horizontal, toSameAxisOf: voiceMemoContentView)
        redCircleView.autoPinEdge(toSuperviewEdge: .right, withInset: 12)
        self.voiceMemoRedRecordingCircle = redCircleView

        let imageView = UIImageView(image: UIImage(imageLiteralResourceName: "mic-solid-24").withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .ows_accentRed
        imageView.setContentHuggingHigh()
        voiceMemoContentView.addSubview(imageView)
        imageView.autoVCenterInSuperview()
        imageView.autoPinEdge(toSuperviewEdge: .left, withInset: 12)

        recordingLabel.autoVCenterInSuperview()
        recordingLabel.autoPinEdge(.left, to: .right, of: imageView, withOffset: 8)

        cancelLabel.autoVCenterInSuperview()
        cancelLabel.autoPinEdge(toSuperviewEdge: .right, withInset: 72)
        cancelLabel.autoPinEdge(.left, to: .right, of: recordingLabel)

        let voiceMemoLockView = VoiceMemoLockView()
        insertSubview(voiceMemoLockView, belowSubview: redCircleView)
        voiceMemoLockView.autoAlignAxis(.vertical, toSameAxisOf: redCircleView)
        voiceMemoLockView.autoPinEdge(.bottom, to: .top, of: redCircleView)
        voiceMemoLockView.setCompressionResistanceHigh()
        self.voiceMemoLockView = voiceMemoLockView

        voiceMemoLockView.transform = CGAffineTransform.scale(0)
        voiceMemoLockView.layoutIfNeeded()
        UIView.animate(withDuration: 0.2, delay: 1) {
            voiceMemoLockView.transform = .identity
        }

        redCircleView.transform = CGAffineTransform.scale(0)
        UIView.animate(withDuration: 0.2) {
            redCircleView.transform = .identity
        }

        // Pulse the icon.
        imageView.alpha = 1
        UIView.animate(
            withDuration: 0.5,
            delay: 0.2,
            options: [.repeat, .autoreverse, .curveEaseIn],
            animations: {
                imageView.alpha = 0
            }
        )

        voiceMemoUpdateTimer?.invalidate()
        voiceMemoUpdateTimer = Timer.weakScheduledTimer(
            withTimeInterval: 0.1,
            target: self,
            selector: #selector(updateVoiceMemo),
            userInfo: nil,
            repeats: true)
    }

    func showVoiceMemoDraft(_ voiceMemoDraft: VoiceMessageModel) {
        AssertIsOnMainThread()

        isShowingVoiceMemoUI = true

        self.voiceMemoDraft = voiceMemoDraft
        voiceMemoRecordingState = .draft

        removeVoiceMemoTooltip()

        voiceMemoRedRecordingCircle?.removeFromSuperview()
        voiceMemoLockView?.removeFromSuperview()

        voiceMemoContentView.removeAllSubviews()

        voiceMemoUpdateTimer?.invalidate()
        voiceMemoUpdateTimer = nil

        let draftView = VoiceMessageDraftView(
            voiceMessageModel: voiceMemoDraft,
            mediaCache: mediaCache) { [weak self] in
                self?.hideVoiceMemoUI(animated: true)
            }
        voiceMemoContentView.addSubview(draftView)
        draftView.autoPinEdgesToSuperviewEdges()
    }

    func hideVoiceMemoUI(animated: Bool) {
        AssertIsOnMainThread()

        isShowingVoiceMemoUI = false

        voiceMemoContentView.removeAllSubviews()

        voiceMemoRecordingState = .idle
        voiceMemoDraft = nil

        let oldVoiceMemoRedRecordingCircle = voiceMemoRedRecordingCircle
        let oldVoiceMemoLockView = voiceMemoLockView

        voiceMemoCancelLabel = nil
        voiceMemoRedRecordingCircle = nil
        voiceMemoLockView = nil
        voiceMemoRecordingLabel = nil

        voiceMemoUpdateTimer?.invalidate()
        voiceMemoUpdateTimer = nil

        voiceMemoDraft = nil

        if animated {
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    oldVoiceMemoRedRecordingCircle?.alpha = 0
                    oldVoiceMemoLockView?.alpha = 0
                },
                completion: { _ in
                    oldVoiceMemoRedRecordingCircle?.removeFromSuperview()
                    oldVoiceMemoLockView?.removeFromSuperview()
                }
            )
        } else {
            oldVoiceMemoRedRecordingCircle?.removeFromSuperview()
            oldVoiceMemoLockView?.removeFromSuperview()
        }
    }

    func lockVoiceMemoUI() {
        guard let voiceMemoRecordingLabel = voiceMemoRecordingLabel else {
            owsFailDebug("voiceMemoRecordingLabel == nil")
            return
        }

        ImpactHapticFeedback.impactOccured(style: .medium)

        let cancelButton = OWSButton(block: { [weak self] in
            self?.inputToolbarDelegate?.voiceMemoGestureDidCancel()
        })
        cancelButton.alpha = 0
        cancelButton.setTitle(CommonStrings.cancelButton, for: .normal)
        cancelButton.setTitleColor(.ows_accentRed, for: .normal)
        cancelButton.setTitleColor(.ows_accentRed.withAlphaComponent(0.4), for: .highlighted)
        cancelButton.titleLabel?.textAlignment = .right
        cancelButton.titleLabel?.font = .ows_dynamicTypeBodyClamped.ows_medium
        cancelButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "cancelButton")
        voiceMemoContentView.addSubview(cancelButton)

        voiceMemoRecordingLabel.setContentHuggingHigh()

        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            cancelButton.autoHCenterInSuperview()
        }
        cancelButton.autoPinEdge(toSuperviewMargin: .right, withInset: 40)
        cancelButton.autoPinEdge(.left, to: .right, of: voiceMemoRecordingLabel, withOffset: 4, relation: .greaterThanOrEqual)
        cancelButton.autoVCenterInSuperview()

        voiceMemoCancelLabel?.removeFromSuperview()
        voiceMemoContentView.layoutIfNeeded()
        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.voiceMemoRedRecordingCircle?.alpha = 0
                self.voiceMemoLockView?.alpha = 0
                cancelButton.alpha = 1
            },
            completion: { _ in
                self.voiceMemoRedRecordingCircle?.removeFromSuperview()
                self.voiceMemoLockView?.removeFromSuperview()
                UIAccessibility.post(notification: .layoutChanged, argument: nil)
            }
        )
    }

    private func setVoiceMemoUICancelAlpha(_ cancelAlpha: CGFloat) {
        AssertIsOnMainThread()

        // Fade out the voice message views as the cancel gesture
        // proceeds as feedback.
        voiceMemoCancelLabel?.alpha = CGFloatClamp01(1 - cancelAlpha)
    }

    @objc
    private func updateVoiceMemo() {
        AssertIsOnMainThread()

        guard
            let voiceMemoStartTime = voiceMemoStartTime,
            let voiceMemoRecordingLabel = voiceMemoRecordingLabel
        else {
            return
        }

        let durationSeconds = abs(voiceMemoStartTime.timeIntervalSinceNow)
        voiceMemoRecordingLabel.text = OWSFormat.formatDurationSeconds(Int(round(durationSeconds)))
        voiceMemoRecordingLabel.sizeToFit()
    }

    func showVoiceMemoTooltip() {
        guard voiceMemoTooltipView == nil else { return }

        let tooltipView = VoiceMessageTooltip(
            fromView: self,
            widthReferenceView: self,
            tailReferenceView: voiceMemoButton) { [weak self] in
                self?.removeVoiceMemoTooltip()
            }
        voiceMemoTooltipView = tooltipView

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.removeVoiceMemoTooltip()
        }
    }

    private func removeVoiceMemoTooltip() {
        guard let voiceMemoTooltipView = voiceMemoTooltipView else { return }

        self.voiceMemoTooltipView = nil

        UIView.animate(
            withDuration: 0.2,
            animations: {
                voiceMemoTooltipView.alpha = 0
            },
            completion: { _ in
                voiceMemoTooltipView.removeFromSuperview()
            }
        )
    }

    @objc
    private func handleVoiceMemoLongPress(gesture: UILongPressGestureRecognizer) {
        switch gesture.state {

        case .possible, .cancelled, .failed:
            guard voiceMemoRecordingState != .idle else { return }
            // Record a draft if we were actively recording.
            voiceMemoRecordingState = .idle
            inputToolbarDelegate?.voiceMemoGestureWasInterrupted()

        case .began:
            switch voiceMemoRecordingState {
            case .idle: break

            case .recordingHeld:
                owsFailDebug("while recording held, shouldn't be possible to restart gesture.")
                inputToolbarDelegate?.voiceMemoGestureDidCancel()

            case .recordingLocked, .draft:
                owsFailDebug("once locked, shouldn't be possible to interact with gesture.")
                inputToolbarDelegate?.voiceMemoGestureDidCancel()
            }

            // Start voice message.
            voiceMemoRecordingState = .recordingHeld
            voiceMemoGestureStartLocation = gesture.location(in: self)
            inputToolbarDelegate?.voiceMemoGestureDidStart()

        case .changed:
            guard isShowingVoiceMemoUI else { return }
            guard let voiceMemoGestureStartLocation = voiceMemoGestureStartLocation else {
                owsFailDebug("voiceMemoGestureStartLocation is nil")
                return
            }

            // Check for "slide to cancel" gesture.
            let location = gesture.location(in: self)
            // For LTR/RTL, swiping in either direction will cancel.
            // This is okay because there's only space on screen to perform the
            // gesture in one direction.
            let xOffset = abs(voiceMemoGestureStartLocation.x - location.x)
            let yOffset = abs(voiceMemoGestureStartLocation.y - location.y)

            // Require a certain threshold before we consider the user to be
            // interacting with the lock ui, otherwise there's perceptible wobble
            // of the lock slider even when the user isn't intended to interact with it.
            let lockThresholdPoints: CGFloat = 20
            let lockOffsetPoints: CGFloat = 80
            let yOffsetBeyondThreshold = max(yOffset - lockThresholdPoints, 0)
            let lockAlpha = yOffsetBeyondThreshold / lockOffsetPoints
            let isLocked = lockAlpha >= 1
            if isLocked {
                switch voiceMemoRecordingState {
                case .recordingHeld:
                    voiceMemoRecordingState = .recordingLocked
                    inputToolbarDelegate?.voiceMemoGestureDidLock()
                    setVoiceMemoUICancelAlpha(0)

                case .recordingLocked, .draft:
                    // already locked
                    break

                case .idle:
                    owsFailDebug("failure: unexpeceted idle state")
                    inputToolbarDelegate?.voiceMemoGestureDidCancel()
                }
            } else {
                voiceMemoLockView?.update(ratioComplete: lockAlpha)

                // The lower this value, the easier it is to cancel by accident.
                // The higher this value, the harder it is to cancel.
                let cancelOffsetPoints: CGFloat = 100
                let cancelAlpha = xOffset / cancelOffsetPoints
                let isCancelled = cancelAlpha >= 1
                guard !isCancelled else {
                    voiceMemoRecordingState = .idle
                    inputToolbarDelegate?.voiceMemoGestureDidCancel()
                    return
                }

                setVoiceMemoUICancelAlpha(cancelAlpha)

                if xOffset > yOffset {
                    voiceMemoRedRecordingCircle?.transform = CGAffineTransform(translationX: min(-xOffset, 0), y: 0)
                } else if yOffset > xOffset {
                    voiceMemoRedRecordingCircle?.transform = CGAffineTransform(translationX: 0, y: min(-yOffset, 0))
                } else {
                    voiceMemoRedRecordingCircle?.transform = .identity
                }
            }

        case .ended:
            switch voiceMemoRecordingState {
            case .idle:
                break

            case .recordingHeld:
                // End voice message.
                voiceMemoRecordingState = .idle
                inputToolbarDelegate?.voiceMemoGestureDidComplete()

            case .recordingLocked, .draft:
                // Continue recording.
                break
            }

        @unknown default: break
        }
    }

    // MARK: Keyboards

    private(set) var isMeasuringKeyboardHeight = false
    private var hasMeasuredKeyboardHeight = false

    private enum KeyboardType {
        case system
        case sticker
        case attachment
    }

    private var _desiredKeyboardType: KeyboardType = .system

    private var desiredKeyboardType: KeyboardType {
        get { _desiredKeyboardType }
        set { setDesiredKeyboardType(newValue, animated: false) }
    }

    private var _stickerKeyboard: StickerKeyboard?

    private var stickerKeyboard: StickerKeyboard {
        if let stickerKeyboard = _stickerKeyboard {
            return stickerKeyboard
        }
        let keyboard = StickerKeyboard()
        keyboard.delegate = self
        keyboard.registerWithView(self)
        _stickerKeyboard = keyboard
        return keyboard
    }

    private var stickerKeyboardIfLoaded: StickerKeyboard? { _stickerKeyboard }

    func showStickerKeyboard() {
        AssertIsOnMainThread()
        guard desiredKeyboardType != .sticker else { return }
        toggleKeyboardType(.sticker, animated: false)
    }

    private var _attachmentKeyboard: AttachmentKeyboard?

    private var attachmentKeyboard: AttachmentKeyboard {
        if let attachmentKeyboard = _attachmentKeyboard {
            return attachmentKeyboard
        }
        let keyboard = AttachmentKeyboard()
        keyboard.delegate = self
        keyboard.registerWithView(self)
        _attachmentKeyboard = keyboard
        return keyboard
    }

    private var attachmentKeyboardIfLoaded: AttachmentKeyboard? { _attachmentKeyboard }

    func showAttachmentKeyboard() {
        AssertIsOnMainThread()
        guard desiredKeyboardType != .attachment else { return }
        toggleKeyboardType(.attachment, animated: false)
    }

    private func toggleKeyboardType(_ keyboardType: KeyboardType, animated: Bool) {
        guard let inputToolbarDelegate = inputToolbarDelegate else {
            owsFailDebug("inputToolbarDelegate is nil")
            return
        }

        if desiredKeyboardType == keyboardType {
            setDesiredKeyboardType(.system, animated: animated)
        } else {
            // For switching to anything other than the system keyboard,
            // make sure this conversation isn't blocked before presenting it.
            if inputToolbarDelegate.isBlockedConversation() {
                inputToolbarDelegate.showUnblockConversationUI { [weak self] isBlocked in
                    guard let self = self, !isBlocked else { return }
                    self.toggleKeyboardType(keyboardType, animated: animated)
                }
                return
            }

            setDesiredKeyboardType(keyboardType, animated: animated)
        }

        beginEditingMessage()
    }

    private func setDesiredKeyboardType(_ keyboardType: KeyboardType, animated: Bool) {
        guard _desiredKeyboardType != keyboardType else { return }

        _desiredKeyboardType = keyboardType

        ensureButtonVisibility(withAnimation: animated, doLayout: true)

        if isInputViewFirstResponder {
            // If any keyboard is presented, make sure the correct
            // keyboard is presented.
            beginEditingMessage()
        } else {
            // Make sure neither keyboard is presented.
            endEditingMessage()
        }
    }

    func clearDesiredKeyboard() {
        AssertIsOnMainThread()
        desiredKeyboardType = .system
    }

    private func restoreDesiredKeyboardIfNecessary() {
        AssertIsOnMainThread()
        if desiredKeyboardType != .system && !desiredFirstResponder.isFirstResponder {
            desiredFirstResponder.becomeFirstResponder()
        }
    }

    private func cacheKeyboardIfNecessary() {
        // Preload the keyboard if we're not showing it already, this
        // allows us to calculate the appropriate initial height for
        // our custom inputViews and in general to present it faster
        // We disable animations so this preload is invisible to the
        // user.
        //
        // We only measure the keyboard if the toolbar isn't hidden.
        // If it's hidden, we're likely here from a peek interaction
        // and don't want to show the keyboard. We'll measure it later.
        guard !hasMeasuredKeyboardHeight && !inputTextView.isFirstResponder && !isHidden else { return }

        // Flag that we're measuring the system keyboard's height, so
        // even if though it won't be the first responder by the time
        // the notifications fire, we'll still read its measurement
        isMeasuringKeyboardHeight = true

        UIView.setAnimationsEnabled(false)

        _ = inputTextView.becomeFirstResponder()
        inputTextView.resignFirstResponder()

        inputTextView.reloadMentionState()

        UIView.setAnimationsEnabled(true)
    }

    var isInputViewFirstResponder: Bool {
        return inputTextView.isFirstResponder
        || stickerKeyboardIfLoaded?.isFirstResponder ?? false
        || attachmentKeyboardIfLoaded?.isFirstResponder ?? false
    }

    private func ensureFirstResponderState() {
        restoreDesiredKeyboardIfNecessary()
    }

    private var desiredFirstResponder: UIResponder {
        switch desiredKeyboardType {
        case .system: return inputTextView
        case .sticker: return stickerKeyboard
        case .attachment: return attachmentKeyboard
        }
    }

    func beginEditingMessage() {
        guard !desiredFirstResponder.isFirstResponder else { return }
        desiredFirstResponder.becomeFirstResponder()
    }

    func endEditingMessage() {
        inputTextView.resignFirstResponder()
        _ = stickerKeyboardIfLoaded?.resignFirstResponder()
        _ = attachmentKeyboardIfLoaded?.resignFirstResponder()
    }

    func viewDidAppear() {
        ensureButtonVisibility(withAnimation: false, doLayout: false)
        cacheKeyboardIfNecessary()
    }

    @objc
    private func applicationDidBecomeActive(notification: Notification) {
        AssertIsOnMainThread()
        restoreDesiredKeyboardIfNecessary()
    }

    @objc
    private func keyboardFrameDidChange(notification: Notification) {
        guard let keyboardEndFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            owsFailDebug("keyboardEndFrame is nil")
            return
        }

        guard inputTextView.isFirstResponder || isMeasuringKeyboardHeight else { return }
        let newHeight = keyboardEndFrame.size.height - frame.size.height
        guard newHeight > 0 else { return }
        stickerKeyboard.updateSystemKeyboardHeight(newHeight)
        attachmentKeyboard.updateSystemKeyboardHeight(newHeight)
        if isMeasuringKeyboardHeight {
            isMeasuringKeyboardHeight = false
            hasMeasuredKeyboardHeight = true
        }
    }
}

// MARK: Button Actions

extension ConversationInputToolbar {

    @objc
    private func cameraButtonPressed() {
        guard let inputToolbarDelegate = inputToolbarDelegate else {
            owsFailDebug("inputToolbarDelegate == nil")
            return
        }
        ImpactHapticFeedback.impactOccured(style: .light)
        inputToolbarDelegate.cameraButtonPressed()
    }

    @objc
    private func attachmentButtonPressed() {
        Logger.verbose("")
        ImpactHapticFeedback.impactOccured(style: .light)
        toggleKeyboardType(.attachment, animated: true)
    }

    @objc
    private func sendButtonPressed() {
        guard let inputToolbarDelegate = inputToolbarDelegate else {
            owsFailDebug("inputToolbarDelegate == nil")
            return
        }

        guard !isShowingVoiceMemoUI else {
            voiceMemoRecordingState = .idle

            guard let voiceMemoDraft = voiceMemoDraft else {
                inputToolbarDelegate.voiceMemoGestureDidComplete()
                return
            }

            inputToolbarDelegate.sendVoiceMemoDraft(voiceMemoDraft)
            return
        }

        inputToolbarDelegate.sendButtonPressed()
    }

    @objc
    private func stickerButtonPressed() {
        Logger.verbose("")

        ImpactHapticFeedback.impactOccured(style: .light)

        var hasInstalledStickerPacks: Bool = false
        databaseStorage.read { transaction in
            hasInstalledStickerPacks = !StickerManager.installedStickerPacks(transaction: transaction).isEmpty
        }
        guard hasInstalledStickerPacks else {
            presentManageStickersView()
            return
        }
        toggleKeyboardType(.sticker, animated: true)
    }
}

extension ConversationInputToolbar: ConversationTextViewToolbarDelegate {

    private func updateHeightWithTextView(_ textView: UITextView) {
        // Compute new height assuming width is unchanged

        let currentSize = textView.frame.size

        let contentSize = textView.sizeThatFits(CGSize(width: currentSize.width, height: .greatestFiniteMagnitude))

        // `textView.contentSize` isn't accurate when restoring a multiline draft, so we compute it here.
        textView.contentSize = contentSize

        let newHeight = CGFloatClamp(
            contentSize.height,
            LayoutMetrics.minTextViewHeight,
            UIDevice.current.isIPad ? LayoutMetrics.maxIPadTextViewHeight : LayoutMetrics.maxTextViewHeight
        )

        guard newHeight != textViewHeight else { return }

        textViewHeight = newHeight
        owsAssertDebug(textViewHeightConstraint != nil)
        textViewHeightConstraint?.constant = newHeight
        invalidateIntrinsicContentSize()
    }

    func textViewDidChange(_ textView: UITextView) {
        owsAssertDebug(inputToolbarDelegate != nil)

        // Ignore change events during configuration.
        guard isConfigurationComplete else { return }

        updateHeightWithTextView(textView)
        updateInputLinkPreview()
        ensureButtonVisibility(withAnimation: true, doLayout: true)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateInputLinkPreview()
    }

    func textViewDidBecomeFirstResponder(_ textView: UITextView) {
        desiredKeyboardType = .system
    }
}

extension ConversationInputToolbar: StickerKeyboardDelegate {

    public func didSelectSticker(stickerInfo: StickerInfo) {
        AssertIsOnMainThread()
        Logger.verbose("")
        inputToolbarDelegate?.sendSticker(stickerInfo)
    }

    public func presentManageStickersView() {
        AssertIsOnMainThread()
        Logger.verbose("")
        inputToolbarDelegate?.presentManageStickersView()
    }
}

extension ConversationInputToolbar: AttachmentKeyboardDelegate {

    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment) {
        inputToolbarDelegate?.didSelectRecentPhoto(asset: asset, attachment: attachment)
    }

    func didTapGalleryButton() {
        inputToolbarDelegate?.galleryButtonPressed()
    }

    func didTapCamera() {
        inputToolbarDelegate?.cameraButtonPressed()
    }

    func didTapGif() {
        inputToolbarDelegate?.gifButtonPressed()
    }

    func didTapFile() {
        inputToolbarDelegate?.fileButtonPressed()
    }

    func didTapContact() {
        inputToolbarDelegate?.contactButtonPressed()
    }

    func didTapLocation() {
        inputToolbarDelegate?.locationButtonPressed()
    }

    func didTapPayment() {
        inputToolbarDelegate?.paymentButtonPressed()
    }

    var isGroup: Bool {
        inputToolbarDelegate?.isGroup() ?? false
    }
}
