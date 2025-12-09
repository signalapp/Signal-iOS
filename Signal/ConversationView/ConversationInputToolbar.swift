//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
public import SignalServiceKit
public import SignalUI

protocol ConversationInputToolbarDelegate: AnyObject {

    func sendButtonPressed()

    func sendSticker(_ sticker: StickerInfo)

    func presentManageStickersView()

    func updateToolbarHeight()

    func isBlockedConversation() -> Bool

    func isGroup() -> Bool

    // Older iOS versions (<16.0) only have proper `keyboardLayoutGuide` on UIVC's root view,
    // but might as well request root view for all iOS versions.
    func viewForKeyboardLayoutGuide() -> UIView

    /// Return a view where `ConversationInputToolbar` should place suggested stickers panel.
    /// This view must contain `ConversationInputToolbar` otherwise the behavior is undefined (we'll crash).
    func viewForSuggestedStickersPanel() -> UIView

    // MARK: Voice Memo

    func voiceMemoGestureDidStart()

    func voiceMemoGestureDidLock()

    func voiceMemoGestureDidComplete()

    func voiceMemoGestureDidCancel()

    func voiceMemoGestureWasInterrupted()

    func sendVoiceMemoDraft(_ draft: VoiceMessageInterruptedDraft)

    // MARK: Attachments

    func cameraButtonPressed()

    func photosButtonPressed()

    func gifButtonPressed()

    func fileButtonPressed()

    func contactButtonPressed()

    func locationButtonPressed()

    func paymentButtonPressed()

    func pollButtonPressed()

    func didSelectRecentPhoto(asset: PHAsset, attachment: PreviewableAttachment)

    func showUnblockConversationUI(completion: ((Bool) -> Void)?)
}

public class ConversationInputToolbar: UIView, QuotedReplyPreviewDelegate {

    private var conversationStyle: ConversationStyle

    private let spoilerState: SpoilerRenderState

    private let mediaCache: CVMediaCache

    private weak var inputToolbarDelegate: ConversationInputToolbarDelegate?

    init(
        conversationStyle: ConversationStyle,
        spoilerState: SpoilerRenderState,
        mediaCache: CVMediaCache,
        messageDraft: MessageBody?,
        quotedReplyDraft: DraftQuotedReplyModel?,
        editTarget: TSOutgoingMessage?,
        inputToolbarDelegate: ConversationInputToolbarDelegate,
        inputTextViewDelegate: ConversationInputTextViewDelegate,
        bodyRangesTextViewDelegate: BodyRangesTextViewDelegate
    ) {
        self.conversationStyle = conversationStyle
        self.spoilerState = spoilerState
        self.mediaCache = mediaCache
        self.editTarget = editTarget
        self.inputToolbarDelegate = inputToolbarDelegate
        self.linkPreviewFetchState = LinkPreviewFetchState(
            db: DependenciesBridge.shared.db,
            linkPreviewFetcher: SUIEnvironment.shared.linkPreviewFetcher,
            linkPreviewSettingStore: DependenciesBridge.shared.linkPreviewSettingStore
        )

        super.init(frame: .zero)

        self.linkPreviewFetchState.onStateChange = { [weak self] in self?.updateLinkPreviewView() }

        setupContentView()

        createContentsWithMessageDraft(
            messageDraft,
            quotedReplyDraft: quotedReplyDraft,
            inputTextViewDelegate: inputTextViewDelegate,
            bodyRangesTextViewDelegate: bodyRangesTextViewDelegate
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(notification:)),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )

        if #available(iOS 17, *) {
            inputTextView.registerForTraitChanges(
                [ UITraitPreferredContentSizeCategory.self ]
            ) { [weak self] (textView: UITextView, _) in
                self?.updateTextViewFontSize()
            }
        } else {
            contentSizeChangeNotificationObserver = NotificationCenter.default.addObserver(
                name: UIContentSizeCategory.didChangeNotification
            ) { [weak self] _ in
                self?.updateTextViewFontSize()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let contentSizeChangeNotificationObserver {
            NotificationCenter.default.removeObserver(contentSizeChangeNotificationObserver)
        }
    }

    // MARK: Layout Configuration.

    public override var frame: CGRect {
        didSet {
            guard oldValue.size.height != frame.size.height else { return }

            inputToolbarDelegate?.updateToolbarHeight()
        }
    }

    public override var bounds: CGRect {
        didSet {
            guard abs(oldValue.size.height - bounds.size.height) > 1 else { return }

            inputToolbarDelegate?.updateToolbarHeight()
        }
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)

        // Suggested sticker panel is placed outside of ConversationInputToolbar
        // and need to be removed manually.
        if newSuperview == nil, !isStickerPanelHidden {
            stickerPanel.removeFromSuperview()
        }
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()

        guard superview != nil else { return }

        // Show suggested stickers for the draft as soon as we are placed in the view hierarchy.
        updateSuggestedStickers(animated: false)

        // Probably because of a regression in iOS 26 `keyboardLayoutGuide`,
        // if first accessed in `calculateCustomKeyboardHeight`, would have an
        // incorrect height of 34 dp (amount of bottom safe area).
        // Accessing the layout guide before somehow fixes that issue.
        if #available(iOS 26, *) {
            _ = keyboardLayoutGuide
        }
    }

    func update(conversationStyle: ConversationStyle) {
        self.conversationStyle = conversationStyle
        if #available(iOS 26, *), let sendButton = trailingEdgeControl as? UIButton {
            sendButton.tintColor = conversationStyle.chatColorValue.asSendButtonTintColor()
        }
    }

    private enum LayoutMetrics {
        static let initialToolbarHeight: CGFloat = 56
        static let initialTextBoxHeight: CGFloat = 40

        static let minTextViewHeight: CGFloat = 35
        static let maxTextViewHeight: CGFloat = 98
        static let maxTextViewHeightIpad: CGFloat = 142
    }

    public enum Style {
        @available(iOS 26, *)
        static var glassTintColor: UIColor {
            // This set of colors is copied to elsewhere.
            // Please update all places if you change color values.
            UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor(white: 0, alpha: 0.2)
                }
                return UIColor(white: 1, alpha: 0.12)
            }
        }

        @available(iOS 26, *)
        static func glassEffect(isInteractive: Bool = false) -> UIGlassEffect {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = glassTintColor
            glassEffect.isInteractive = isInteractive
            return glassEffect
        }

        static var primaryTextColor: UIColor {
            .Signal.label
        }

        static var secondaryTextColor: UIColor {
            .Signal.secondaryLabel
        }

        static var buttonTintColor: UIColor {
            if #available(iOS 26, *) {
                return .Signal.label
            }
            return UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                ? Theme.darkThemeLegacyPrimaryIconColor
                : Theme.lightThemeLegacyPrimaryIconColor
            }
        }
    }

    private var iOS26Layout = false

    private enum Buttons {
        private static func compactButton(
            buttonImage: UIImage,
            primaryAction: UIAction?,
            accessibilityLabel: String?,
            accessibilityIdentifier: String?
        ) -> UIButton {
            let button = UIButton(
                configuration: .plain(),
                primaryAction: primaryAction
            )
            button.configuration?.image = buttonImage
            button.configuration?.baseForegroundColor = Style.buttonTintColor
            button.accessibilityLabel = accessibilityLabel
            button.accessibilityIdentifier = accessibilityIdentifier
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addConstraints([
                button.widthAnchor.constraint(equalToConstant: LayoutMetrics.initialTextBoxHeight),
                button.heightAnchor.constraint(equalToConstant: LayoutMetrics.initialTextBoxHeight),
            ])
            return button
        }

        static func stickerButton(
            primaryAction: UIAction,
            accessibilityIdentifier: String?
        ) -> UIButton {
            return compactButton(
                buttonImage: UIImage(imageLiteralResourceName: "sticker"),
                primaryAction: primaryAction,
                accessibilityLabel: OWSLocalizedString(
                    "INPUT_TOOLBAR_STICKER_BUTTON_ACCESSIBILITY_LABEL",
                    comment: "accessibility label for the button which shows the sticker picker"
                ),
                accessibilityIdentifier: accessibilityIdentifier
            )
        }

        static func keyboardButton(
            primaryAction: UIAction,
            accessibilityIdentifier: String?
        ) -> UIButton {
            return compactButton(
                buttonImage: UIImage(imageLiteralResourceName: "keyboard"),
                primaryAction: primaryAction,
                accessibilityLabel: OWSLocalizedString(
                    "INPUT_TOOLBAR_KEYBOARD_BUTTON_ACCESSIBILITY_LABEL",
                    comment: "accessibility label for the button which shows the regular keyboard instead of sticker picker"
                ),
                accessibilityIdentifier: accessibilityIdentifier
            )
        }

        static func cameraButton(
            primaryAction: UIAction?,
            accessibilityIdentifier: String?
        ) -> UIButton {
            let button = compactButton(
                buttonImage: Theme.iconImage(.buttonCamera),
                primaryAction: primaryAction,
                accessibilityLabel: OWSLocalizedString(
                    "CAMERA_BUTTON_LABEL",
                    comment: "Accessibility label for camera button."
                ),
                accessibilityIdentifier: accessibilityIdentifier
            )
            button.accessibilityHint = OWSLocalizedString(
                "CAMERA_BUTTON_HINT",
                comment: "Accessibility hint describing what you can do with the camera button"
            )
            return button
        }

        static func voiceNoteButton(
            primaryAction: UIAction?,
            accessibilityIdentifier: String?
        ) -> UIButton {
            let button = compactButton(
                buttonImage: Theme.iconImage(.buttonMicrophone),
                primaryAction: primaryAction,
                accessibilityLabel: OWSLocalizedString(
                    "INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_LABEL",
                    comment: "accessibility label for the button which records voice memos"
                ),
                accessibilityIdentifier: accessibilityIdentifier
            )
            button.accessibilityHint = OWSLocalizedString(
                "INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_HINT",
                comment: "accessibility hint for the button which records voice memos"
            )
            return button
        }

        @available(iOS 26.0, *)
        static func sendButton(
            primaryAction: UIAction?,
            accessibilityIdentifier: String?
        ) -> UIButton {

            let buttonSize = LayoutMetrics.initialTextBoxHeight

            let button = UIButton(
                configuration: .prominentGlass(),
                primaryAction: primaryAction
            )
            // Button's tint color is set externalley (from `conversationStyle`).
            button.configuration?.image = Theme.iconImage(.arrowUp)
            button.configuration?.baseForegroundColor = .white
            button.configuration?.cornerStyle = .capsule
            button.accessibilityLabel = MessageStrings.sendButton
            button.accessibilityIdentifier = accessibilityIdentifier
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addConstraints([
                button.widthAnchor.constraint(equalToConstant: buttonSize),
                button.heightAnchor.constraint(equalToConstant: buttonSize),
            ])
            return button
        }

        @available(iOS 26.0, *)
        static func addAttachmentButton(
            primaryAction: UIAction?,
            accessibilityIdentifier: String?
        ) -> UIButton {

            let buttonSize = LayoutMetrics.initialTextBoxHeight

            let button = AttachmentButton(
                configuration: .glass(),
                primaryAction: primaryAction
            )
            button.tintColor = Style.glassTintColor
            button.configuration?.image = UIImage(imageLiteralResourceName: "plus")
            button.configuration?.baseForegroundColor = Style.buttonTintColor
            button.configuration?.cornerStyle = .capsule
            button.accessibilityLabel = OWSLocalizedString(
                "ATTACHMENT_LABEL",
                comment: "Accessibility label for attaching photos"
            )
            button.accessibilityHint = OWSLocalizedString(
                "ATTACHMENT_HINT",
                comment: "Accessibility hint describing what you can do with the attachment button"
            )
            button.accessibilityIdentifier = accessibilityIdentifier
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addConstraints([
                button.widthAnchor.constraint(equalToConstant: buttonSize),
                button.heightAnchor.constraint(equalToConstant: buttonSize),
            ])
            return button
        }

        @available(iOS 26.0, *)
        static func deleteVoiceMemoDraftButton(
            primaryAction: UIAction?,
            accessibilityIdentifier: String?
        ) -> UIButton {

            let buttonSize = LayoutMetrics.initialTextBoxHeight

            let button = UIButton(
                configuration: .prominentGlass(),
                primaryAction: primaryAction
            )
            button.tintColor = .Signal.red
            button.configuration?.image = UIImage(imageLiteralResourceName: "trash-fill")
            button.configuration?.baseForegroundColor = .white
            button.configuration?.cornerStyle = .capsule
            button.accessibilityIdentifier = accessibilityIdentifier
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addConstraints([
                button.widthAnchor.constraint(equalToConstant: buttonSize),
                button.heightAnchor.constraint(equalToConstant: buttonSize),
            ])
            return button
        }
    }

    private lazy var inputTextView: ConversationInputTextView = {
        let inputTextView = ConversationInputTextView()
        inputTextView.textViewToolbarDelegate = self
        inputTextView.font = .dynamicTypeBody
        inputTextView.textColor = Style.primaryTextColor
        inputTextView.placeholderTextColor = Style.secondaryTextColor
        inputTextView.semanticContentAttribute = .forceLeftToRight
        inputTextView.setContentHuggingVerticalHigh()
        inputTextView.setCompressionResistanceLow()
        inputTextView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "inputTextView")
        return inputTextView
    }()

    private lazy var leadingEdgeControl: UIView = {
#if compiler(>=6.2)
        guard #unavailable(iOS 26.0) else {
            return Buttons.addAttachmentButton(
                primaryAction: UIAction { [weak self] _ in
                    self?.addOrCancelButtonPressed()
                },
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "attachmentButton")
            )
        }
#endif

        let button = AttachmentButtonLegacy()
        button.accessibilityLabel = OWSLocalizedString(
            "ATTACHMENT_LABEL",
            comment: "Accessibility label for attaching photos"
        )
        button.accessibilityHint = OWSLocalizedString(
            "ATTACHMENT_HINT",
            comment: "Accessibility hint describing what you can do with the attachment button"
        )
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "attachmentButton")
        button.addTarget(self, action: #selector(addOrCancelButtonPressed), for: .touchUpInside)
        return button
    }()

    private lazy var stickerButton = Buttons.stickerButton(
        primaryAction: UIAction { [weak self] _ in
            self?.stickerButtonPressed()
        },
        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "stickerButton")
    )

    private lazy var keyboardButton = Buttons.keyboardButton(
        primaryAction: UIAction { [weak self] _ in
            self?.keyboardButtonPressed()
        },
        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "keyboardButton")
    )

    private lazy var cameraButton = Buttons.cameraButton(
        primaryAction: UIAction { [weak self] _ in
            self?.cameraButtonPressed()
        },
        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "cameraButton")
    )

    private lazy var voiceNoteButton: UIButton = {
        let button = Buttons.voiceNoteButton(
            primaryAction: nil,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "voiceNoteButton")
        )
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleVoiceMemoLongPress(gesture:)))
        longPressGestureRecognizer.minimumPressDuration = 0
        button.addGestureRecognizer(longPressGestureRecognizer)
        return button
    }()

    private lazy var trailingEdgeControl: UIView = {
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            let button = Buttons.sendButton(
                primaryAction: UIAction { [weak self] _ in
                    self?.sendButtonPressed()
                },
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "sendButton")
            )
            button.tintColor = conversationStyle.bubbleChatColorOutgoing.asSendButtonTintColor()
            return button
        }
#endif

        let view = RightEdgeControlsView(
            sendButtonAction: UIAction { [weak self] _ in
                self?.sendButtonPressed()
            },
            cameraButtonAction: UIAction { [weak self] _ in
                self?.cameraButtonPressed()
            }
        )

        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleVoiceMemoLongPress(gesture:)))
        longPressGestureRecognizer.minimumPressDuration = 0
        view.voiceMemoButton.addGestureRecognizer(longPressGestureRecognizer)
        return view
    }()

    private lazy var linkPreviewWrapper: UIView = {
        let view = UIView.container()
        view.clipsToBounds = true
        view.directionalLayoutMargins = .init(top: 6, leading: 6, bottom: 0, trailing: 6)
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "linkPreviewWrapper")
        return view
    }()

    private lazy var voiceMemoContentView: UIView = {
        let view = UIView.container()
        view.isHidden = true
        view.semanticContentAttribute = .forceLeftToRight
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "voiceMemoContentView")
        return view
    }()

    private var glassContainerView: UIView?
    private var legacyBackgroundView: UIView?
    private var legacyBackgroundBlurView: UIVisualEffectView?

    /// Whole-width container that contains (+) button, text input part and Send button.
    private let contentView = UIView()

    /// Occupies central part of the `contentView`. That's where text input field, link preview etc live in.
    private let messageContentView = UIView()

    @available(iOS 26, *)
    func setScrollEdgeElementContainerInteraction(_ interaction: UIInteraction) {
        owsAssertBeta(glassContainerView != nil)
        glassContainerView?.addInteraction(interaction)
    }

    private var isConfigurationComplete = false

    private func setupContentView() {
        // The input toolbar should *always* be laid out left-to-right, even when using
        // a right-to-left language. The convention for messaging apps is for the send
        // button to always be to the right of the input field, even in RTL layouts.
        // This means you'll need to set the appropriate `semanticContentAttribute`
        // to ensure horizontal stack views layout left-to-right.
        semanticContentAttribute = .forceLeftToRight
        contentView.semanticContentAttribute = .forceLeftToRight

        let contentViewSuperview: UIView
        if #available(iOS 26, *) {
            iOS26Layout = true

            // Glass Container.
            let glassContainerView = UIVisualEffectView(effect: UIGlassContainerEffect())
            addSubview(glassContainerView)
            glassContainerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                glassContainerView.topAnchor.constraint(equalTo: topAnchor),
                glassContainerView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
                glassContainerView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
                glassContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            contentViewSuperview = glassContainerView.contentView
            self.glassContainerView = glassContainerView
        } else {
            // Background needed on pre-iOS 26 devices.
            // The background is stretched to all edges to cover any safe area gaps.
           let backgroundView = UIView()
            if UIAccessibility.isReduceTransparencyEnabled {
                backgroundView.backgroundColor = .Signal.background
            } else {
                let blurEffectView = UIVisualEffectView(effect: nil) // will be updated later
                backgroundView.addSubview(blurEffectView)
                blurEffectView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    blurEffectView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
                    blurEffectView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
                    blurEffectView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
                    blurEffectView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
                ])

                // Set background color and visual effect.
                updateBackgroundColors(backgroundView: backgroundView, backgroundBlurView: blurEffectView)

                // Remember these views so that we can update colors on traitCollection changes.
                self.legacyBackgroundView = backgroundView
                self.legacyBackgroundBlurView = blurEffectView
            }
            addSubview(backgroundView)
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                backgroundView.topAnchor.constraint(equalTo: topAnchor),
                backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                // extend background view down to cover any potentian gaps between input toolbar and keyboard.
                backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 200),
            ])

            contentViewSuperview = self
        }

        // Set up content view.
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            hMargin: OWSTableViewController2.defaultHOuterMargin - 16,
            vMargin: iOS26Layout ? 0.5 * (LayoutMetrics.initialToolbarHeight - LayoutMetrics.initialTextBoxHeight) : 0
        )
        contentViewSuperview.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func createContentsWithMessageDraft(
        _ messageDraft: MessageBody?,
        quotedReplyDraft: DraftQuotedReplyModel?,
        inputTextViewDelegate: ConversationInputTextViewDelegate,
        bodyRangesTextViewDelegate: BodyRangesTextViewDelegate
    ) {

        // 1. Set initial parameters.
        // NOTE: Don't set inputTextViewDelegate until configuration is complete.
        inputTextView.bodyRangesDelegate = bodyRangesTextViewDelegate
        inputTextView.inputTextViewDelegate = inputTextViewDelegate

        // Initial state for "Editing Message" label
        if isEditingMessage {
            loadEditMessageViewIfNecessary()
            editMessageViewVisibleConstraint.isActive = true
        }

        // Initial state for the quoted message snippet.
        quotedReplyViewConstraints = [
            quotedReplyWrapper.heightAnchor.constraint(equalToConstant: 0)
        ]
        NSLayoutConstraint.activate(quotedReplyViewConstraints)
        self.quotedReplyDraft = quotedReplyDraft

        // 2. Prepare content displayed in the central part of the toolbar.

        // This container allows to vertically center short text views in standard sized box.
        let inputTextViewContainer = UIView.container()
        inputTextViewContainer.semanticContentAttribute = .forceLeftToRight
        inputTextViewContainer.addSubview(inputTextView)
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        textViewHeightConstraint = inputTextView.heightAnchor.constraint(equalToConstant: LayoutMetrics.minTextViewHeight)
        inputTextViewContainer.addConstraints([
            // This defines height of `inputTextView` which is always set to content size. calculated in `updateHeightWithTextView()`
            textViewHeightConstraint,
            // This sets minimum height on visual text view box. This height can exceed height of an empty inputTextView.
            // We don't want `inputTextView` to grow above it's content size because that causes
            // incorrect (top) alignment of text when there's just a single line of it.
            inputTextViewContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: LayoutMetrics.initialTextBoxHeight),
            // This lets `inputTextViewContainer` grow with `inputTextView` when height of the latter increases with text.
            // Working in conjuction with the next constraint they center `inputTextView` vertically
            // when it's height is below minimum height of `inputTextViewContainer`.
            inputTextView.topAnchor.constraint(greaterThanOrEqualTo: inputTextViewContainer.topAnchor),
            inputTextView.centerYAnchor.constraint(equalTo: inputTextViewContainer.centerYAnchor),
            // This constraint doesn't allow `inputTextViewContainer` to grow uncontrollably in height
            // when mentions picker is placed above, being constrained between VC's root view's top edge
            // and ConversationInputToolbar's top edge.
            // Priority is set to not conflict with the constraints above, but still be higher
            // than vertical hugging priority of the mentions picker.
            {
                let c = inputTextView.topAnchor.constraint(equalTo: inputTextViewContainer.topAnchor)
                c.priority = .defaultHigh
                return c
            }(),
            inputTextView.leadingAnchor.constraint(equalTo: inputTextViewContainer.leadingAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: inputTextViewContainer.trailingAnchor),
        ])

        // Vertical stack of message component views in the center
        // | edit message |
        // | Link Preview |
        // | Reply Quote  |
        // | Text Input   |
        let messageComponentsView = UIStackView(arrangedSubviews: [
            editMessageLabelWrapper,
            quotedReplyWrapper,
            linkPreviewWrapper,
            inputTextViewContainer,
        ])
        messageComponentsView.axis = .vertical
        messageComponentsView.alignment = .fill

        // Voice Message UI is added to the same vertical stack, but not as arranged subview.
        // The view is constrained to text input view's edges.
        messageComponentsView.addSubview(voiceMemoContentView)
        voiceMemoContentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            voiceMemoContentView.topAnchor.constraint(equalTo: inputTextViewContainer.topAnchor),
            voiceMemoContentView.leadingAnchor.constraint(equalTo: inputTextViewContainer.leadingAnchor),
            voiceMemoContentView.trailingAnchor.constraint(equalTo: inputTextViewContainer.trailingAnchor),
            voiceMemoContentView.bottomAnchor.constraint(equalTo: inputTextViewContainer.bottomAnchor),
        ])

        // Rounded rect background for the text input field:
        // Liquid Glass on iOS 26, gray-ish on earlier iOS versions.
        let backgroundView: UIView
        if #available(iOS 26, *) {
            let glassEffectView = UIVisualEffectView(effect: Style.glassEffect(isInteractive: true))
            glassEffectView.cornerConfiguration = .uniformCorners(radius: 20)
            glassEffectView.contentView.addSubview(messageComponentsView)
            backgroundView = glassEffectView

            messageContentView.addSubview(backgroundView)
        } else {
            backgroundView = UIView()
            backgroundView.backgroundColor = UIColor.Signal.tertiaryFill
            backgroundView.layer.cornerRadius = 20

            messageContentView.addSubview(backgroundView)
            messageContentView.addSubview(messageComponentsView)
        }

        let vMargin = 0.5 * (LayoutMetrics.initialToolbarHeight - LayoutMetrics.initialTextBoxHeight)
        let hMargin: CGFloat = iOS26Layout ? 12 : 0 // iOS 26 needs space between leading/trailing buttons and text view background.
        messageContentView.directionalLayoutMargins = .init(hMargin: hMargin, vMargin: vMargin)
        messageContentView.semanticContentAttribute = .forceLeftToRight
        backgroundView.semanticContentAttribute = .forceLeftToRight

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        messageComponentsView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Background view is inset from the edges of the central part of the `contentView` - `messageContentView`
            backgroundView.topAnchor.constraint(equalTo: messageContentView.layoutMarginsGuide.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: messageContentView.layoutMarginsGuide.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: messageContentView.layoutMarginsGuide.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: messageContentView.layoutMarginsGuide.bottomAnchor),

            // Message components stack is constrained to background view's edges.
            messageComponentsView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            messageComponentsView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            messageComponentsView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            messageComponentsView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
        ])

        // iOS 26 has three in-field buttons: Sticker/Keyboard, Camera, Voice Note.
        // iOS 15-18 only have Sticker/Keyboard.
        if iOS26Layout {
            inputTextView.inFieldButtonsAreaWidth = 3 * LayoutMetrics.initialTextBoxHeight

            inputTextViewContainer.addSubview(stickerButton)
            inputTextViewContainer.addSubview(keyboardButton)
            inputTextViewContainer.addSubview(cameraButton)
            inputTextViewContainer.addSubview(voiceNoteButton)

            stickerButton.translatesAutoresizingMaskIntoConstraints = false
            keyboardButton.translatesAutoresizingMaskIntoConstraints = false
            cameraButton.translatesAutoresizingMaskIntoConstraints = false
            voiceNoteButton.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                voiceNoteButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -4),
                cameraButton.trailingAnchor.constraint(equalTo: voiceNoteButton.leadingAnchor),
                stickerButton.trailingAnchor.constraint(equalTo: cameraButton.leadingAnchor),
                keyboardButton.trailingAnchor.constraint(equalTo: cameraButton.leadingAnchor),

                voiceNoteButton.bottomAnchor.constraint(equalTo: inputTextViewContainer.bottomAnchor),
                cameraButton.bottomAnchor.constraint(equalTo: inputTextViewContainer.bottomAnchor),
                stickerButton.bottomAnchor.constraint(equalTo: inputTextViewContainer.bottomAnchor),
                keyboardButton.bottomAnchor.constraint(equalTo: inputTextViewContainer.bottomAnchor),
            ])
        } else {
            inputTextView.inFieldButtonsAreaWidth = 1 * LayoutMetrics.initialTextBoxHeight

            inputTextViewContainer.addSubview(stickerButton)
            inputTextViewContainer.addSubview(keyboardButton)

            stickerButton.translatesAutoresizingMaskIntoConstraints = false
            keyboardButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stickerButton.centerYAnchor.constraint(equalTo: inputTextViewContainer.centerYAnchor),
                keyboardButton.centerYAnchor.constraint(equalTo: inputTextViewContainer.centerYAnchor),

                stickerButton.trailingAnchor.constraint(equalTo: messageContentView.trailingAnchor, constant: -4),
                keyboardButton.trailingAnchor.constraint(equalTo: messageContentView.trailingAnchor, constant: -4),
            ])
        }

        // 3. Configure horizontal layout: Attachment button, message components, Camera|VoiceNote|Send button.
        leadingEdgeControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(leadingEdgeControl)

        messageContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(messageContentView)

        trailingEdgeControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(trailingEdgeControl)

        let outerHMargin: CGFloat = iOS26Layout ? 16 : 0
        NSLayoutConstraint.activate([
            // + Attachment button: pinned to the bottom left corner.
            leadingEdgeControl.leadingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.leadingAnchor,
                constant: outerHMargin
            ),
            leadingEdgeControl.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            // Message components view: pinned to attachment button on the left, Camera button on the right,
            // taking entire superview's height.
            messageContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            messageContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Camera | Voice Message | Send: pinned to the bottom right corner.
            trailingEdgeControl.trailingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.trailingAnchor,
                constant: -outerHMargin
            ),
            trailingEdgeControl.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])

        updateMessageContentViewLeadingEdgeConstraint(isLeadingEdgeControlHidden: false)
        if iOS26Layout {
            setSendButtonHidden(true, usingAnimator: nil)
        } else {
            messageContentView.trailingAnchor.constraint(equalTo: trailingEdgeControl.leadingAnchor).isActive = true
        }

        // 4. Finish.
        setMessageBody(messageDraft, animated: false, doLayout: false)

        isConfigurationComplete = true
    }

    // MARK: Layout Updates.

    @discardableResult
    class func setView(_ view: UIView, hidden isHidden: Bool, usingAnimator animator: UIViewPropertyAnimator?) -> Bool {
        // Nothing to do if the view isn't a part of the view hierarchy.
        if isHidden, view.superview == nil { return false }

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

        let animator: UIViewPropertyAnimator?
        if isAnimated {
            animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 0.645, springResponse: 0.25)
        } else {
            animator = nil
        }

        //
        // 1. Show / hide Voice Memo UI.
        //
        voiceMemoContentView.setIsHidden(isShowingVoiceMemoUI == false, animated: isAnimated)

        //
        // 2. Update leading edge control.
        //

        // Possible states of the leading edge control:
        // * (+) attachment button: when there is no voice note UI visible.
        // * Delete Voice Note button: when there's a voice note draft.
        // * No control: when there's voice note recording in progress.
        let leadingEdgeControlState: LeadingEdgeControlState =  {
            if isShowingVoiceMemoUI {
                return voiceMemoRecordingState == .draft ? .deleteVoiceMemoDraft : .none
            }
            return .addAttachment
        }()
        if setLeadingEdgeControlState(leadingEdgeControlState, usingAnimator: animator) {
            hasLayoutChanged = true
        }

        // (+) attachment button can be displayed in its alternative appearance - as (X) button in two cases:
        // * attachment keyboard is displayed.
        // * user is editing a message.
        if let attachmentButton = leadingEdgeControl as? AttachmentButtonProtocol {
            let buttonState: AttachmentButtonState = {
                if isEditingMessage {
                    return .close
                } else {
                    return desiredKeyboardType == .attachment ? .close : .add
                }
            }()
            attachmentButton.setButtonState(buttonState, usingAnimator: animator)
        }

        //
        // 3. Determine state of the trailing edge controls.
        //

        let rightEdgeControlsState: TrailingEdgeControlState
        // Voice recording is in progress in "locked" state: show Send button in active state.
        // In all other voice note recording states there are no trailing edge controls.
        if isShowingVoiceMemoUI {
            let showSendButton: Bool = {
                switch voiceMemoRecordingState {
                case .recordingLocked, .draft:
                    true
                default:
                    false
                }
            }()
            rightEdgeControlsState = showSendButton ? .sendButton : .hiddenSendButton
        }
        // Text field has non-whitespace input: show Send button in active state.
        // Note: Activating "edit message" feature would temporarily disable Send button
        //       even if there is non-whitespace text. Editing text would re-enable Send button.
        else if hasMessageText {
            rightEdgeControlsState = .sendButton
        }
        // If there's a quoted message or we're editing a message: show inactive Send button.
        else if isEditingMessage {
            rightEdgeControlsState = .disabledSendButton
        }
        // No input, not editing message, no quoted message: do not show Send button.
        // On iOS 26 there would be no right edge controls.
        // On iOS 15-18 there would be Camera and Mic buttons.
        else {
            rightEdgeControlsState = .default
        }

        //
        // 4. Update middle part: text input field and buttons inside.
        //

        // Only ever show in-field buttons when there's no Send button visible on the right or when
        // text input contains newlines (that increases text box's height).
        // On iOS 26 there are Camera and Voice Note buttons inside of the text input field:
        // those would be hidden to match pre-iOS 26 behavior.
        let hideAllTextFieldButtons = rightEdgeControlsState != .default || inputTextView.untrimmedText.rangeOfCharacter(from: .newlines) != nil
        // Sticker/keyboard buttons will also be hidden if there's whitespace-only input.
        let textFieldHasAnyInput = !inputTextView.untrimmedText.isEmpty
        let hideInputMethodButtons = hideAllTextFieldButtons || textFieldHasAnyInput || hasQuotedMessage
        let hideStickerButton = hideInputMethodButtons || desiredKeyboardType == .sticker
        let hideKeyboardButton = hideInputMethodButtons || !hideStickerButton
        ConversationInputToolbar.setView(stickerButton, hidden: hideStickerButton, usingAnimator: animator)
        ConversationInputToolbar.setView(keyboardButton, hidden: hideKeyboardButton, usingAnimator: animator)
        if iOS26Layout {
            ConversationInputToolbar.setView(cameraButton, hidden: hideAllTextFieldButtons, usingAnimator: animator)
            ConversationInputToolbar.setView(voiceNoteButton, hidden: hideAllTextFieldButtons, usingAnimator: animator)
        }

        // Text input is hidden whenever Voice Message UI is presented.
        // Change view's opacity instead of `isHidden` because the latter will cause inputTextView to lose focus.
        let inputTextViewAlpha: CGFloat = isShowingVoiceMemoUI ? 0 : 1
        if let animator {
            animator.addAnimations {
                self.inputTextView.alpha = inputTextViewAlpha
            }
        } else {
            inputTextView.alpha = inputTextViewAlpha
        }

        //
        // 5. Apply changes to trailing edge controls.
        //

        // iOS 15-18: update trailing edge controls view.
        if let rightEdgeControlsView = trailingEdgeControl as? RightEdgeControlsView,
           rightEdgeControlsView.state != rightEdgeControlsState {
            hasLayoutChanged = true

            if let animator {
                // `state` in implicitly animatable.
                animator.addAnimations {
                    rightEdgeControlsView.state = rightEdgeControlsState
                }
            } else {
                rightEdgeControlsView.state = rightEdgeControlsState
            }
        }

        // iOS 26: Update Send button state.
        if iOS26Layout, let sendButton = trailingEdgeControl as? UIButton {
            let hideSendButton: Bool
            var disableSendButton = false
            switch rightEdgeControlsState {
            case .default:
                hideSendButton = true
            case .sendButton:
                hideSendButton = false
            case .disabledSendButton:
                hideSendButton = false
                disableSendButton = true
            case .hiddenSendButton:
                hideSendButton = true
            }

            let sendButtonVisibilityChanges = setSendButtonHidden(hideSendButton, usingAnimator: animator)
            if sendButtonVisibilityChanges {
                hasLayoutChanged = true
            }

            // Enable/disable Send button, taking potential visibility changes into accoount.
            if hideSendButton, sendButtonVisibilityChanges {
                // If Send button becomes hidden do not update `isEnabled` until animation completes.
                if let animator {
                    animator.addCompletion { _ in
                        sendButton.isEnabled = !disableSendButton
                    }
                } else {
                    sendButton.isEnabled = !disableSendButton
                }
            } else {
                // If Send button becomes visible or becomes enabled/disabled while being visible
                // we need to apply changes to `isEnabled` right away.
                sendButton.isEnabled = !disableSendButton
            }
        }

        //
        // 6. Commit animations.
        //

        if let animator {
            if doLayout && hasLayoutChanged {
                animator.addAnimations {
                    self.contentView.setNeedsLayout()
                    self.contentView.layoutIfNeeded()
                }
            }

            animator.startAnimation()
        } else {
            if doLayout && hasLayoutChanged {
                self.contentView.setNeedsLayout()
                self.contentView.layoutIfNeeded()
            }
        }

        updateSuggestedStickers(animated: isAnimated)
    }

    private var messageContentViewLeadingEdgeConstraint: NSLayoutConstraint?
    private func updateMessageContentViewLeadingEdgeConstraint(isLeadingEdgeControlHidden: Bool) {
        if let messageContentViewLeadingEdgeConstraint {
            removeConstraint(messageContentViewLeadingEdgeConstraint)
        }
        let constraint: NSLayoutConstraint
        if isLeadingEdgeControlHidden {
            constraint = messageContentView.leadingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.leadingAnchor,
                constant: iOS26Layout ? 4 : 16
            )
        } else {
            constraint = messageContentView.leadingAnchor.constraint(equalTo: leadingEdgeControl.trailingAnchor)
        }
        addConstraint(constraint)
        messageContentViewLeadingEdgeConstraint = constraint
    }

    private var messageContentViewTrailingEdgeConstraint: NSLayoutConstraint?
    private func updateMessageContentViewTrailingEdgeConstraint(isTrailingEdgeControlHidden: Bool) {
        guard iOS26Layout else { return }

        if let messageContentViewTrailingEdgeConstraint {
            removeConstraint(messageContentViewTrailingEdgeConstraint)
        }
        let constraint: NSLayoutConstraint
        if isTrailingEdgeControlHidden {
            constraint = messageContentView.trailingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.trailingAnchor,
                constant: -4
            )
        } else {
            constraint = messageContentView.trailingAnchor.constraint(equalTo: trailingEdgeControl.leadingAnchor)
        }
        addConstraint(constraint)
        messageContentViewTrailingEdgeConstraint = constraint
    }

    private enum LeadingEdgeControlState {
        /// No control.
        case none

        /// (+) button.
        case addAttachment

        /// Red 🗑️ delete Voice Note button.
        case deleteVoiceMemoDraft
    }

    private enum TrailingEdgeControlState {
        /// No control on iOS 26+. Camera and Mic on iOS 15-18.
        case `default`

        /// Active Send button.
        case sendButton

        /// Inactive Send button.
        case disabledSendButton

        /// Send button not visible, but the space for is is reserved.
        case hiddenSendButton
    }

    @discardableResult
    private func setLeadingEdgeControlState(
        _ controlState: LeadingEdgeControlState,
        usingAnimator animator: UIViewPropertyAnimator?
    ) -> Bool {
        var voiceMemoButtonUpdated = false
        if controlState == .deleteVoiceMemoDraft, voiceMemoDeleteButton.superview == nil {
            contentView.addSubview(voiceMemoDeleteButton)
            voiceMemoDeleteButton.translatesAutoresizingMaskIntoConstraints = false
            contentView.addConstraints([
                voiceMemoDeleteButton.topAnchor.constraint(equalTo: leadingEdgeControl.topAnchor),
                voiceMemoDeleteButton.leadingAnchor.constraint(equalTo: leadingEdgeControl.leadingAnchor),
                voiceMemoDeleteButton.trailingAnchor.constraint(equalTo: leadingEdgeControl.trailingAnchor),
                voiceMemoDeleteButton.bottomAnchor.constraint(equalTo: leadingEdgeControl.bottomAnchor),
            ])

            voiceMemoButtonUpdated = true
        } else if controlState != .deleteVoiceMemoDraft, voiceMemoDeleteButton.superview != nil {
            voiceMemoDeleteButton.removeFromSuperview()

            voiceMemoButtonUpdated = true
        }
        let attachmentButtonUpdated = ConversationInputToolbar.setView(leadingEdgeControl, hidden: controlState != .addAttachment, usingAnimator: animator)

        guard attachmentButtonUpdated || voiceMemoButtonUpdated else {
            return false
        }

        updateMessageContentViewLeadingEdgeConstraint(isLeadingEdgeControlHidden: controlState == .none)

        return true
    }

    @discardableResult
    private func setSendButtonHidden(_ isHidden: Bool, usingAnimator animator: UIViewPropertyAnimator?) -> Bool {
        // Only on iOS 26 trailing edge control (Send button) can get hidden.
        guard let sendButton = trailingEdgeControl as? UIButton else { return false }
        guard ConversationInputToolbar.setView(sendButton, hidden: isHidden, usingAnimator: animator) else { return false }
        updateMessageContentViewTrailingEdgeConstraint(isTrailingEdgeControlHidden: isHidden)
        return true
    }

    func scrollToBottom() {
        inputTextView.scrollToBottom()
    }

    // Dynamic color and visual effect support for background view(s) on iOS 15-18.
    @available(iOS, deprecated: 26)
    private func updateBackgroundColors(backgroundView: UIView, backgroundBlurView: UIVisualEffectView) {
        let backgroundColor = UIColor.Signal.background
            .resolvedColor(with: traitCollection)
            .withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)

        backgroundView.backgroundColor = backgroundColor

        // Match Theme.barBlurEffect.
        backgroundBlurView.effect =
        traitCollection.userInterfaceStyle == .dark
        ? UIBlurEffect(style: .dark)
        : UIBlurEffect(style: .light)

        // Alter the visual effect view's tint to match our background color
        // so the input bar, when over a solid color background matching `toolbarBackgroundColor`,
        // exactly matches the background color. This is brittle, but there is no way to get
        // this behavior from UIVisualEffectView otherwise.
        if let tintingView = backgroundBlurView.subviews.first(where: {
            String(describing: type(of: $0)) == "_UIVisualEffectSubview"
        }) {
            tintingView.backgroundColor = backgroundColor
        }
    }

    // MARK: Right Edge Buttons

    @available(iOS, deprecated: 26.0)
    private class RightEdgeControlsView: UIView {

        typealias State = TrailingEdgeControlState

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
            button.ows_adjustsImageWhenDisabled = true
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "sendButton")
            button.setImage(UIImage(imageLiteralResourceName: "send-blue-28"), for: .normal)
            button.bounds.size = CGSize(width: 48, height: LayoutMetrics.initialToolbarHeight)
            return button
        }()

        lazy var cameraButton: UIButton = {
            let button = UIButton(type: .system)
            button.tintColor = Style.buttonTintColor
            button.accessibilityLabel = OWSLocalizedString(
                "CAMERA_BUTTON_LABEL",
                comment: "Accessibility label for camera button."
            )
            button.accessibilityHint = OWSLocalizedString(
                "CAMERA_BUTTON_HINT",
                comment: "Accessibility hint describing what you can do with the camera button"
            )
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "cameraButton")
            button.setImage(Theme.iconImage(.buttonCamera), for: .normal)
            button.bounds.size = CGSize(width: 40, height: LayoutMetrics.initialToolbarHeight)
            return button
        }()

        lazy var voiceMemoButton: UIButton = {
            let button = UIButton(type: .system)
            button.tintColor = Style.buttonTintColor
            button.accessibilityLabel = OWSLocalizedString(
                "INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_LABEL",
                comment: "accessibility label for the button which records voice memos"
            )
            button.accessibilityHint = OWSLocalizedString(
                "INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_HINT",
                comment: "accessibility hint for the button which records voice memos"
            )
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "voiceMemoButton")
            button.setImage(Theme.iconImage(.buttonMicrophone), for: .normal)
            button.bounds.size = CGSize(width: 40, height: LayoutMetrics.initialToolbarHeight)
            return button
        }()

        init(
            sendButtonAction: UIAction,
            cameraButtonAction: UIAction
        ) {
            super.init(frame: .zero)

            sendButton.addAction(sendButtonAction, for: .primaryActionTriggered)
            cameraButton.addAction(cameraButtonAction, for: .primaryActionTriggered)

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

            case .sendButton, .disabledSendButton, .hiddenSendButton:
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

            case .sendButton, .disabledSendButton, .hiddenSendButton:
                cameraButton.transform = .scale(0.1)
                cameraButton.alpha = 0

                voiceMemoButton.transform = .scale(0.1)
                voiceMemoButton.alpha = 0

                sendButton.transform = .identity
                sendButton.alpha = state == .hiddenSendButton ? 0 : 1
                sendButton.isEnabled = state == .sendButton
            }
        }

        override var intrinsicContentSize: CGSize {
            let width: CGFloat = {
                switch state {
                case .default: return cameraButton.width + voiceMemoButton.width + 2 * Self.cameraButtonHMargin
                case .sendButton, .disabledSendButton, .hiddenSendButton: return sendButton.width + 2 * Self.sendButtonHMargin
                }
            }()
            return CGSize(width: width, height: LayoutMetrics.initialToolbarHeight)
        }
    }

    // MARK: Add/Cancel Button

    private enum AttachmentButtonState {
        case add
        case close
    }

    private protocol AttachmentButtonProtocol where Self: UIButton {
        var buttonState: AttachmentButtonState { get set }
        func setButtonState(_ buttonState: AttachmentButtonState, usingAnimator animator: UIViewPropertyAnimator?)
    }

    @available(iOS, deprecated: 26.0)
    private class AttachmentButtonLegacy: UIButton, AttachmentButtonProtocol {

        private let roundedCornersBackground: UIView = {
            let view = UIView()
            view.backgroundColor = .init(rgbHex: 0x3B3B3B)
            view.clipsToBounds = true
            view.layer.cornerRadius = 14
            view.isUserInteractionEnabled = false
            return view
        }()

        private let iconImageView = UIImageView(image: UIImage(imageLiteralResourceName: "plus"))

        private override init(frame: CGRect) {
            super.init(frame: frame)

            addSubview(roundedCornersBackground)
            roundedCornersBackground.autoCenterInSuperview()
            roundedCornersBackground.autoSetDimensions(to: CGSize(square: 28))
            updateImageColorAndBackground()

            addSubview(iconImageView)
            iconImageView.autoCenterInSuperview()
            updateImageTransform()

            // Button is larger but the same visually to allow easier taps.
            translatesAutoresizingMaskIntoConstraints = false
            addConstraints([
                widthAnchor.constraint(equalToConstant: LayoutMetrics.initialToolbarHeight),
                heightAnchor.constraint(equalToConstant: LayoutMetrics.initialToolbarHeight),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var isHighlighted: Bool {
            didSet {
                // When user releases their finger appearance change animations will be fired.
                // We don't want changes performed by this method to interfere with animations.
                guard !isAnimatingStateChange else { return }

                // Mimic behavior of a standard system button.
                let opacity: CGFloat = isHighlighted ? (Theme.isDarkThemeEnabled ? 0.4 : 0.2) : 1
                switch buttonState {
                case .add:
                    iconImageView.alpha = opacity

                case .close:
                    roundedCornersBackground.alpha = opacity
                }
            }
        }

        private var _buttonState: AttachmentButtonState = .add
        private var isAnimatingStateChange = false

        var buttonState: AttachmentButtonState {
            get { _buttonState }
            set { setButtonState(newValue, usingAnimator: nil) }
        }

        func setButtonState(_ buttonState: AttachmentButtonState, usingAnimator animator: UIViewPropertyAnimator?) {
            guard buttonState != _buttonState else { return }

            _buttonState = buttonState

            guard let animator else {
                updateImageColorAndBackground()
                updateImageTransform()
                return
            }

            isAnimatingStateChange = true
            animator.addAnimations({
                    self.updateImageColorAndBackground()
                },
                delayFactor: buttonState == .add ? 0 : 0.2
            )
            animator.addAnimations {
                self.updateImageTransform()
            }
            animator.addCompletion { _ in
                self.isAnimatingStateChange = false
            }
        }

        private func updateImageColorAndBackground() {
            switch buttonState {
            case .add:
                iconImageView.alpha = 1
                iconImageView.tintColor = Style.buttonTintColor
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
            switch buttonState {
            case .add:
                iconImageView.transform = .identity

            case .close:
                iconImageView.transform = .rotate(1.5 * .halfPi)
            }
        }
    }

    @available(iOS 26.0, *)
    private class AttachmentButton: UIButton, AttachmentButtonProtocol {

        private var _buttonState: AttachmentButtonState = .add

        var buttonState: AttachmentButtonState {
            get { _buttonState }
            set { setButtonState(newValue, usingAnimator: nil) }
        }

        func setButtonState(_ buttonState: AttachmentButtonState, usingAnimator animator: UIViewPropertyAnimator?) {
            guard buttonState != _buttonState else { return }

            _buttonState = buttonState

            guard let animator else {
                updateTransform()
                return
            }

            animator.addAnimations {
                self.updateTransform()
            }
        }

        private func updateTransform() {
            switch buttonState {
            case .add:
                transform = .identity

            case .close:
                transform = .rotate(1.5 * .halfPi)
            }
        }
    }

    // MARK: Message Body

    private var hasMessageText: Bool { inputTextView.trimmedText.isEmpty == false }

    private var textViewHeight: CGFloat = 0

    private var textViewHeightConstraint: NSLayoutConstraint!

    class var heightChangeAnimationDuration: TimeInterval { 0.25 }

    var hasUnsavedDraft: Bool {
        let currentDraft = messageBodyForSending ?? .empty

        if let editTarget {
            let editTargetMessage = MessageBody(
                text: editTarget.body ?? "",
                ranges: editTarget.bodyRanges ?? .empty
            )

            return currentDraft != editTargetMessage
        }

        return !currentDraft.isEmpty
    }

    var messageBodyForSending: MessageBody? { inputTextView.messageBodyForSending }

    func setMessageBody(_ messageBody: MessageBody?, animated: Bool, doLayout: Bool = true) {
        inputTextView.setMessageBody(messageBody, txProvider: DependenciesBridge.shared.db.readTxProvider)

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
        editTarget = nil
        setMessageBody(nil, animated: animated)
        inputTextView.undoManager?.removeAllActions()
    }

    // MARK: Content Size Change Handling

    // Unused on iOS 17 and later.
    private var contentSizeChangeNotificationObserver: NotificationCenter.Observer?

    private func updateTextViewFontSize() {
        inputTextView.font = .dynamicTypeBody
        updateHeightWithTextView(inputTextView)
    }

    // MARK: Edit Message

    var isEditingMessage: Bool { editTarget != nil }

    var editTarget: TSOutgoingMessage? {
        didSet {
            let animateChanges = window != nil

            // Show the 'editing' tag
            if let editTarget = editTarget {

                // Fetch the original text (including any oversized text attachments)
                let componentState = SSKEnvironment.shared.databaseStorageRef.read { tx in
                    CVLoader.buildStandaloneComponentState(
                        interaction: editTarget,
                        spoilerState: SpoilerRenderState(),
                        transaction: tx)
                }

                let messageBody: MessageBody
                let ranges = editTarget.bodyRanges ?? .empty
                switch componentState?.bodyText?.displayableText?.fullTextValue {
                case .attributedText(let string):
                    messageBody = MessageBody(text: string.string, ranges: ranges)
                case .messageBody(let body):
                    messageBody = body.asMessageBodyForForwarding(preservingAllMentions: true)
                case .text(let text):
                    messageBody = MessageBody(text: text, ranges: ranges)
                case .none:
                    messageBody = MessageBody(text: "", ranges: .empty)
                }
                self.setMessageBody(messageBody, animated: true)
                showEditMessageView(animated: animateChanges)
            } else if oldValue != nil {
                editThumbnail = nil
                self.setMessageBody(nil, animated: true)
                hideEditMessageView(animated: animateChanges)
            }
        }
    }

    var editThumbnail: UIImage? {
        get { editMessageThumbnailView.image }
        set { editMessageThumbnailView.image = newValue }
    }

    private lazy var editMessageThumbnailView: UIImageView = {
        let imageView = UIImageView()
        imageView.layer.cornerRadius = 4
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var editMessageLabelView: UIView = {
        let editIconView = UIImageView(image: Theme.iconImage(.compose16))
        editIconView.contentMode = .scaleAspectFit
        editIconView.setContentHuggingHigh()
        editIconView.tintColor = Style.buttonTintColor

        let editLabel = UILabel()
        editLabel.text = OWSLocalizedString(
            "INPUT_TOOLBAR_EDIT_MESSAGE_LABEL",
            comment: "Label at the top of the input text when editing a message"
        )
        editLabel.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        editLabel.textColor = Style.primaryTextColor

        // Font produced via `.semibold()` is no longer dynamic
        // and UILabel has to be updated when content size changes.
        if #available(iOS 17, *) {
            editLabel.registerForTraitChanges(
                [ UITraitPreferredContentSizeCategory.self ],
                handler: { (label: UILabel, _) in
                    label.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
                }
            )
        }

        let stackView = UIStackView(arrangedSubviews: [editIconView, editLabel, editMessageThumbnailView])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let view = UIView()
        view.directionalLayoutMargins = .init(top: 12, leading: 12, bottom: 4, trailing: 8)
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            // per design specs, align using textLabel, not stackView
            editLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),

            editMessageThumbnailView.widthAnchor.constraint(equalToConstant: 20),
            editMessageThumbnailView.heightAnchor.constraint(equalToConstant: 20),
        ])

        return view
    }()

    private lazy var editMessageLabelWrapper: UIView = {
        let view = UIView.container()
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "editMessageWrapper")
        return view
    }()

    private lazy var editMessageViewVisibleConstraint = editMessageLabelView.bottomAnchor.constraint(
        equalTo: editMessageLabelWrapper.bottomAnchor
    )

    private lazy var editMessageViewHiddenConstraint = editMessageLabelView.bottomAnchor.constraint(
        equalTo: editMessageLabelWrapper.topAnchor
    )

    private func loadEditMessageViewIfNecessary() {
        guard editMessageLabelView.superview == nil else { return }

        editMessageLabelView.translatesAutoresizingMaskIntoConstraints = false
        editMessageLabelWrapper.addSubview(editMessageLabelView)
        NSLayoutConstraint.activate([
            editMessageLabelView.topAnchor.constraint(equalTo: editMessageLabelWrapper.topAnchor),
            editMessageLabelView.leadingAnchor.constraint(equalTo: editMessageLabelWrapper.leadingAnchor),
            editMessageLabelView.trailingAnchor.constraint(equalTo: editMessageLabelWrapper.trailingAnchor),
        ])
    }

    private func showEditMessageView(animated isAnimated: Bool) {
        loadEditMessageViewIfNecessary()

        guard isAnimated else {
            editMessageLabelView.alpha = 1
            editMessageViewHiddenConstraint.isActive = false
            editMessageViewVisibleConstraint.isActive = true
            return
        }

        UIView.performWithoutAnimation {
            editMessageLabelView.alpha = 0
        }

        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.editMessageLabelView.alpha = 1
            self.editMessageViewHiddenConstraint.isActive = false
            self.editMessageViewVisibleConstraint.isActive = true
            // We simply disable Send button until something (like user editing text) enables it back.
            // Whether or not message text actually changes isn't tracked.
            self.setSendButtonEnabled(false)
            self.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    private func hideEditMessageView(animated isAnimated: Bool) {
        owsAssertDebug(editTarget == nil)

        guard isAnimated else {
            editMessageViewVisibleConstraint.isActive = false
            editMessageViewHiddenConstraint.isActive = true
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.editMessageLabelView.alpha = 0
            self.editMessageViewVisibleConstraint.isActive = false
            self.editMessageViewHiddenConstraint.isActive = true
            self.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    private func setSendButtonEnabled(_ enabled: Bool) {
        if let rightEdgeControlsView = trailingEdgeControl as? RightEdgeControlsView {
            rightEdgeControlsView.sendButton.isEnabled = enabled
        } else if let sendButton = trailingEdgeControl as? UIButton {
            sendButton.isEnabled = enabled
        }
    }

    // MARK: Quoted Reply

    private var hasQuotedMessage: Bool { quotedReplyDraft != nil }

    var quotedReplyDraft: DraftQuotedReplyModel? {
        didSet {
            guard oldValue != quotedReplyDraft else { return }

            layer.removeAllAnimations()

            let animateChanges = window != nil
            if hasQuotedMessage {
                showQuotedReplyView(animated: animateChanges)
            } else {
                hideQuotedReplyView(animated: animateChanges)
            }
            // This would show / hide Stickers|Keyboard button.
            ensureButtonVisibility(withAnimation: animateChanges, doLayout: true)
            clearDesiredKeyboard()
        }
    }

    var draftReply: ThreadReplyInfo? {
        guard let quotedReplyDraft else { return nil }
        guard
            let originalMessageTimestamp = quotedReplyDraft.originalMessageTimestamp,
            let aci = quotedReplyDraft.originalMessageAuthorAddress.aci
        else {
            return nil
        }
        return ThreadReplyInfo(timestamp: originalMessageTimestamp, author: aci)
    }

    private lazy var quotedReplyWrapper: UIView = {
        let view = UIView.container()
        view.clipsToBounds = true
        view.directionalLayoutMargins = .init(top: 6, leading: 6, bottom: 0, trailing: 6)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "quotedReplyWrapper")
        return view
    }()

    private var quotedReplyViewConstraints = [NSLayoutConstraint]()

    private func showQuotedReplyView(animated isAnimated: Bool) {
        guard let quotedReplyDraft else {
            owsFailDebug("quotedReply == nil")
            return
        }

        let oldMessagePreviewView = quotedReplyWrapper.subviews.first as? QuotedReplyPreview
        let oldConstraints = quotedReplyViewConstraints

        // New quoted message snippet.
        let quotedMessagePreview = QuotedReplyPreview(
            quotedReplyDraft: quotedReplyDraft,
            spoilerState: spoilerState
        )
        quotedMessagePreview.delegate = self
        quotedMessagePreview.setContentHuggingHorizontalLow()
        quotedMessagePreview.setCompressionResistanceHorizontalLow()
        quotedMessagePreview.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "quotedMessagePreview")
        quotedReplyWrapper.addSubview(quotedMessagePreview)
        quotedMessagePreview.translatesAutoresizingMaskIntoConstraints = false

        // Resize message snippet to its final size.
        // Don't constrain the bottom though - do so in the animation block.
        // Bottom constrain will cause `quotedReplyWrapper` to grow vertically.
        NSLayoutConstraint.activate([
            quotedMessagePreview.topAnchor.constraint(equalTo: quotedReplyWrapper.layoutMarginsGuide.topAnchor),
            quotedMessagePreview.leadingAnchor.constraint(equalTo: quotedReplyWrapper.layoutMarginsGuide.leadingAnchor),
            quotedMessagePreview.trailingAnchor.constraint(equalTo: quotedReplyWrapper.layoutMarginsGuide.trailingAnchor),
        ])
        UIView.performWithoutAnimation {
            quotedReplyWrapper.setNeedsLayout()
            quotedReplyWrapper.layoutIfNeeded()
        }

        // New constraints.
        let newConstraints = [
            quotedMessagePreview.bottomAnchor.constraint(equalTo: quotedReplyWrapper.layoutMarginsGuide.bottomAnchor),
        ]

        defer {
            quotedReplyViewConstraints = newConstraints
        }

        guard isAnimated else {
            oldMessagePreviewView?.removeFromSuperview()
            NSLayoutConstraint.deactivate(oldConstraints)
            NSLayoutConstraint.activate(newConstraints)
            return
        }

        UIView.performWithoutAnimation {
            quotedMessagePreview.alpha = 0
        }

        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            oldMessagePreviewView?.alpha = 0
            quotedMessagePreview.alpha = 1
            NSLayoutConstraint.deactivate(oldConstraints)
            NSLayoutConstraint.activate(newConstraints)
            self.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            oldMessagePreviewView?.removeFromSuperview()
        }
        animator.startAnimation()
    }

    private func hideQuotedReplyView(animated isAnimated: Bool) {
        owsAssertDebug(quotedReplyDraft == nil)

        let oldMessagePreviewView = quotedReplyWrapper.subviews.first as? QuotedReplyPreview
        let oldConstraints = quotedReplyViewConstraints

        let newConstraints = [
            quotedReplyWrapper.heightAnchor.constraint(equalToConstant: 0)
        ]

        defer {
            quotedReplyViewConstraints = newConstraints
        }

        guard isAnimated else {
            oldMessagePreviewView?.removeFromSuperview()
            NSLayoutConstraint.deactivate(oldConstraints)
            NSLayoutConstraint.activate(newConstraints)
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            oldMessagePreviewView?.alpha = 0
            NSLayoutConstraint.deactivate(oldConstraints)
            NSLayoutConstraint.activate(newConstraints)
            self.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            oldMessagePreviewView?.removeFromSuperview()
        }
        animator.startAnimation()
    }

    func quotedReplyPreviewDidPressCancel(_ preview: QuotedReplyPreview) {
        quotedReplyDraft = nil
    }

    // MARK: Link Preview

    private let linkPreviewFetchState: LinkPreviewFetchState

    private var linkPreviewView: OutgoingLinkPreviewView?

    private var isLinkPreviewHidden = true

    private var linkPreviewConstraints = [NSLayoutConstraint]()

    private func updateLinkPreviewConstraint() {
        guard let linkPreviewView else {
            owsFailDebug("linkPreviewView == nil")
            return
        }
        removeConstraints(linkPreviewConstraints)

        // To hide link preview I constrain both top and bottom edges of the linkPreviewWrapper
        // to top edge of linkPreviewView, effectively making linkPreviewWrapper a zero height view.
        // But since linkPreviewView keeps it size animating this change results in a nice slide in/out animation.
        // To make link preview visible I constrain linkPreviewView to linkPreviewWrapper normally.
        if isLinkPreviewHidden {
            linkPreviewConstraints = [
                linkPreviewView.topAnchor.constraint(equalTo: linkPreviewWrapper.topAnchor),
                linkPreviewView.topAnchor.constraint(equalTo: linkPreviewWrapper.bottomAnchor),
            ]
        } else {
            linkPreviewConstraints = [
                linkPreviewView.topAnchor.constraint(equalTo: linkPreviewWrapper.layoutMarginsGuide.topAnchor),
                linkPreviewView.bottomAnchor.constraint(equalTo: linkPreviewWrapper.layoutMarginsGuide.bottomAnchor),
            ]
        }
        addConstraints(linkPreviewConstraints)
    }

    var linkPreviewDraft: OWSLinkPreviewDraft? {
        AssertIsOnMainThread()

        return linkPreviewFetchState.linkPreviewDraftIfLoaded
    }

    private func updateInputLinkPreview() {
        AssertIsOnMainThread()

        let messageBody = messageBodyForSending
            ?? .init(text: "", ranges: .empty)
        linkPreviewFetchState.update(messageBody, enableIfEmpty: true)
    }

    private func updateLinkPreviewView() {
        let animateChanges = window != nil

        switch linkPreviewFetchState.currentState {
        case .none, .failed:
            hideLinkPreviewView(animated: animateChanges)
        default:
            ensureLinkPreviewView(withState: linkPreviewFetchState.currentState)
        }
    }

    private func ensureLinkPreviewView(withState state: LinkPreviewFetchState.State) {
        AssertIsOnMainThread()

        let linkPreviewView: OutgoingLinkPreviewView
        if let existingLinkPreviewView = self.linkPreviewView {
            linkPreviewView = existingLinkPreviewView
            linkPreviewView.configure(withState: state)
        } else {
            linkPreviewView = OutgoingLinkPreviewView(state: state)
            linkPreviewView.cancelButton.addAction(
                UIAction { [weak self] _ in
                    self?.didTapDeleteLinkPreview()
                },
                for: .primaryActionTriggered
            )
            linkPreviewWrapper.addSubview(linkPreviewView)
            // See comment in `updateLinkPreviewConstraint` why vertical constraints aren't here.
            linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                linkPreviewView.leadingAnchor.constraint(equalTo: linkPreviewWrapper.layoutMarginsGuide.leadingAnchor),
                linkPreviewView.trailingAnchor.constraint(equalTo: linkPreviewWrapper.layoutMarginsGuide.trailingAnchor),
            ])
            self.linkPreviewView = linkPreviewView

            updateLinkPreviewConstraint()
        }

        UIView.performWithoutAnimation {
            self.contentView.layoutIfNeeded()
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

        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.updateLinkPreviewConstraint()
            self.layoutIfNeeded()
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
            self.linkPreviewView?.resetContent()
        }
        animator.startAnimation()
    }

    private func didTapDeleteLinkPreview() {
        AssertIsOnMainThread()

        linkPreviewFetchState.disable()
    }

    // MARK: Stickers

    private let suggestedStickerViewCache = StickerViewCache(maxSize: 12)

    private var currentSuggestedStickerEmoji: Character?

    private var currentSuggestedStickers: [StickerInfo] = []

    private var isStickerPanelHidden = true

    private enum StickerLayout {
        // Square.
        static let listItemSize: CGFloat = 56

        // Horizontal.
        static let listItemSpacing: CGFloat = 12

        // Spacing around sticker list view's content.
        // Set spacing as `UICollectionView.contentInset` to allow scrolling stickers right up to the edge of the background.
        static let listViewPadding = UIEdgeInsets(hMargin: 10, vMargin: 6)

        // `stickersListView` must be inset a little bit to make room for glass background's border.
        static let backgroundMargins = NSDirectionalEdgeInsets(margin: 2)

        // How much is the sticker panel (visible background) inset from the full-width `stickerPanel`.
        static let outerPanelHMargin: CGFloat = if #available(iOS 26, *) { OWSTableViewController2.cellHInnerMargin } else { 0 }

        // Corner radius of the glass/blur background.
        @available(iOS 26, *)
        static let backgroundCornerRadius: CGFloat = 26

        // Make sure to match parameters from MentionPicker.
        static func animationTransform(_ view: UIView) -> CGAffineTransform {
            guard #available(iOS 26, *) else { return .identity }
            return .scale(0.9)
        }

        // Make sure to match parameters from MentionPicker.
        static func animator() -> UIViewPropertyAnimator {
            return UIViewPropertyAnimator(
                duration: 0.35,
                springDamping: 1,
                springResponse: 0.35
            )
        }

        static let panelVisualEffect: UIVisualEffect = {
            // UIVisualEffect cannot "dematerialize" glass on iOS 26.0: setting `effect` to `nil` simply doesn't work.
            // That was fixed in 26.1.
            if #available(iOS 26.1, *) { Style.glassEffect() } else { UIBlurEffect(style: .systemMaterial) }
        }()
    }

    /// Outermost sticker view placed as a subview of the delegate provided view and takes full width of that.
    private let stickerPanel = UIView.container()

    private var stickerPanelConstraint: NSLayoutConstraint?

    /// Subview of `stickerPanel`. Contains background panel and sticker list view.
    /// Constrained horizontally to `stickerPanel.safeAreaLayoutGuide` with a fixed margin.
    /// On iOS 26 it's leading edge aligns with (+) attachment button and
    /// trailing edge aligns with the blue Send button.
    private lazy var stickerListViewWrapper: UIVisualEffectView = {
        let view = UIVisualEffectView()

        if #available(iOS 26.0, *) {
            view.clipsToBounds = true
            view.cornerConfiguration = .uniformCorners(radius: .fixed(StickerLayout.backgroundCornerRadius))

            // `stickersListView` is inset from its parent container with a very small inset.
            // Make sure its corners are also rounded so that content doesn't go outside of the panel.
            let minRadius = StickerLayout.backgroundCornerRadius - max(StickerLayout.backgroundMargins.leading, StickerLayout.backgroundMargins.top)
            stickersListView.cornerConfiguration = .uniformCorners(radius: .containerConcentric(minimum: minRadius))
        }

        // List view.
        view.directionalLayoutMargins = StickerLayout.backgroundMargins
        stickersListView.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.addSubview(stickersListView)
        NSLayoutConstraint.activate([
            stickersListView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            stickersListView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stickersListView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stickersListView.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),

            stickersListView.heightAnchor.constraint(
                equalToConstant: StickerLayout.listItemSize + StickerLayout.listViewPadding.totalHeight
            ),
        ])

        return view
    }()

    private lazy var stickersListView: StickerHorizontalListView = {
        let view = StickerHorizontalListView(
            cellSize: StickerLayout.listItemSize,
            cellContentInset: 0,
            spacing: StickerLayout.listItemSpacing
        )
        view.backgroundColor = .clear
        view.contentInset = StickerLayout.listViewPadding
        return view
    }()

    private func loadStickerPanelIfNecessary() {
        guard stickerListViewWrapper.superview == nil else { return }

        stickerPanel.addSubview(stickerListViewWrapper)
        stickerListViewWrapper.translatesAutoresizingMaskIntoConstraints = false
        stickerPanel.addConstraints([
            stickerListViewWrapper.topAnchor.constraint(
                equalTo: stickerPanel.topAnchor
            ),
            stickerListViewWrapper.leadingAnchor.constraint(
                equalTo: stickerPanel.safeAreaLayoutGuide.leadingAnchor,
                constant: StickerLayout.outerPanelHMargin
            ),
            stickerListViewWrapper.trailingAnchor.constraint(
                equalTo: stickerPanel.layoutMarginsGuide.trailingAnchor,
                constant: -StickerLayout.outerPanelHMargin
            ),
            stickerListViewWrapper.bottomAnchor.constraint(
                equalTo: stickerPanel.bottomAnchor
            )
        ])

        UIView.performWithoutAnimation {
            stickerPanel.layoutIfNeeded()
        }
    }

    private func updateSuggestedStickers(animated: Bool) {
        // Skip this until we are in the view hierarchy.
        guard superview != nil else { return }

        let suggestedStickerEmoji = StickerManager.suggestedStickerEmoji(chatBoxText: inputTextView.trimmedText)
        guard currentSuggestedStickerEmoji != suggestedStickerEmoji else { return }
        currentSuggestedStickerEmoji = suggestedStickerEmoji

        let suggestedStickers: [StickerInfo]
        if let suggestedStickerEmoji {
            suggestedStickers = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return StickerManager.suggestedStickers(for: suggestedStickerEmoji, tx: tx).map { $0.info }
            }
        } else {
            suggestedStickers = []
        }
        guard currentSuggestedStickers != suggestedStickers else { return }

        currentSuggestedStickers = suggestedStickers

        guard !suggestedStickers.isEmpty else {
            hideStickerPanel(animated: animated)
            return
        }

        showStickerPanel(animated: animated)
    }

    private func showStickerPanel(animated: Bool) {
        guard let stickerPanelSuperview = inputToolbarDelegate?.viewForSuggestedStickersPanel() else {
            owsFailBeta("No view provided for stickers panel.")
            return
        }

        owsAssertDebug(!currentSuggestedStickers.isEmpty)

        loadStickerPanelIfNecessary()

        stickersListView.items = currentSuggestedStickers.map { stickerInfo in
            StickerHorizontalListViewItemSticker(
                stickerInfo: stickerInfo,
                didSelectBlock: { [weak self] in
                    self?.didSelectSuggestedSticker(stickerInfo)
                },
                cache: suggestedStickerViewCache
            )
        }

        guard isStickerPanelHidden else { return }

        isStickerPanelHidden = false

        UIView.performWithoutAnimation {
            // Find a subview of `stickerPanelSuperview` that we would put `stickerPanel` behind.
            var stickerPanelSiblingView: UIView = self
            while let siblingSuperView = stickerPanelSiblingView.superview,
                  siblingSuperView != stickerPanelSuperview
            {
                stickerPanelSiblingView = siblingSuperView
            }

            // Add `stickerPanel` to the view hierarchy and set up constraints.
            stickerPanelSuperview.insertSubview(stickerPanel, belowSubview: stickerPanelSiblingView)
            stickerPanel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stickerPanel.leadingAnchor.constraint(equalTo: stickerPanelSuperview.leadingAnchor),
                stickerPanel.trailingAnchor.constraint(equalTo: stickerPanelSuperview.trailingAnchor),
                stickerPanel.bottomAnchor.constraint(equalTo: self.topAnchor)
            ])

            // Manually calculate final size and position of the `stickerPanel`
            // and place it appropriately.
            // This is done to avoid calling `layoutSubviews` on the panel's parent which is likely VC's root view.
            let stickerPanelMaxY = stickerPanelSuperview.convert(bounds.origin, from: self).y
            let stickerPanelSize = stickerPanel.systemLayoutSizeFitting(
                CGSize(width: stickerPanelSuperview.bounds.width, height: 300),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            stickerPanel.frame = CGRect(
                origin: CGPoint(
                    x: stickerPanelSuperview.bounds.minX,
                    y: stickerPanelMaxY - stickerPanelSize.height
                ),
                size: CGSize(
                    width: stickerPanelSuperview.bounds.width,
                    height: stickerPanelSize.height
                )
            )
            // Ensure final layout within the panel.
            stickerPanel.layoutIfNeeded()

            // Set initial scroll position in the list.
            stickersListView.contentOffset = CGPoint(
                x: -(CurrentAppContext().isRTL
                     ? stickersListView.frame.width - stickersListView.contentSize.width - StickerLayout.listViewPadding.right
                     : StickerLayout.listViewPadding.left),
                y: -StickerLayout.listViewPadding.top
            )
        }

        guard animated else {
            stickerListViewWrapper.transform = .identity
            stickerListViewWrapper.effect = StickerLayout.panelVisualEffect

            stickersListView.alpha = 1
            return
        }

        // Prepare initial state for animations.
        UIView.performWithoutAnimation {
            stickerListViewWrapper.transform = StickerLayout.animationTransform(stickerListViewWrapper)
            stickerListViewWrapper.effect = nil

            stickersListView.alpha = 0
        }

        // Animate.
        let animator = StickerLayout.animator()
        animator.addAnimations {
            self.stickerListViewWrapper.transform = .identity
            self.stickerListViewWrapper.effect = StickerLayout.panelVisualEffect

            self.stickersListView.alpha = 1
        }
        animator.startAnimation()
    }

    private func hideStickerPanel(animated: Bool) {
        guard !isStickerPanelHidden else { return }

        guard animated else {
            stickerPanel.removeFromSuperview()
            isStickerPanelHidden = true
            return
        }

        let animator = StickerLayout.animator()
        animator.addAnimations {
            self.stickerListViewWrapper.transform = StickerLayout.animationTransform(self.stickerListViewWrapper)
            self.stickerListViewWrapper.effect = nil

            self.stickersListView.alpha = 0
        }
        animator.addCompletion { _ in
            self.stickerPanel.removeFromSuperview()
            self.isStickerPanelHidden = true
        }
        animator.startAnimation()
    }

    private func didSelectSuggestedSticker(_ stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

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

    var voiceMemoDraft: VoiceMessageInterruptedDraft?
    private var voiceMemoStartTime: Date?
    private var voiceMemoUpdateTimer: Timer?
    private var voiceMemoTooltipView: UIView?
    private lazy var voiceMemoDurationLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = Style.primaryTextColor
        label.font = .monospacedDigitSystemFont(ofSize: UIFont.dynamicTypeBodyClamped.pointSize, weight: .semibold)
        label.setContentHuggingHigh()
        label.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "recordingLabel")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var voiceMemoCancelLabel: UILabel = {
        let cancelLabelFont = UIFont.dynamicTypeSubheadlineClamped
        let cancelArrowFontSize = cancelLabelFont.pointSize + 7
        let cancelString = NSMutableAttributedString(
            string: "\u{F104}",
            attributes: [
                .font: UIFont.awesomeFont(ofSize: cancelArrowFontSize),
                .baselineOffset: -2
            ]
        )
        cancelString.append(
            NSAttributedString(
                string: "  ",
                attributes: [ .font: cancelLabelFont ]
            )
        )
        cancelString.append(
            NSAttributedString(
                string: OWSLocalizedString("VOICE_MESSAGE_CANCEL_INSTRUCTIONS", comment: "Indicates how to cancel a voice message."),
                attributes: [ .font: cancelLabelFont ]
            )
        )
        cancelString.addAttributeToEntireString(.foregroundColor, value: Style.secondaryTextColor)
        let label = UILabel()
        label.textAlignment = .right
        label.attributedText = cancelString
        label.translatesAutoresizingMaskIntoConstraints = false
        label.sizeToFit()
        return label
    }()

    private lazy var voiceMemoRedRecordingCircle: UIView = {
        let micIconSize: CGFloat = 32
        let circleSize: CGFloat = 88

        let micIcon = UIImageView(image: UIImage(imageLiteralResourceName: "mic-fill"))
        micIcon.tintColor = .white

        let circleView = CircleView(frame: CGRect(origin: .zero, size: .square(circleSize)))
        circleView.backgroundColor = .Signal.red
        circleView.addSubview(micIcon)
        circleView.translatesAutoresizingMaskIntoConstraints = false
        micIcon.translatesAutoresizingMaskIntoConstraints = false
        circleView.addConstraints([
            micIcon.widthAnchor.constraint(equalToConstant: micIconSize),
            micIcon.heightAnchor.constraint(equalToConstant: micIconSize),

            micIcon.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),

            circleView.widthAnchor.constraint(equalToConstant: circleSize),
            circleView.heightAnchor.constraint(equalToConstant: circleSize),
        ])
        return circleView
    }()

    private lazy var voiceMemoLockView: VoiceMemoLockView = {
        let view = VoiceMemoLockView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var voiceMemoDeleteButton: UIButton = {
#if compiler(>=6.2)
        guard #unavailable(iOS 26.0) else {
            return Buttons.deleteVoiceMemoDraftButton(
                primaryAction: UIAction { [weak self] _ in
                    self?.deleteVoiceMemoDraft()
                },
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "stickerButton")
            )
        }
#endif

        let button = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                self?.deleteVoiceMemoDraft()
            }
        )
        button.configuration?.image = UIImage(imageLiteralResourceName: "trash-fill")
        button.configuration?.baseForegroundColor = .Signal.red
        return button
    }()

    func showVoiceMemoUI() {
        AssertIsOnMainThread()

        isShowingVoiceMemoUI = true

        // Prepare initial state.
        removeVoiceMemoTooltip()

        voiceMemoStartTime = Date()
        voiceMemoLockView.update(ratioComplete: 0)

        voiceMemoContentView.removeAllSubviews()
        // These are added to self.
        voiceMemoRedRecordingCircle.removeFromSuperview()
        voiceMemoLockView.removeFromSuperview()

        // Red mic icon
        let redMicIconImageView = UIImageView(image: UIImage(imageLiteralResourceName: "mic-fill"))
        redMicIconImageView.tintColor = .Signal.red
        redMicIconImageView.autoSetDimensions(to: .square(24))
        voiceMemoContentView.addSubview(redMicIconImageView)

        // Duration Label
        updateVoiceMemoDurationLabel()
        voiceMemoContentView.addSubview(voiceMemoDurationLabel)

        // < Swipe to Cancel
        voiceMemoCancelLabel.alpha = 1
        voiceMemoContentView.addSubview(voiceMemoCancelLabel)

        // Constraints for the content inside of text input box.
        redMicIconImageView.translatesAutoresizingMaskIntoConstraints = false
        voiceMemoContentView.addConstraints([
            redMicIconImageView.leadingAnchor.constraint(equalTo: voiceMemoContentView.leadingAnchor, constant: 12),
            redMicIconImageView.centerYAnchor.constraint(equalTo: voiceMemoContentView.centerYAnchor),

            voiceMemoDurationLabel.leadingAnchor.constraint(equalTo: redMicIconImageView.trailingAnchor, constant: 12),
            voiceMemoDurationLabel.centerYAnchor.constraint(equalTo: voiceMemoContentView.centerYAnchor),

            // X-position is configured relative to big red circle - later in this method.
            voiceMemoCancelLabel.centerYAnchor.constraint(equalTo: voiceMemoContentView.centerYAnchor, constant: -2),
        ])

        // Big red circle with mic icon inside and lock icon above.
        let redCircleCenterXAnchor: NSLayoutXAxisAnchor
        if let rightEdgeControls = trailingEdgeControl as? RightEdgeControlsView {
            redCircleCenterXAnchor = rightEdgeControls.voiceMemoButton.centerXAnchor
        } else {
            redCircleCenterXAnchor = voiceNoteButton.centerXAnchor
        }
        addSubview(voiceMemoLockView)
        addSubview(voiceMemoRedRecordingCircle)
        addConstraints([
            voiceMemoRedRecordingCircle.centerXAnchor.constraint(equalTo: redCircleCenterXAnchor),
            voiceMemoRedRecordingCircle.centerYAnchor.constraint(equalTo: voiceMemoContentView.centerYAnchor),

            voiceMemoLockView.centerXAnchor.constraint(equalTo: redCircleCenterXAnchor),
            voiceMemoLockView.topAnchor.constraint(equalTo: voiceMemoRedRecordingCircle.topAnchor, constant: -120),

            voiceMemoCancelLabel.trailingAnchor.constraint(equalTo: voiceMemoRedRecordingCircle.leadingAnchor, constant: -16),
        ])

        // Animations

        // Animate in red circle and lock view (lock view - with a delay).
        UIView.performWithoutAnimation {
            voiceMemoRedRecordingCircle.alpha = 0
            voiceMemoRedRecordingCircle.transform = .scale(0.9)

            voiceMemoLockView.alpha = 0
            voiceMemoLockView.transform = .scale(0.9)
        }
        UIView.animate(withDuration: 0.2) {
            self.voiceMemoRedRecordingCircle.alpha = 1
            self.voiceMemoRedRecordingCircle.transform = .identity
        }
        UIView.animate(withDuration: 0.2, delay: 1) {
            self.voiceMemoLockView.alpha = 1
            self.voiceMemoLockView.transform = .identity
        }

        // Pulse the red mic icon on the left.
        redMicIconImageView.alpha = 1
        UIView.animate(
            withDuration: 0.5,
            delay: 0.2,
            options: [.repeat, .autoreverse, .curveEaseIn],
            animations: {
                redMicIconImageView.alpha = 0
            }
        )

        // Start recording timer.
        voiceMemoUpdateTimer?.invalidate()
        voiceMemoUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.updateVoiceMemoDurationLabel()
        }
    }

    func showVoiceMemoDraft(_ voiceMemoDraft: VoiceMessageInterruptedDraft) {
        AssertIsOnMainThread()

        isShowingVoiceMemoUI = true

        voiceMemoRecordingState = .draft

        removeVoiceMemoTooltip()

        voiceMemoContentView.removeAllSubviews()
        // These are added to self.
        voiceMemoRedRecordingCircle.removeFromSuperview()
        voiceMemoLockView.removeFromSuperview()

        voiceMemoUpdateTimer?.invalidate()
        voiceMemoUpdateTimer = nil

        let draftView = VoiceMessageDraftView(
            voiceMessageInterruptedDraft: voiceMemoDraft,
            mediaCache: mediaCache
        )
        voiceMemoContentView.addSubview(draftView)
        draftView.translatesAutoresizingMaskIntoConstraints = false
        voiceMemoContentView.addConstraints([
            draftView.topAnchor.constraint(equalTo: voiceMemoContentView.topAnchor),
            draftView.leadingAnchor.constraint(equalTo: voiceMemoContentView.leadingAnchor),
            draftView.trailingAnchor.constraint(equalTo: voiceMemoContentView.trailingAnchor),
            draftView.bottomAnchor.constraint(equalTo: voiceMemoContentView.bottomAnchor),
        ])

        self.voiceMemoDraft = voiceMemoDraft
    }

    private func deleteVoiceMemoDraft() {
        guard let voiceMemoDraft else {
            owsFailBeta("No voice memo draft")
            return
        }
        voiceMemoDraft.audioPlayer.stop()
        SSKEnvironment.shared.databaseStorageRef.asyncWrite {
            voiceMemoDraft.clearDraft(transaction: $0)
        } completion: {
            self.hideVoiceMemoUI(animated: true)
        }
    }

    func hideVoiceMemoUI(animated: Bool) {
        AssertIsOnMainThread()

        isShowingVoiceMemoUI = false

        voiceMemoContentView.removeAllSubviews()

        voiceMemoRecordingState = .idle
        voiceMemoDraft = nil

        voiceMemoUpdateTimer?.invalidate()
        voiceMemoUpdateTimer = nil

        guard voiceMemoRedRecordingCircle.superview != nil else { return }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    let scale: CGFloat = 0.9

                    self.voiceMemoRedRecordingCircle.alpha = 0
                    // Red circle might have a translation transorm - make sure to preserve it.
                    self.voiceMemoRedRecordingCircle.transform = self.voiceMemoRedRecordingCircle.transform.scaledBy(x: scale, y: scale)

                    self.voiceMemoLockView.alpha = 0
                    self.voiceMemoLockView.transform = .scale(scale)
                },
                completion: { _ in
                    self.voiceMemoRedRecordingCircle.removeFromSuperview()
                    self.voiceMemoLockView.removeFromSuperview()
                }
            )
        } else {
            voiceMemoRedRecordingCircle.removeFromSuperview()
            voiceMemoLockView.removeFromSuperview()
        }
    }

    func lockVoiceMemoUI() {
        ImpactHapticFeedback.impactOccurred(style: .medium)

        let cancelButton = UIButton(
            configuration: .borderless(),
            primaryAction: UIAction { [weak self] _ in
                self?.inputToolbarDelegate?.voiceMemoGestureDidCancel()
            }
        )
        cancelButton.alpha = 0
        cancelButton.configuration?.baseForegroundColor = .Signal.red
        cancelButton.configuration?.contentInsets = .init(margin: 8)
        cancelButton.configuration?.title = CommonStrings.cancelButton
        cancelButton.configuration?.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        cancelButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "cancelButton")
        voiceMemoContentView.addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        voiceMemoContentView.addConstraints([
            cancelButton.centerYAnchor.constraint(equalTo: voiceMemoContentView.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: voiceMemoContentView.trailingAnchor, constant: -16),
        ])

        voiceMemoCancelLabel.removeFromSuperview()
        voiceMemoContentView.layoutIfNeeded()

        UIView.animate(
            withDuration: 0.2,
            animations: {
                let scale: CGFloat = 0.9

                self.voiceMemoRedRecordingCircle.alpha = 0
                self.voiceMemoRedRecordingCircle.transform = self.voiceMemoRedRecordingCircle.transform.scaledBy(x: scale, y: scale)

                self.voiceMemoLockView.alpha = 0
                self.voiceMemoLockView.transform = .scale(scale)

                cancelButton.alpha = 1
            },
            completion: { _ in
                self.voiceMemoRedRecordingCircle.removeFromSuperview()
                self.voiceMemoLockView.removeFromSuperview()

                UIAccessibility.post(notification: .layoutChanged, argument: nil)
            }
        )
    }

    private func setVoiceMemoUICancelAlpha(_ cancelAlpha: CGFloat) {
        AssertIsOnMainThread()

        // Fade out the voice message views as the cancel gesture
        // proceeds as feedback.
        voiceMemoCancelLabel.alpha = CGFloat.clamp01(1 - cancelAlpha)
    }

    private func updateVoiceMemoDurationLabel() {
        AssertIsOnMainThread()

        defer {
            voiceMemoDurationLabel.sizeToFit()
        }

        guard let voiceMemoStartTime else {
            voiceMemoDurationLabel.text = ""
            return
        }

        let durationSeconds = abs(voiceMemoStartTime.timeIntervalSinceNow)
        voiceMemoDurationLabel.text = OWSFormat.formatDurationSeconds(Int(round(durationSeconds)))
    }

    func showVoiceMemoTooltip() {
        guard voiceMemoTooltipView == nil else { return }
        guard let rightEdgeControlsView = trailingEdgeControl as? RightEdgeControlsView else { return }

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
                voiceMemoLockView.update(ratioComplete: lockAlpha)

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
                    voiceMemoRedRecordingCircle.transform = CGAffineTransform(translationX: min(-xOffset, 0), y: 0)
                } else if yOffset > xOffset {
                    voiceMemoRedRecordingCircle.transform = CGAffineTransform(translationX: 0, y: min(-yOffset, 0))
                } else {
                    voiceMemoRedRecordingCircle.transform = .identity
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
        let stickerKeyboard = StickerKeyboard(delegate: self)
        _stickerKeyboard = stickerKeyboard
        return stickerKeyboard
    }

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
        let keyboard = AttachmentKeyboard(delegate: self)
        _attachmentKeyboard = keyboard
        return keyboard
    }

    func showAttachmentKeyboard() {
        AssertIsOnMainThread()
        guard desiredKeyboardType != .attachment else { return }
        toggleKeyboardType(.attachment, animated: false)
    }

    private func toggleKeyboardType(_ keyboardType: KeyboardType, animated: Bool) {
        guard let inputToolbarDelegate else {
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

        // Measure system keyboard size when switching away from it,
        // but only if we don't know the height for this orientation yet.
        if  desiredKeyboardType == .system,
            inputTextView.isFirstResponder,
            !CustomKeyboard.hasCachedHeight(forTraitCollection: traitCollection)
        {
            calculateCustomKeyboardHeight()
        }

        _desiredKeyboardType = keyboardType

        ensureButtonVisibility(withAnimation: animated, doLayout: true)

        // Do this before assigning as `inputView`.
        if let customKeyboard = desiredInputView as? CustomKeyboard {
            customKeyboard.updateHeightForPresentation()
        }

        inputTextView.inputView = desiredInputView
        inputTextView.reloadInputViews()

        // Add "Tap to switch to system keyboard" behavior.
        if desiredKeyboardType == .system {
            inputTextView.removeGestureRecognizer(textInputViewTapGesture)
        } else if textInputViewTapGesture.view == nil {
            inputTextView.addGestureRecognizer(textInputViewTapGesture)
        }
    }

    private func calculateCustomKeyboardHeight() {
        guard desiredKeyboardType == .system, inputTextView.isFirstResponder else { return }

        let viewForKeyboardLayoutGuide = inputToolbarDelegate?.viewForKeyboardLayoutGuide() ?? self
        let keyboardHeight = viewForKeyboardLayoutGuide.keyboardLayoutGuide.layoutFrame.height
        if keyboardHeight > 100 {
            Logger.debug("Keyboard height: \(keyboardHeight). Horizontal: \(traitCollection.horizontalSizeClass) Vertical: \(traitCollection.verticalSizeClass)")
            stickerKeyboard.setSystemKeyboardHeight(keyboardHeight, forTraitCollection: traitCollection)
            attachmentKeyboard.setSystemKeyboardHeight(keyboardHeight, forTraitCollection: traitCollection)
        } else {
            Logger.warn("Suspicious keyboard height: \(keyboardHeight)")
        }
    }

    func clearDesiredKeyboard() {
        AssertIsOnMainThread()
        desiredKeyboardType = .system
    }

    private func restoreDesiredKeyboardIfNecessary() {
        AssertIsOnMainThread()
        if desiredKeyboardType != .system && !inputTextView.isFirstResponder {
            beginEditingMessage()
        }
    }

    var isInputViewFirstResponder: Bool {
        return inputTextView.isFirstResponder
    }

    private var desiredInputView: UIInputView? {
        switch desiredKeyboardType {
        case .system: return nil
        case .sticker: return stickerKeyboard
        case .attachment: return attachmentKeyboard
        }
    }

    func beginEditingMessage() {
        _ = inputTextView.becomeFirstResponder()
    }

    func endEditingMessage() {
        _ = inputTextView.resignFirstResponder()
    }

    func viewDidAppear() {
        ensureButtonVisibility(withAnimation: false, doLayout: false)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #unavailable(iOS 26), let legacyBackgroundView, let legacyBackgroundBlurView {
            updateBackgroundColors(backgroundView: legacyBackgroundView, backgroundBlurView: legacyBackgroundBlurView)
        }

        // Starting with iOS 17 UIKit messes up keyboard layout guide on rotation if custom keyboard is up.
        // That causes the keyboard to overlap text input field and become unaccessible.
        // The workaround is to hide the keyboard on rotation.
        guard #available(iOS 17, *) else { return }

        // Require a custom keyboard to be up.
        guard inputTextView.isFirstResponder, desiredKeyboardType != .system else { return }

        // We only care about changes in size classes, which would be triggered by interface rotation.
        guard
            previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass ||
            previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass
        else { return }

        // Dismiss keyboard.
        endEditingMessage()
    }

    @objc
    private func applicationDidBecomeActive(notification: Notification) {
        AssertIsOnMainThread()
        restoreDesiredKeyboardIfNecessary()
    }

    private lazy var textInputViewTapGesture = UITapGestureRecognizer(target: self, action: #selector(textInputViewTapped))

    @objc
    private func textInputViewTapped() {
        clearDesiredKeyboard()
    }
}

// MARK: Button Actions

extension ConversationInputToolbar {

    private func cameraButtonPressed() {
        guard let inputToolbarDelegate = inputToolbarDelegate else {
            owsFailDebug("inputToolbarDelegate == nil")
            return
        }
        ImpactHapticFeedback.impactOccurred(style: .light)
        inputToolbarDelegate.cameraButtonPressed()
    }

    @objc
    private func addOrCancelButtonPressed() {
        ImpactHapticFeedback.impactOccurred(style: .light)
        if isEditingMessage {
            editTarget = nil
            quotedReplyDraft = nil
            clearTextMessage(animated: true)
        } else {
            toggleKeyboardType(.attachment, animated: true)
        }
    }

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

    private func stickerButtonPressed() {
        ImpactHapticFeedback.impactOccurred(style: .light)

        var hasInstalledStickerPacks: Bool = false
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            hasInstalledStickerPacks = !StickerManager.installedStickerPacks(transaction: transaction).isEmpty
        }
        guard hasInstalledStickerPacks else {
            inputToolbarDelegate?.presentManageStickersView()
            return
        }
        toggleKeyboardType(.sticker, animated: true)
    }

    private func keyboardButtonPressed() {
        ImpactHapticFeedback.impactOccurred(style: .light)

        toggleKeyboardType(.system, animated: true)
    }
}

extension ConversationInputToolbar: ConversationTextViewToolbarDelegate {

    private func updateHeightWithTextView(_ textView: UITextView) {

        let maxSize = CGSize(width: textView.width - textView.textContainerInset.totalWidth, height: CGFloat.greatestFiniteMagnitude)
        var textToMeasure: NSAttributedString = textView.attributedText
        if textToMeasure.isEmpty {
            textToMeasure = NSAttributedString(string: "M", attributes: [.font: textView.font ?? .dynamicTypeBody])
        }
        var contentSize = textToMeasure.boundingRect(with: maxSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size
        contentSize.height += textView.textContainerInset.top
        contentSize.height += textView.textContainerInset.bottom

        let newHeight = CGFloat.clamp(
            contentSize.height.rounded(),
            min: LayoutMetrics.minTextViewHeight,
            max: UIDevice.current.isIPad ? LayoutMetrics.maxTextViewHeightIpad : LayoutMetrics.maxTextViewHeight
        )

        guard newHeight != textViewHeight else { return }

        guard let textViewHeightConstraint else {
            owsFailDebug("textViewHeightConstraint == nil")
            return
        }

        textViewHeight = newHeight
        textViewHeightConstraint.constant = newHeight

        if let superview, inputToolbarDelegate != nil {
            let animator = UIViewPropertyAnimator(
                duration: ConversationInputToolbar.heightChangeAnimationDuration,
                springDamping: 1,
                springResponse: 0.25
            )
            animator.addAnimations {
                self.invalidateIntrinsicContentSize()
                superview.layoutIfNeeded()
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

        if editTarget != nil {
            // Here we could potentially compare to original (before edit)
            // message and update Send button accordingly.
            setSendButtonEnabled(hasMessageText)
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) { }
}

extension ConversationInputToolbar: StickerKeyboardDelegate {

    public func stickerKeyboard(_: StickerKeyboard, didSelect stickerInfo: StickerInfo) {
        AssertIsOnMainThread()
        inputToolbarDelegate?.sendSticker(stickerInfo)
    }

    public func stickerKeyboardDidRequestPresentManageStickersView(_ stickerKeyboard: StickerKeyboard) {
        AssertIsOnMainThread()
        inputToolbarDelegate?.presentManageStickersView()
    }
}

extension ConversationInputToolbar: AttachmentKeyboardDelegate {

    func didSelectRecentPhoto(asset: PHAsset, attachment: PreviewableAttachment) {
        inputToolbarDelegate?.didSelectRecentPhoto(asset: asset, attachment: attachment)
    }

    func didTapPhotos() {
        inputToolbarDelegate?.photosButtonPressed()
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

    func didTapPoll() {
        inputToolbarDelegate?.pollButtonPressed()
    }

    var isGroup: Bool {
        inputToolbarDelegate?.isGroup() ?? false
    }
}

extension ConversationInputToolbar: ConversationBottomBar {
    var shouldAttachToKeyboardLayoutGuide: Bool { true }
}

@available(iOS 26, *)
private extension ColorOrGradientValue {

    func asSendButtonTintColor() -> UIColor {
        let bubbleColor: UIColor = {
            switch self {
            case .transparent:
                return .Signal.accent

            case .solidColor(let color):
                return color

            case .gradient(let gradientColor1, let gradientColor2, _):
                return gradientColor1.midPoint(with: gradientColor2)
            }
        }()
        let lightThemeFinalColor = bubbleColor.blendedWithOverlay(.white, opacity: 0.16)
        let darkThemeFinalColor = bubbleColor.blendedWithOverlay(.black, opacity: 0.1)
        return UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return darkThemeFinalColor
            } else {
                return lightThemeFinalColor
            }
        }
    }
}
