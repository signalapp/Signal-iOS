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
        self.linkPreviewFetcher = LinkPreviewFetcher(
            linkPreviewManager: Self.linkPreviewManager,
            schedulers: DependenciesBridge.shared.schedulers
        )

        super.init(frame: .zero)

        self.linkPreviewFetcher.onStateChange = { [weak self] in self?.updateLinkPreviewView() }

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
            if isAnimatingHeightChange && inputTextView.isFirstResponder {
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
        static let maxTextViewHeight: CGFloat = 98
        static let maxIPadTextViewHeight: CGFloat = 142
        static let minToolbarItemHeight: CGFloat = 52
    }

    private lazy var inputTextView: ConversationInputTextView = {
        let inputTextView = ConversationInputTextView()
        inputTextView.textViewToolbarDelegate = self
        inputTextView.font = .ows_dynamicTypeBody
        inputTextView.setContentHuggingLow()
        inputTextView.setCompressionResistanceLow()
        inputTextView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "inputTextView")
        return inputTextView
    }()

    private lazy var attachmentButton: AttachmentButton = {
        let button = AttachmentButton()
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
        button.autoSetDimensions(to: CGSize(square: LayoutMetrics.minToolbarItemHeight))
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalHigh()
        return button
    }()

    private lazy var stickerButton: UIButton = {
        let imageResourceName = Theme.isDarkThemeEnabled ? "sticker-solid-24" : "sticker-outline-24"
        let button = UIButton(type: .system)
        button.tintColor = Theme.primaryIconColor
        button.accessibilityLabel = NSLocalizedString(
            "INPUT_TOOLBAR_STICKER_BUTTON_ACCESSIBILITY_LABEL",
            comment: "accessibility label for the button which shows the sticker picker"
        )
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "stickerButton")
        button.setImage(UIImage(imageLiteralResourceName: imageResourceName), for: .normal)
        button.addTarget(self, action: #selector(stickerButtonPressed), for: .touchUpInside)
        button.autoSetDimensions(to: CGSize(width: 40, height: LayoutMetrics.minTextViewHeight))
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalHigh()
        return button
    }()

    private lazy var keyboardButton: UIButton = {
        let imageResourceName = Theme.isDarkThemeEnabled ? "keyboard-solid-24" : "keyboard-outline-24"
        let button = UIButton(type: .system)
        button.tintColor = Theme.primaryIconColor
        button.accessibilityLabel = NSLocalizedString(
            "INPUT_TOOLBAR_KEYBOARD_BUTTON_ACCESSIBILITY_LABEL",
            comment: "accessibility label for the button which shows the regular keyboard instead of sticker picker"
        )
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "keyboardButton")
        button.setImage(UIImage(imageLiteralResourceName: imageResourceName), for: .normal)
        button.addTarget(self, action: #selector(keyboardButtonPressed), for: .touchUpInside)
        button.autoSetDimensions(to: CGSize(width: 40, height: LayoutMetrics.minTextViewHeight))
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalHigh()
        return button
    }()

    private lazy var quotedReplyWrapper: UIView = {
        let view = UIView.container()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "quotedReplyWrapper")
        return view
    }()

    private lazy var linkPreviewWrapper: UIView = {
        let view = UIView.container()
        view.clipsToBounds = true
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "linkPreviewWrapper")
        return view
    }()

    private lazy var voiceMemoContentView: UIView = {
        let view = UIView.container()
        view.isHidden = true
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "voiceMemoContentView")
        return view
    }()

    private lazy var rightEdgeControlsView: RightEdgeControlsView = {
        let view = RightEdgeControlsView()
        view.sendButton.addTarget(self, action: #selector(sendButtonPressed), for: .touchUpInside)
        view.cameraButton.addTarget(self, action: #selector(cameraButtonPressed), for: .touchUpInside)
        // We want to be permissive about the voice message gesture, so we hang
        // the long press GR on the button's wrapper, not the button itself.
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleVoiceMemoLongPress(gesture:)))
        longPressGestureRecognizer.minimumPressDuration = 0
        view.voiceMemoButton.addGestureRecognizer(longPressGestureRecognizer)
        return view
    }()

    private lazy var suggestedStickerView: StickerHorizontalListView = {
        let suggestedStickerSize: CGFloat = 48
        let suggestedStickerSpacing: CGFloat = 12
        let stickerListContentInset = UIEdgeInsets(
            hMargin: OWSTableViewController2.defaultHOuterMargin,
            vMargin: suggestedStickerSpacing
        )
        let view = StickerHorizontalListView(cellSize: suggestedStickerSize, cellInset: 0, spacing: suggestedStickerSpacing)
        view.backgroundColor = Theme.conversationButtonBackgroundColor
        view.contentInset = stickerListContentInset
        view.autoSetDimension(.height, toSize: suggestedStickerSize + stickerListContentInset.bottom + stickerListContentInset.top)
        return view
    }()

    private let suggestedStickerWrapper = UIView.container()

    private let messageContentView = UIView.container()

    private let mainPanelView: UIView = {
        let view = UIView()
        view.layoutMargins = UIEdgeInsets(hMargin: OWSTableViewController2.defaultHOuterMargin - 16, vMargin: 0)
        return view
    }()

    private let mainPanelWrapperView = UIView.container()

    private var isConfigurationComplete = false

    private var textViewHeight: CGFloat = 0
    private var textViewHeightConstraint: NSLayoutConstraint?
    class var heightChangeAnimationDuration: TimeInterval { 0.25 }
    private(set) var isAnimatingHeightChange = false

    private var layoutConstraints: [NSLayoutConstraint]?

    private func createContentsWithMessageDraft(
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

        // NOTE: Don't set inputTextViewDelegate until configuration is complete.
        inputTextView.mentionDelegate = mentionDelegate
        inputTextView.inputTextViewDelegate = inputTextViewDelegate

        textViewHeightConstraint = inputTextView.autoSetDimension(.height, toSize: LayoutMetrics.minTextViewHeight)

        if DebugFlags.internalLogging {
            OWSLogger.info("")
        }

        quotedReplyWrapper.isHidden = quotedReply == nil
        self.quotedReply = quotedReply

        // Vertical stack of message component views in the center: Link Preview, Reply Quote, Text Input View.
        let messageContentVStack = UIStackView(arrangedSubviews: [ quotedReplyWrapper, linkPreviewWrapper, inputTextView ])
        messageContentVStack.axis = .vertical
        messageContentVStack.alignment = .fill
        messageContentVStack.setContentHuggingHorizontalLow()
        messageContentVStack.setCompressionResistanceHorizontalLow()

        // Voice Message UI is added to the same vertical stack, but not as arranged subview.
        // The view is constrained to text input view's edges.
        messageContentVStack.addSubview(voiceMemoContentView)
        voiceMemoContentView.autoPinEdges(toEdgesOf: inputTextView)

        // Wrap vertical stack into a view with rounded corners.
        let vStackRoundingView = UIView.container()
        vStackRoundingView.backgroundColor = Theme.isDarkThemeEnabled ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.1)
        vStackRoundingView.layer.cornerRadius = 18
        vStackRoundingView.clipsToBounds = true
        vStackRoundingView.addSubview(messageContentVStack)
        messageContentVStack.autoPinEdgesToSuperviewEdges()
        messageContentView.addSubview(vStackRoundingView)
        // This margin defines amount of padding above and below visible text input box.
        let textViewVInset = 0.5 * (LayoutMetrics.minToolbarItemHeight - LayoutMetrics.minTextViewHeight)
        vStackRoundingView.autoPinWidthToSuperview()
        vStackRoundingView.autoPinHeightToSuperview(withMargin: textViewVInset)

        // Sticker button: looks like is a part of the text input view,
        // but is reality it located a couple levels up in the view hierarchy.
        vStackRoundingView.addSubview(stickerButton)
        vStackRoundingView.addSubview(keyboardButton)
        stickerButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: 4)
        stickerButton.autoAlignAxis(.horizontal, toSameAxisOf: inputTextView)
        keyboardButton.autoAlignAxis(.vertical, toSameAxisOf: stickerButton)
        keyboardButton.autoAlignAxis(.horizontal, toSameAxisOf: stickerButton)

        // Horizontal Stack: Attachment button, message components, Camera|VoiceNote|Send button.
        //
        // + Attachment button: pinned to the bottom left corner.
        mainPanelView.addSubview(attachmentButton)
        attachmentButton.autoPinEdge(toSuperviewMargin: .left)
        attachmentButton.autoPinEdge(toSuperviewEdge: .bottom)

        // Camera | Voice Message | Send: pinned to the bottom right corner.
        mainPanelView.addSubview(rightEdgeControlsView)
        rightEdgeControlsView.autoPinEdge(toSuperviewMargin: .right)
        rightEdgeControlsView.autoPinEdge(toSuperviewEdge: .bottom)

        // Message components view: pinned to attachment button on the left, Camera button on the right,
        // taking entire superview's height.
        mainPanelView.addSubview(messageContentView)
        messageContentView.autoPinHeightToSuperview()
        messageContentView.autoPinEdge(.right, to: .left, of: rightEdgeControlsView)
        updateMessageContentViewLeftEdgeConstraint(isViewHidden: false)

        // Put main panel view into a wrapper view that would also contain background view.
        mainPanelWrapperView.addSubview(mainPanelView)
        mainPanelView.autoPinEdgesToSuperviewEdges()

        // "Suggested Stickers" panel is created as needed and will placed in a wrapper view to allow for slide in / slide out animation.
        suggestedStickerWrapper.clipsToBounds = true
        updateSuggestedStickersViewConstraint()

        let outerVStack = UIStackView(arrangedSubviews: [ suggestedStickerWrapper, mainPanelWrapperView ] )
        outerVStack.axis = .vertical
        addSubview(outerVStack)
        outerVStack.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        outerVStack.autoPinEdge(toSuperviewSafeArea: .bottom)

        // When presenting or dismissing the keyboard, there may be a slight
        // gap between the keyboard and the bottom of the input bar during
        // the animation. Extend the background below the toolbar's bounds
        // by this much to mask that extra space.
        let backgroundExtension: CGFloat = 500
        let extendedBackgroundView = UIView()
        if UIAccessibility.isReduceTransparencyEnabled {
            extendedBackgroundView.backgroundColor = Theme.toolbarBackgroundColor
        } else {
            extendedBackgroundView.backgroundColor = Theme.toolbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)

            let blurEffectView = UIVisualEffectView(effect: Theme.barBlurEffect)
            // Alter the visual effect view's tint to match our background color
            // so the input bar, when over a solid color background matching `toolbarBackgroundColor`,
            // exactly matches the background color. This is brittle, but there is no way to get
            // this behavior from UIVisualEffectView otherwise.
            if let tintingView = blurEffectView.subviews.first(where: {
                String(describing: type(of: $0)) == "_UIVisualEffectSubview"
            }) {
                tintingView.backgroundColor = extendedBackgroundView.backgroundColor
            }
            extendedBackgroundView.addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }
        mainPanelWrapperView.insertSubview(extendedBackgroundView, at: 0)
        extendedBackgroundView.autoPinWidthToSuperview()
        extendedBackgroundView.autoPinEdge(toSuperviewEdge: .top)
        extendedBackgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -backgroundExtension)

        // See comments on updateLayout(withSafeAreaInsets:).
        messageContentVStack.insetsLayoutMarginsFromSafeArea = false
        messageContentView.insetsLayoutMarginsFromSafeArea = false
        mainPanelWrapperView.insetsLayoutMarginsFromSafeArea = false
        outerVStack.insetsLayoutMarginsFromSafeArea = false
        insetsLayoutMarginsFromSafeArea = false

        messageContentVStack.preservesSuperviewLayoutMargins = false
        messageContentView.preservesSuperviewLayoutMargins = false
        mainPanelWrapperView.preservesSuperviewLayoutMargins = false
        preservesSuperviewLayoutMargins = false

        setMessageBody(messageDraft, animated: false, doLayout: false)

        isConfigurationComplete = true
    }

    @discardableResult
    class func setView(_ view: UIView, hidden isHidden: Bool, usingAnimator animator: UIViewPropertyAnimator?) -> Bool {
        let viewAlpha: CGFloat = isHidden ? 0 : 1

        guard viewAlpha != view.alpha else { return false }

        let viewUpdateBlock = {
            view.alpha = viewAlpha
            view.transform = isHidden ? .scale(0.1) : .identity
        }
        if let animator {
            animator.addAnimations(viewUpdateBlock)
        } else {
            viewUpdateBlock()
        }
        return true
    }

    private func ensureButtonVisibility(withAnimation isAnimated: Bool, doLayout: Bool) {

        var hasLayoutChanged = false
        var rightEdgeControlsState = rightEdgeControlsView.state

        // Voice Memo UI.
        if isShowingVoiceMemoUI {
            voiceMemoContentView.setIsHidden(false, animated: isAnimated)

            // Send button would be visible if there's voice recording in progress in "locked" state.
            let hideSendButton = voiceMemoRecordingState == .recordingHeld || voiceMemoRecordingState == .idle
            rightEdgeControlsState = hideSendButton ? .hiddenSendButton : .sendButton
        } else {
            voiceMemoContentView.setIsHidden(true, animated: isAnimated)

            // Show Send button instead of Camera and Voice Message buttons only when text input isn't empty.
            let hasNonWhitespaceTextInput = !inputTextView.trimmedText.isEmpty
            rightEdgeControlsState = hasNonWhitespaceTextInput ? .sendButton : .default
        }

        let animator: UIViewPropertyAnimator?
        if isAnimated {
            animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 0.645, springResponse: 0.25)
        } else {
            animator = nil
        }

        // Attachment Button
        let hideAttachmentButton = isShowingVoiceMemoUI
        if setAttachmentButtonHidden(hideAttachmentButton, usingAnimator: animator) {
            hasLayoutChanged = true
        }

        // Attachment button has more complex animations and cannot be grouped with the rest.
        let attachmentButtonAppearance: AttachmentButton.Appearance = desiredKeyboardType == .attachment ? .close : .add
        attachmentButton.setAppearance(attachmentButtonAppearance, usingAnimator: animator)

        // Show / hide Sticker or Keyboard buttons inside of the text input field.
        // Either buttons are only visible if there's no any text input, including whitespace-only.
        let hideStickerOrKeyboardButton = !inputTextView.untrimmedText.isEmpty || isShowingVoiceMemoUI || quotedReply != nil
        let hideStickerButton = hideStickerOrKeyboardButton || desiredKeyboardType == .sticker
        let hideKeyboardButton = hideStickerOrKeyboardButton || !hideStickerButton
        ConversationInputToolbar.setView(stickerButton, hidden: hideStickerButton, usingAnimator: animator)
        ConversationInputToolbar.setView(keyboardButton, hidden: hideKeyboardButton, usingAnimator: animator)

        // Hide text input field if Voice Message UI is presented or make it visible otherwise.
        // Do not change "isHidden" because that'll cause inputTextView to lose focus.
        let inputTextViewAlpha: CGFloat = isShowingVoiceMemoUI ? 0 : 1
        if let animator {
            animator.addAnimations {
                self.inputTextView.alpha = inputTextViewAlpha
            }
        } else {
            inputTextView.alpha = inputTextViewAlpha
        }

        if rightEdgeControlsView.state != rightEdgeControlsState {
            hasLayoutChanged = true

            if let animator {
                // `state` in implicitly animatable.
                animator.addAnimations {
                    self.rightEdgeControlsView.state = rightEdgeControlsState
                }
            } else {
                rightEdgeControlsView.state = rightEdgeControlsState
            }
        }

        if let animator {
            if doLayout && hasLayoutChanged {
                animator.addAnimations {
                    self.mainPanelView.setNeedsLayout()
                    self.mainPanelView.layoutIfNeeded()
                }
            }

            animator.startAnimation()
        } else {
            if doLayout && hasLayoutChanged {
                self.mainPanelView.setNeedsLayout()
                self.mainPanelView.layoutIfNeeded()
            }
        }

        updateSuggestedStickers(animated: isAnimated)
    }

    private var messageContentViewLeftEdgeConstraint: NSLayoutConstraint?

    private func updateMessageContentViewLeftEdgeConstraint(isViewHidden: Bool) {
        if let messageContentViewLeftEdgeConstraint {
            removeConstraint(messageContentViewLeftEdgeConstraint)
        }
        let constraint: NSLayoutConstraint
        if isViewHidden {
            constraint = messageContentView.leftAnchor.constraint(
                equalTo: mainPanelView.layoutMarginsGuide.leftAnchor,
                constant: 16
            )
        } else {
            constraint = messageContentView.leftAnchor.constraint(equalTo: attachmentButton.rightAnchor)
        }
        addConstraint(constraint)
        messageContentViewLeftEdgeConstraint = constraint
    }

    private func setAttachmentButtonHidden(_ isHidden: Bool, usingAnimator animator: UIViewPropertyAnimator?) -> Bool {
        guard ConversationInputToolbar.setView(attachmentButton, hidden: isHidden, usingAnimator: animator) else { return false }
        updateMessageContentViewLeftEdgeConstraint(isViewHidden: isHidden)
        return true
    }

    func updateLayout(withSafeAreaInsets safeAreaInsets: UIEdgeInsets) -> Bool {
        let insetsChanged = receivedSafeAreaInsets != safeAreaInsets
        let needLayoutConstraints = layoutConstraints == nil
        guard insetsChanged || needLayoutConstraints else {
            return false
        }

        // iOS doesn't always update the safeAreaInsets correctly & in a timely
        // way for the inputAccessoryView after a orientation change.  The best
        // workaround appears to be to use the safeAreaInsets from
        // ConversationViewController's view.  ConversationViewController updates
        // this input toolbar using updateLayoutWithIsLandscape:.

        receivedSafeAreaInsets = safeAreaInsets
        return true
    }

    func updateFontSizes() {
        inputTextView.font = .ows_dynamicTypeBody
    }

    // MARK: Right Edge Buttons

    private class RightEdgeControlsView: UIView {

        enum State {
            case `default`
            case sendButton
            case hiddenSendButton
        }
        private var _state: State = .default
        var state: State {
            get { _state }
            set {
                guard _state != newValue else { return }
                _state = newValue
                configureViewsForState(_state)
                invalidateIntrinsicContentSize()
            }
        }

        static let sendButtonHMargin: CGFloat = 4
        static let cameraButtonHMargin: CGFloat = 8

        lazy var sendButton: UIButton = {
            let button = UIButton(type: .system)
            button.accessibilityLabel = MessageStrings.sendButton
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "sendButton")
            button.setImage(UIImage(imageLiteralResourceName: "send-blue-32"), for: .normal)
            button.bounds.size = CGSize(width: 48, height: LayoutMetrics.minToolbarItemHeight)
            return button
        }()

        lazy var cameraButton: UIButton = {
            let button = UIButton(type: .system)
            button.tintColor = Theme.primaryIconColor
            button.accessibilityLabel = NSLocalizedString(
                "CAMERA_BUTTON_LABEL",
                comment: "Accessibility label for camera button."
            )
            button.accessibilityHint = NSLocalizedString(
                "CAMERA_BUTTON_HINT",
                comment: "Accessibility hint describing what you can do with the camera button"
            )
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "cameraButton")
            button.setImage(Theme.iconImage(.cameraButton), for: .normal)
            button.bounds.size = CGSize(width: 40, height: LayoutMetrics.minToolbarItemHeight)
            return button
        }()

        lazy var voiceMemoButton: UIButton = {
            let button = UIButton(type: .system)
            button.tintColor = Theme.primaryIconColor
            button.accessibilityLabel = NSLocalizedString(
                "INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_LABEL",
                comment: "accessibility label for the button which records voice memos"
            )
            button.accessibilityHint = NSLocalizedString(
                "INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_HINT",
                comment: "accessibility hint for the button which records voice memos"
            )
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "voiceMemoButton")
            button.setImage(Theme.iconImage(.micButton), for: .normal)
            button.bounds.size = CGSize(width: 40, height: LayoutMetrics.minToolbarItemHeight)
            return button
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)

            for button in [ cameraButton, voiceMemoButton, sendButton ] {
                button.setContentHuggingHorizontalHigh()
                button.setCompressionResistanceHorizontalHigh()
                addSubview(button)
            }
            configureViewsForState(state)

            setContentHuggingHigh()
            setCompressionResistanceHigh()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            sendButton.center = CGPoint(
                x: bounds.maxX - Self.sendButtonHMargin - 0.5 * sendButton.bounds.width,
                y: bounds.midY
            )

            switch state {
            case .default:
                cameraButton.center = CGPoint(
                    x: bounds.minX + Self.cameraButtonHMargin + 0.5 * cameraButton.bounds.width,
                    y: bounds.midY
                )
                voiceMemoButton.center = sendButton.center

            case .sendButton, .hiddenSendButton:
                cameraButton.center = sendButton.center
                voiceMemoButton.center = sendButton.center
            }
        }

        private func configureViewsForState(_ state: State) {
            switch state {
            case .default:
                cameraButton.transform = .identity
                cameraButton.alpha = 1

                voiceMemoButton.transform = .identity
                voiceMemoButton.alpha = 1

                sendButton.transform = .scale(0.1)
                sendButton.alpha = 0

            case .sendButton, .hiddenSendButton:
                cameraButton.transform = .scale(0.1)
                cameraButton.alpha = 0

                voiceMemoButton.transform = .scale(0.1)
                voiceMemoButton.alpha = 0

                sendButton.transform = .identity
                sendButton.alpha = state == .hiddenSendButton ? 0 : 1
            }
        }

        override var intrinsicContentSize: CGSize {
            let width: CGFloat = {
                switch state {
                case .default: return cameraButton.width + voiceMemoButton.width + 2 * Self.cameraButtonHMargin
                case .sendButton, .hiddenSendButton: return sendButton.width + 2 * Self.sendButtonHMargin
                }
            }()
            return CGSize(width: width, height: LayoutMetrics.minToolbarItemHeight)
        }
    }

    // MARK: Attachment Button

    private class AttachmentButton: UIButton {

        private let roundedCornersBackground: UIView = {
            let view = UIView()
            view.backgroundColor = .init(rgbHex: 0x3B3B3B)
            view.clipsToBounds = true
            view.layer.cornerRadius = 8
            view.isUserInteractionEnabled = false
            return view
        }()

        private let iconImageView = UIImageView(image: UIImage(imageLiteralResourceName: "plus-24"))

        private override init(frame: CGRect) {
            super.init(frame: frame)

            addSubview(roundedCornersBackground)
            roundedCornersBackground.autoCenterInSuperview()
            roundedCornersBackground.autoSetDimensions(to: CGSize(square: 28))
            updateImageColorAndBackground()

            addSubview(iconImageView)
            iconImageView.autoCenterInSuperview()
            updateImageTransform()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var isHighlighted: Bool {
            didSet {
                // When user releases their finger appearance change animations will be fired.
                // We don't want changes performed by this method to interfere with animations.
                guard !isAnimatingAppearance else { return }

                // Mimic behavior of a standard system button.
                let opacity: CGFloat = isHighlighted ? (Theme.isDarkThemeEnabled ? 0.4 : 0.2) : 1
                switch appearance {
                case .add:
                    iconImageView.alpha = opacity

                case .close:
                    roundedCornersBackground.alpha = opacity
                }
            }
        }

        enum Appearance {
            case add
            case close
        }

        private var _appearance: Appearance = .add
        private var isAnimatingAppearance = false

        var appearance: Appearance {
            get { _appearance }
            set { setAppearance(newValue, usingAnimator: nil) }
        }

        func setAppearance(_ appearance: Appearance, usingAnimator animator: UIViewPropertyAnimator?) {
            guard appearance != _appearance else { return }

            _appearance = appearance

            guard let animator else {
                updateImageColorAndBackground()
                updateImageTransform()
                return
            }

            isAnimatingAppearance = true
            animator.addAnimations({
                    self.updateImageColorAndBackground()
                },
                delayFactor: appearance == .add ? 0 : 0.2
            )
            animator.addAnimations {
                self.updateImageTransform()
            }
            animator.addCompletion { _ in
                self.isAnimatingAppearance = false
            }
        }

        private func updateImageColorAndBackground() {
            switch appearance {
            case .add:
                iconImageView.alpha = 1
                iconImageView.tintColor = Theme.primaryIconColor
                roundedCornersBackground.alpha = 0
                roundedCornersBackground.transform = .scale(0.05)

            case .close:
                iconImageView.alpha = 1
                iconImageView.tintColor = .white
                roundedCornersBackground.alpha = 1
                roundedCornersBackground.transform = .identity
            }
        }

        private func updateImageTransform() {
            switch appearance {
            case .add:
                iconImageView.transform = .identity

            case .close:
                iconImageView.transform = .rotate(1.5 * .halfPi)
            }
        }
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
    }

    // MARK: Quoted Reply

    var quotedReply: OWSQuotedReplyModel? {
        didSet {
            guard oldValue != quotedReply else { return }

            layer.removeAllAnimations()

            let animateChanges = window != nil
            if quotedReply != nil {
                showQuotedReplyView(animated: animateChanges)
            } else {
                hideQuotedReplyView(animated: animateChanges)
            }
            // This would show / hide Stickers|Keyboard button.
            ensureButtonVisibility(withAnimation: true, doLayout: false)
            clearDesiredKeyboard()
        }
    }

    private func showQuotedReplyView(animated: Bool) {
        guard let quotedReply else {
            owsFailDebug("quotedReply == nil")
            return
        }

        let quotedMessagePreview = QuotedReplyPreview(quotedReply: quotedReply, conversationStyle: conversationStyle)
        quotedMessagePreview.delegate = self
        quotedMessagePreview.setContentHuggingHorizontalLow()
        quotedMessagePreview.setCompressionResistanceHorizontalLow()
        quotedMessagePreview.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "quotedMessagePreview")
        quotedReplyWrapper.addSubview(quotedMessagePreview)
        quotedMessagePreview.autoPinEdgesToSuperviewEdges()

        updateInputLinkPreview()

        if animated, quotedReplyWrapper.isHidden {
            isAnimatingHeightChange = true

            UIView.animate(
                withDuration: ConversationInputToolbar.heightChangeAnimationDuration,
                animations: {
                    self.quotedReplyWrapper.isHidden = false
                },
                completion: { _ in
                    self.isAnimatingHeightChange = false
                }
            )
        } else {
            quotedReplyWrapper.isHidden = false
        }
    }

    private func hideQuotedReplyView(animated: Bool) {
        owsAssertDebug(quotedReply == nil)

        if animated {
            isAnimatingHeightChange = true

            UIView.animate(
                withDuration: ConversationInputToolbar.heightChangeAnimationDuration,
                animations: {
                    self.quotedReplyWrapper.isHidden = true
                },
                completion: { _ in
                    self.isAnimatingHeightChange = false
                    self.quotedReplyWrapper.removeAllSubviews()
                }
            )
        } else {
            quotedReplyWrapper.isHidden = true
            quotedReplyWrapper.removeAllSubviews()
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

    private let linkPreviewFetcher: LinkPreviewFetcher

    private var linkPreviewView: LinkPreviewView?

    private var isLinkPreviewHidden = true

    private var linkPreviewConstraint: NSLayoutConstraint?

    private func updateLinkPreviewConstraint() {
        guard let linkPreviewView else {
            owsFailDebug("linkPreviewView == nil")
            return
        }
        if let linkPreviewConstraint {
            removeConstraint(linkPreviewConstraint)
        }
        // To hide link preview I constrain both top and bottom edges of the linkPreviewWrapper
        // to top edge of linkPreviewView, effectively making linkPreviewWrapper a zero height view.
        // But since linkPreviewView keeps it size animating this change results in a nice slide in/out animation.
        // To make link preview visible I constrain linkPreviewView to linkPreviewWrapper normally.
        let linkPreviewContstraint: NSLayoutConstraint
        if isLinkPreviewHidden {
            linkPreviewContstraint = linkPreviewWrapper.bottomAnchor.constraint(equalTo: linkPreviewView.topAnchor)
        } else {
            linkPreviewContstraint = linkPreviewWrapper.bottomAnchor.constraint(equalTo: linkPreviewView.bottomAnchor)
        }
        addConstraint(linkPreviewContstraint)
        self.linkPreviewConstraint = linkPreviewContstraint
    }

    var linkPreviewDraft: OWSLinkPreviewDraft? {
        AssertIsOnMainThread()

        return linkPreviewFetcher.linkPreviewDraftIfLoaded
    }

    private func updateInputLinkPreview() {
        AssertIsOnMainThread()

        linkPreviewFetcher.update(messageBody?.text ?? "", enableIfEmpty: true)
    }

    private func updateLinkPreviewView() {
        let animateChanges = window != nil

        switch linkPreviewFetcher.currentState {
        case .none, .failed:
            hideLinkPreviewView(animated: animateChanges)
        case .loading:
            ensureLinkPreviewView(withState: LinkPreviewLoading(linkType: .preview))
        case .loaded(let linkPreviewDraft):
            ensureLinkPreviewView(withState: LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft))
        }
    }

    private func ensureLinkPreviewView(withState state: LinkPreviewState) {
        AssertIsOnMainThread()

        let linkPreviewView: LinkPreviewView
        if let existingLinkPreviewView = self.linkPreviewView {
            linkPreviewView = existingLinkPreviewView
        } else {
            linkPreviewView = LinkPreviewView(draftDelegate: self)
            linkPreviewWrapper.addSubview(linkPreviewView)
            // See comment in `updateLinkPreviewConstraint` why `bottom` isn't constrained.
            linkPreviewView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
            self.linkPreviewView = linkPreviewView

            updateLinkPreviewConstraint()
        }

        linkPreviewView.configureForNonCVC(state: state, isDraft: true, hasAsymmetricalRounding: quotedReply == nil)
        UIView.performWithoutAnimation {
            self.mainPanelView.layoutIfNeeded()
        }

        guard isLinkPreviewHidden else {
            return
        }

        isLinkPreviewHidden = false

        let animateChanges = window != nil
        guard animateChanges else {
            updateLinkPreviewConstraint()
            layoutIfNeeded()
            return
        }

        isAnimatingHeightChange = true
        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.updateLinkPreviewConstraint()
            self.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            self.isAnimatingHeightChange = false
        }
        animator.startAnimation()
    }

    private func hideLinkPreviewView(animated: Bool) {
        AssertIsOnMainThread()

        guard !isLinkPreviewHidden else { return }

        isLinkPreviewHidden = true

        guard animated else {
            updateLinkPreviewConstraint()
            layoutIfNeeded()
            return
        }

        isAnimatingHeightChange = true
        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.updateLinkPreviewConstraint()
            self.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            self.isAnimatingHeightChange = false
        }
        animator.startAnimation()
    }

    // MARK: LinkPreviewViewDraftDelegate

    public func linkPreviewDidCancel() {
        AssertIsOnMainThread()

        linkPreviewFetcher.disable()
    }

    // MARK: Stickers

    private let suggestedStickerViewCache = StickerViewCache(maxSize: 12)

    private var suggestedStickerInfos: [StickerInfo] = []

    private var suggestedStickersViewConstraint: NSLayoutConstraint?

    private func updateSuggestedStickersViewConstraint() {
        if let suggestedStickersViewConstraint {
            removeConstraint(suggestedStickersViewConstraint)
        }

        // suggestedStickerView is created lazily and isn't accessed until it is needed.
        // Set wrapper's height to zero if it is not needed yet.
        guard suggestedStickerWrapper.subviews.count > 0 else {
            let zeroHeightConstraint = suggestedStickerWrapper.heightAnchor.constraint(equalToConstant: 0)
            addConstraint(zeroHeightConstraint)
            suggestedStickersViewConstraint = zeroHeightConstraint
            return
        }

        // To hide suggested stickers panel I constrain both top and bottom edges of the `suggestedStickerView`
        // to the top edge of its wrapper view, effectively making that wrapper view a zero height view.
        // `suggestedStickerView` has a fixed height so animating this change results in a nice slide in/out animation.
        // `suggestedStickerView` is made visible by constraining all of its edges to wrapper view normally.
        let constraint: NSLayoutConstraint
        if isSuggestedStickersViewHidden {
            constraint = suggestedStickerWrapper.bottomAnchor.constraint(equalTo: suggestedStickerView.topAnchor)
        } else {
            constraint = suggestedStickerWrapper.bottomAnchor.constraint(equalTo: suggestedStickerView.bottomAnchor)
        }
        addConstraint(constraint)
        suggestedStickersViewConstraint = constraint
    }

    private var isSuggestedStickersViewHidden = true

    private func updateSuggestedStickers(animated: Bool) {
        let suggestedStickerInfos = StickerManager.shared.suggestedStickers(forTextInput: inputTextView.trimmedText).map { $0.info }

        guard suggestedStickerInfos != self.suggestedStickerInfos else { return }

        self.suggestedStickerInfos = suggestedStickerInfos

        guard !suggestedStickerInfos.isEmpty else {
            hideSuggestedStickersView(animated: animated)
            return
        }

        showSuggestedStickersView(animated: animated)
    }

    private func showSuggestedStickersView(animated: Bool) {
        owsAssertDebug(!suggestedStickerInfos.isEmpty)

        if suggestedStickerView.superview == nil {
            suggestedStickerWrapper.addSubview(suggestedStickerView)
            suggestedStickerView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
            UIView.performWithoutAnimation {
                suggestedStickerWrapper.layoutIfNeeded()
            }
        }

        suggestedStickerView.items = suggestedStickerInfos.map { stickerInfo in
            StickerHorizontalListViewItemSticker(
                stickerInfo: stickerInfo,
                didSelectBlock: { [weak self] in
                    self?.didSelectSuggestedSticker(stickerInfo)
                },
                cache: suggestedStickerViewCache
            )
        }

        guard isSuggestedStickersViewHidden else { return }

        isSuggestedStickersViewHidden = false

        UIView.performWithoutAnimation {
            self.suggestedStickerView.layoutIfNeeded()
            self.suggestedStickerView.contentOffset = CGPoint(
                x: -self.suggestedStickerView.contentInset.left,
                y: -self.suggestedStickerView.contentInset.top
            )
        }

        guard animated else {
            updateSuggestedStickersViewConstraint()
            return
        }

        isAnimatingHeightChange = true
        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.updateSuggestedStickersViewConstraint()
            self.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            self.isAnimatingHeightChange = false
        }
        animator.startAnimation()
    }

    private func hideSuggestedStickersView(animated: Bool) {
        guard !isSuggestedStickersViewHidden else { return }

        isSuggestedStickersViewHidden = true

        guard animated else {
            updateSuggestedStickersViewConstraint()
            return
        }

        isAnimatingHeightChange = true
        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.updateSuggestedStickersViewConstraint()
            self.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            self.isAnimatingHeightChange = false
        }
        animator.startAnimation()
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
            tailReferenceView: rightEdgeControlsView.voiceMemoButton) { [weak self] in
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

    @objc
    private func keyboardButtonPressed() {
        Logger.verbose("")

        ImpactHapticFeedback.impactOccured(style: .light)

        toggleKeyboardType(.system, animated: true)
    }
}

extension ConversationInputToolbar: ConversationTextViewToolbarDelegate {

    private func updateHeightWithTextView(_ textView: UITextView) {

        let contentSize = textView.sizeThatFits(CGSize(width: textView.width, height: CGFloat.greatestFiniteMagnitude))

        // `textView.contentSize` isn't accurate when restoring a multiline draft, so we compute it here.
        textView.contentSize = contentSize

        let newHeight = CGFloatClamp(
            contentSize.height,
            LayoutMetrics.minTextViewHeight,
            UIDevice.current.isIPad ? LayoutMetrics.maxIPadTextViewHeight : LayoutMetrics.maxTextViewHeight
        )

        guard newHeight != textViewHeight else { return }

        guard let textViewHeightConstraint else {
            owsFailDebug("textViewHeightConstraint == nil")
            return
        }

        textViewHeight = newHeight
        textViewHeightConstraint.constant = newHeight

        if let superview, inputToolbarDelegate != nil {
            isAnimatingHeightChange = true

            let animator = UIViewPropertyAnimator(
                duration: ConversationInputToolbar.heightChangeAnimationDuration,
                springDamping: 1,
                springResponse: 0.25
            )
            animator.addAnimations {
                self.invalidateIntrinsicContentSize()
                superview.layoutIfNeeded()
            }
            animator.addCompletion { _ in
                self.isAnimatingHeightChange = false
            }
            animator.startAnimation()
        } else {
            invalidateIntrinsicContentSize()
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        owsAssertDebug(inputToolbarDelegate != nil)

        // Ignore change events during configuration.
        guard isConfigurationComplete else { return }

        updateHeightWithTextView(textView)
        ensureButtonVisibility(withAnimation: true, doLayout: true)
        updateInputLinkPreview()
    }

    func textViewDidChangeSelection(_ textView: UITextView) { }

    func textViewDidBecomeFirstResponder(_ textView: UITextView) {
        setDesiredKeyboardType(.system, animated: true)
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
