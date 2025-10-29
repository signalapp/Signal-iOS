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

    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment)

    func showUnblockConversationUI(completion: ((Bool) -> Void)?)
}

protocol ConversationInputPanelWithContentLayoutGuide {
    /// View controller should use this layout guide to position content above the keyboard.
    var contentLayoutGuide: UILayoutGuide { get }
}

public class ConversationInputToolbar: UIView, ConversationInputPanelWithContentLayoutGuide, QuotedReplyPreviewDelegate {

    private let spoilerState: SpoilerRenderState

    private let mediaCache: CVMediaCache

    private weak var inputToolbarDelegate: ConversationInputToolbarDelegate?

    public let contentLayoutGuide = UILayoutGuide()

    init(
        spoilerState: SpoilerRenderState,
        mediaCache: CVMediaCache,
        messageDraft: MessageBody?,
        quotedReplyDraft: DraftQuotedReplyModel?,
        editTarget: TSOutgoingMessage?,
        inputToolbarDelegate: ConversationInputToolbarDelegate,
        inputTextViewDelegate: ConversationInputTextViewDelegate,
        bodyRangesTextViewDelegate: BodyRangesTextViewDelegate
    ) {
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

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

    private enum LayoutMetrics {
        static let initialToolbarHeight: CGFloat = 52
        static let initialTextBoxHeight: CGFloat = 40

        static let minTextViewHeight: CGFloat = 35
        static let maxTextViewHeight: CGFloat = 98
        static let maxTextViewHeightIpad: CGFloat = 142
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
            if #available(iOS 26, *) {
                button.configuration?.baseForegroundColor = Theme.primaryTextColor
            } else {
                button.configuration?.baseForegroundColor = Theme.primaryIconColor
            }
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

#if compiler(>=6.2)
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
            button.tintColor = .Signal.accent
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
            button.tintColor = .white
            button.configuration?.image = UIImage(imageLiteralResourceName: "plus")
            button.configuration?.baseForegroundColor = .Signal.label
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
#endif
    }

    private lazy var inputTextView: ConversationInputTextView = {
        let inputTextView = ConversationInputTextView()
        inputTextView.textViewToolbarDelegate = self
        inputTextView.font = .dynamicTypeBody
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
        guard #unavailable(iOS 26.0) else {
            return Buttons.sendButton(
                primaryAction: UIAction { [weak self] _ in
                    self?.sendButtonPressed()
                },
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "sendButton")
            )
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

    private lazy var editMessageThumbnailView: UIImageView = {
        let imageView = UIImageView()
        imageView.layer.cornerRadius = 4
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var editMessageLabelWrapper: UIView = {
        let editIconView = UIImageView(image: Theme.iconImage(.compose16))
        editIconView.contentMode = .scaleAspectFit
        editIconView.setContentHuggingHigh()
        editIconView.tintColor = .Signal.label

        let editLabel = UILabel()
        editLabel.text = OWSLocalizedString(
            "INPUT_TOOLBAR_EDIT_MESSAGE_LABEL",
            comment: "Label at the top of the input text when editing a message"
        )
        editLabel.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        editLabel.textColor = .Signal.label

        let stackView = UIStackView(arrangedSubviews: [editIconView, editLabel, editMessageThumbnailView])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let view = UIView()
        view.directionalLayoutMargins = .init(top: 12, leading: 12, bottom: 4, trailing: 8)
        view.addSubview(stackView)
        view.addConstraints([
            editLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor), // align using textLabel, not stackView
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),

            editMessageThumbnailView.widthAnchor.constraint(equalToConstant: 20),
            editMessageThumbnailView.heightAnchor.constraint(equalToConstant: 20),
        ])
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "editMessageWrapper")

        return view
    }()

    private lazy var quotedReplyWrapper: UIView = {
        let view = UIView.container()
        view.directionalLayoutMargins = .init(top: 6, leading: 6, bottom: 0, trailing: 6)
        view.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "quotedReplyWrapper")
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

    // Whole-width container that contains (+) button, text input part and Send button.
    private let contentView = UIView()

    // Occupies central part of the `contentView`. That's where text input field, link preview etc live in.
    private let messageContentView = UIView()

    @available(iOS 26, *)
    func setScrollEdgeElementContainerInteraction(_ interaction: UIInteraction) {
        contentView.addInteraction(interaction)
    }

    private var isConfigurationComplete = false

    private func setupContentView() {
        // The input toolbar should *always* be laid out left-to-right, even when using
        // a right-to-left language. The convention for messaging apps is for the send
        // button to always be to the right of the input field, even in RTL layouts.
        // This means you'll need to set the appropriate `semanticContentAttribute`
        // to ensure horizontal stack views layout left-to-right.
        semanticContentAttribute = .forceLeftToRight

        // `contentLayoutGuide` defines area where all the content lives.
        addLayoutGuide(contentLayoutGuide)
        addConstraints([
            contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            contentLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            {
                let c = contentLayoutGuide.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
                c.priority = .defaultLow
                return c
            }()
        ])

        // "Suggested Stickers" horizontal list view will be placed in a wrapper view to allow for slide in / slide out animation.
        updateSuggestedStickersPanelConstraints()

        if #available(iOS 26, *) {
            iOS26Layout = true
        }

        let contentViewWrapperView = UIView.container()

        // Outermost vertical stack:
        // [ Suggested Stickers Panel ]
        // [ Message Creation Input Box and Buttons ]
        let outerVStack = UIStackView(arrangedSubviews: [ suggestedStickersPanel, contentViewWrapperView ] )
        outerVStack.axis = .vertical
        addSubview(outerVStack)
        outerVStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            outerVStack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            outerVStack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            outerVStack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            outerVStack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])

        // Background needed on pre-iOS 26 devices.
        // Background is constrained to `contentViewWrapperView` on all edges except for bottom.
        // Background is constrained to `self.bottom` to cover any safe area gaps.
        if !iOS26Layout {
            let backgroundView = UIView()
            if UIAccessibility.isReduceTransparencyEnabled {
                backgroundView.backgroundColor = Theme.toolbarBackgroundColor
            } else {
                backgroundView.backgroundColor = Theme.toolbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)

                let blurEffectView = UIVisualEffectView(effect: Theme.barBlurEffect)
                // Alter the visual effect view's tint to match our background color
                // so the input bar, when over a solid color background matching `toolbarBackgroundColor`,
                // exactly matches the background color. This is brittle, but there is no way to get
                // this behavior from UIVisualEffectView otherwise.
                if let tintingView = blurEffectView.subviews.first(where: {
                    String(describing: type(of: $0)) == "_UIVisualEffectSubview"
                }) {
                    tintingView.backgroundColor = backgroundView.backgroundColor
                }
                backgroundView.addSubview(blurEffectView)
                blurEffectView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    blurEffectView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
                    blurEffectView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
                    blurEffectView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
                    blurEffectView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
                ])
            }
            contentViewWrapperView.addSubview(backgroundView)
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                backgroundView.topAnchor.constraint(equalTo: contentViewWrapperView.topAnchor),
                backgroundView.leadingAnchor.constraint(equalTo: contentViewWrapperView.leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: contentViewWrapperView.trailingAnchor),
                // Note different anchor here.
                backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        // Set up content view.
        contentView.semanticContentAttribute = .forceLeftToRight
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            hMargin: OWSTableViewController2.defaultHOuterMargin - 16,
            vMargin: iOS26Layout ? 6 : 0
        )
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentViewWrapperView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: contentViewWrapperView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentViewWrapperView.safeAreaLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentViewWrapperView.safeAreaLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentViewWrapperView.bottomAnchor),
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

        editMessageLabelWrapper.isHidden = !shouldShowEditUI

        quotedReplyWrapper.isHidden = quotedReplyDraft == nil
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
#if compiler(>=6.2)
        let backgroundView: UIView
        if #available(iOS 26, *) {
            let glassEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glassEffectView.cornerConfiguration = .uniformCorners(radius: 20)
            glassEffectView.contentView.addSubview(messageComponentsView)

            backgroundView = glassEffectView
        } else {
            backgroundView = UIView()
            backgroundView.backgroundColor = UIColor.Signal.tertiaryFill
            backgroundView.layer.cornerRadius = 20

            messageContentView.addSubview(messageComponentsView)
        }
#else
        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor.Signal.tertiaryFill
        backgroundView.layer.cornerRadius = 20

        messageContentView.addSubview(messageComponentsView)
#endif

        let vMargin = 0.5 * (LayoutMetrics.initialToolbarHeight - LayoutMetrics.initialTextBoxHeight)
        let hMargin: CGFloat = iOS26Layout ? 12 : 0 // iOS 26 needs space between leading/trailing buttons and text view background.
        messageContentView.directionalLayoutMargins = .init(hMargin: hMargin, vMargin: vMargin)
        messageContentView.semanticContentAttribute = .forceLeftToRight

        messageContentView.insertSubview(backgroundView, at: 0)
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

            messageContentView.addSubview(stickerButton)
            messageContentView.addSubview(keyboardButton)
            messageContentView.addSubview(cameraButton)
            messageContentView.addSubview(voiceNoteButton)

            stickerButton.translatesAutoresizingMaskIntoConstraints = false
            keyboardButton.translatesAutoresizingMaskIntoConstraints = false
            cameraButton.translatesAutoresizingMaskIntoConstraints = false
            voiceNoteButton.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                voiceNoteButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -4),
                cameraButton.trailingAnchor.constraint(equalTo: voiceNoteButton.leadingAnchor),
                stickerButton.trailingAnchor.constraint(equalTo: cameraButton.leadingAnchor),
                keyboardButton.trailingAnchor.constraint(equalTo: cameraButton.leadingAnchor),

                voiceNoteButton.centerYAnchor.constraint(equalTo: inputTextViewContainer.centerYAnchor),
                cameraButton.centerYAnchor.constraint(equalTo: inputTextViewContainer.centerYAnchor),
                stickerButton.centerYAnchor.constraint(equalTo: inputTextViewContainer.centerYAnchor),
                keyboardButton.centerYAnchor.constraint(equalTo: inputTextViewContainer.centerYAnchor),
            ])
        } else {
            inputTextView.inFieldButtonsAreaWidth = 1 * LayoutMetrics.initialTextBoxHeight

            messageContentView.addSubview(stickerButton)
            messageContentView.addSubview(keyboardButton)

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
        var rightEdgeControlsState: RightEdgeControlsView.State

        // Voice Memo UI.
        if isShowingVoiceMemoUI {
            voiceMemoContentView.setIsHidden(false, animated: isAnimated)

            // Send button would be visible if there's voice recording in progress in "locked" state.
            let hideSendButton = voiceMemoRecordingState == .recordingHeld || voiceMemoRecordingState == .idle
            rightEdgeControlsState = hideSendButton ? .hiddenSendButton : .sendButton
        } else {
            voiceMemoContentView.setIsHidden(true, animated: isAnimated)

            // Show Send button instead of Camera and Voice Message buttons only when text input isn't empty.
            let hasNonWhitespaceTextInput = !inputTextView.trimmedText.isEmpty || shouldShowEditUI
            rightEdgeControlsState = hasNonWhitespaceTextInput ? .sendButton : .default
        }

        let animator: UIViewPropertyAnimator?
        if isAnimated {
            animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 0.645, springResponse: 0.25)
        } else {
            animator = nil
        }

        // Attachment Button
        let leadingEdgeControlState: LeadingEdgeControlState =  {
            if isShowingVoiceMemoUI {
                return voiceMemoRecordingState == .draft ? .deleteVoiceMemoDraft : .none
            }
            return .addAttachment
        }()
        if setLeadingEdgeControlState(leadingEdgeControlState, usingAnimator: animator) {
            hasLayoutChanged = true
        }

        // Attachment button has more complex animations and cannot be grouped with the rest.
        if let attachmentButton = leadingEdgeControl as? AttachmentButtonProtocol {
            let buttonState: AttachmentButtonState = {
                if shouldShowEditUI {
                    return .close
                } else {
                    return desiredKeyboardType == .attachment ? .close : .add
                }
            }()
            attachmentButton.setButtonState(buttonState, usingAnimator: animator)
        }

        // Show / hide Sticker or Keyboard buttons inside of the text input field.
        // Show / hide Camera and Voice Note buttons inside of the text input field on iOS 26.
        // In-field buttons are only visible if there's no any text input, including whitespace-only.
        let hideTextFieldButtons = shouldShowEditUI || !inputTextView.untrimmedText.isEmpty || isShowingVoiceMemoUI || quotedReplyDraft != nil
        let hideStickerButton = hideTextFieldButtons || desiredKeyboardType == .sticker
        let hideKeyboardButton = hideTextFieldButtons || !hideStickerButton
        ConversationInputToolbar.setView(stickerButton, hidden: hideStickerButton, usingAnimator: animator)
        ConversationInputToolbar.setView(keyboardButton, hidden: hideKeyboardButton, usingAnimator: animator)
        if iOS26Layout {
            ConversationInputToolbar.setView(cameraButton, hidden: hideTextFieldButtons, usingAnimator: animator)
            ConversationInputToolbar.setView(voiceNoteButton, hidden: hideTextFieldButtons, usingAnimator: animator)
        }

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

        // Pre-iOS 26: update trailing edge controls.
        if let rightEdgeControlsView = trailingEdgeControl as? RightEdgeControlsView {
            if rightEdgeControlsView.state != rightEdgeControlsState {
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
        }

        // iOS 26+: show / hide Send button.
        if iOS26Layout {
            let hideSendButton = rightEdgeControlsState != .sendButton
            if setSendButtonHidden(hideSendButton, usingAnimator: animator) {
                hasLayoutChanged = true
            }
        }

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
        case none
        case addAttachment
        case deleteVoiceMemoDraft
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

    func updateFontSizes() {
        inputTextView.font = .dynamicTypeBody
    }

    // MARK: Right Edge Buttons

    @available(iOS, deprecated: 26.0)
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
            button.ows_adjustsImageWhenDisabled = true
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "sendButton")
            button.setImage(UIImage(imageLiteralResourceName: "send-blue-28"), for: .normal)
            button.bounds.size = CGSize(width: 48, height: LayoutMetrics.initialToolbarHeight)
            return button
        }()

        lazy var cameraButton: UIButton = {
            let button = UIButton(type: .system)
            button.tintColor = Theme.primaryIconColor
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
            button.tintColor = Theme.primaryIconColor
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
            switch buttonState {
            case .add:
                iconImageView.transform = .identity

            case .close:
                iconImageView.transform = .rotate(1.5 * .halfPi)
            }
        }
    }

#if compiler(>=6.2)
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
#endif

    // MARK: Message Body

    private var textViewHeight: CGFloat = 0

    private var textViewHeightConstraint: NSLayoutConstraint!

    class var heightChangeAnimationDuration: TimeInterval { 0.25 }

    private(set) var isAnimatingHeightChange = false

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

    // MARK: Edit Message

    var shouldShowEditUI: Bool { editTarget != nil }

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

    private func showEditMessageView(animated: Bool) {
        toggleMessageComponentVisibility(hide: false, component: editMessageLabelWrapper, animated: animated)
        setSendButtonEnabled(false)
    }

    private func hideEditMessageView(animated: Bool) {
        owsAssertDebug(editTarget == nil)
        toggleMessageComponentVisibility(hide: true, component: editMessageLabelWrapper, animated: animated)
        setSendButtonEnabled(true)
    }

    private func setSendButtonEnabled(_ enabled: Bool) {
        if let rightEdgeControlsView = trailingEdgeControl as? RightEdgeControlsView {
            rightEdgeControlsView.sendButton.isEnabled = enabled
        } else if let sendButton = trailingEdgeControl as? UIButton {
            sendButton.isEnabled = enabled
        }
    }

    // MARK: Quoted Reply

    var quotedReplyDraft: DraftQuotedReplyModel? {
        didSet {
            guard oldValue != quotedReplyDraft else { return }

            layer.removeAllAnimations()

            let animateChanges = window != nil
            if quotedReplyDraft != nil {
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
        guard let quotedReplyDraft else {
            owsFailDebug("quotedReply == nil")
            return
        }

        quotedReplyWrapper.removeAllSubviews()

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
        NSLayoutConstraint.activate([
            quotedMessagePreview.topAnchor.constraint(equalTo: quotedReplyWrapper.layoutMarginsGuide.topAnchor),
            quotedMessagePreview.leadingAnchor.constraint(equalTo: quotedReplyWrapper.layoutMarginsGuide.leadingAnchor),
            quotedMessagePreview.trailingAnchor.constraint(equalTo: quotedReplyWrapper.layoutMarginsGuide.trailingAnchor),
            quotedMessagePreview.bottomAnchor.constraint(equalTo: quotedReplyWrapper.layoutMarginsGuide.bottomAnchor),
        ])

        updateInputLinkPreview()

        toggleMessageComponentVisibility(hide: false, component: quotedReplyWrapper, animated: animated)
    }

    private func hideQuotedReplyView(animated: Bool) {
        owsAssertDebug(quotedReplyDraft == nil)
        toggleMessageComponentVisibility(hide: true, component: quotedReplyWrapper, animated: animated) { _ in
            self.quotedReplyWrapper.removeAllSubviews()
        }
    }

    private func toggleMessageComponentVisibility(
        hide: Bool,
        component: UIView,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        if animated, component.isHidden != hide {
            isAnimatingHeightChange = true

            UIView.animate(
                withDuration: ConversationInputToolbar.heightChangeAnimationDuration,
                animations: {
                    component.isHidden = hide
                },
                completion: { completed in
                    self.isAnimatingHeightChange = false
                    completion?(completed)
                }
            )
        } else {
            component.isHidden = hide
            completion?(true)
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

    private var suggestedStickerEmoji: Character?

    private var suggestedStickerInfos: [StickerInfo] = []

    private lazy var suggestedStickersListView: StickerHorizontalListView = {
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

    private let suggestedStickersPanel: UIView = {
        let view = UIView.container()
        view.clipsToBounds = true
        return view
    }()

    private var suggestedStickersPanelConstraints: [NSLayoutConstraint] = []

    private func updateSuggestedStickersPanelConstraints() {
        NSLayoutConstraint.deactivate(suggestedStickersPanelConstraints)

        defer {
            NSLayoutConstraint.activate(suggestedStickersPanelConstraints)
        }

        // suggestedStickerView is created lazily and isn't accessed until it is needed.
        // Set wrapper's height to zero if it is not needed yet.
        guard suggestedStickersPanel.subviews.count > 0 else {
            let zeroHeightConstraint = suggestedStickersPanel.heightAnchor.constraint(equalToConstant: 0)
            suggestedStickersPanelConstraints = [ zeroHeightConstraint ]
            return
        }

        // To hide suggested stickers panel I constrain both top and bottom edges of the `suggestedStickerView`
        // to the top edge of its wrapper view, effectively making that wrapper view a zero height view.
        // `suggestedStickerView` has a fixed height so animating this change results in a nice slide in/out animation.
        // `suggestedStickerView` is made visible by constraining all of its edges to wrapper view normally.
        let constraint: NSLayoutConstraint
        if isSuggestedStickersPanelHidden {
            constraint = suggestedStickersPanel.bottomAnchor.constraint(equalTo: suggestedStickersListView.topAnchor)
        } else {
            constraint = suggestedStickersPanel.bottomAnchor.constraint(equalTo: suggestedStickersListView.bottomAnchor)
        }
        suggestedStickersPanelConstraints = [ constraint ]
    }

    private var isSuggestedStickersPanelHidden = true

    private func updateSuggestedStickers(animated: Bool) {
        let suggestedStickerEmoji = StickerManager.suggestedStickerEmoji(chatBoxText: inputTextView.trimmedText)

        if self.suggestedStickerEmoji == suggestedStickerEmoji {
            return
        }
        self.suggestedStickerEmoji = suggestedStickerEmoji

        let suggestedStickerInfos: [StickerInfo]
        if let suggestedStickerEmoji {
            suggestedStickerInfos = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return StickerManager.suggestedStickers(for: suggestedStickerEmoji, tx: tx).map { $0.info }
            }
        } else {
            suggestedStickerInfos = []
        }

        if self.suggestedStickerInfos == suggestedStickerInfos {
            return
        }
        self.suggestedStickerInfos = suggestedStickerInfos

        guard !suggestedStickerInfos.isEmpty else {
            hideSuggestedStickersPanel(animated: animated)
            return
        }

        showSuggestedStickersPanel(animated: animated)
    }

    private func showSuggestedStickersPanel(animated: Bool) {
        owsAssertDebug(!suggestedStickerInfos.isEmpty)

        if suggestedStickersListView.superview == nil {
            suggestedStickersPanel.addSubview(suggestedStickersListView)
            suggestedStickersListView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
            UIView.performWithoutAnimation {
                suggestedStickersPanel.layoutIfNeeded()
            }
        }

        suggestedStickersListView.items = suggestedStickerInfos.map { stickerInfo in
            StickerHorizontalListViewItemSticker(
                stickerInfo: stickerInfo,
                didSelectBlock: { [weak self] in
                    self?.didSelectSuggestedSticker(stickerInfo)
                },
                cache: suggestedStickerViewCache
            )
        }

        guard isSuggestedStickersPanelHidden else { return }

        isSuggestedStickersPanelHidden = false

        UIView.performWithoutAnimation {
            self.suggestedStickersListView.layoutIfNeeded()
            self.suggestedStickersListView.contentOffset = CGPoint(
                x: -self.suggestedStickersListView.contentInset.left,
                y: -self.suggestedStickersListView.contentInset.top
            )
        }

        guard animated else {
            updateSuggestedStickersPanelConstraints()
            return
        }

        isAnimatingHeightChange = true
        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.updateSuggestedStickersPanelConstraints()
            self.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            self.isAnimatingHeightChange = false
        }
        animator.startAnimation()
    }

    private func hideSuggestedStickersPanel(animated: Bool) {
        guard !isSuggestedStickersPanelHidden else { return }

        isSuggestedStickersPanelHidden = true

        guard animated else {
            updateSuggestedStickersPanelConstraints()
            return
        }

        isAnimatingHeightChange = true
        let animator = UIViewPropertyAnimator(
            duration: ConversationInputToolbar.heightChangeAnimationDuration,
            springDamping: 0.9,
            springResponse: 0.3
        )
        animator.addAnimations {
            self.updateSuggestedStickersPanelConstraints()
            self.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            self.isAnimatingHeightChange = false
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
        label.textColor = .Signal.label
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
        cancelString.addAttributeToEntireString(.foregroundColor, value: UIColor.Signal.secondaryLabel)
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
        if shouldShowEditUI {
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
            presentManageStickersView()
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

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // Probably because of a regression in iOS 26 `keyboardLayoutGuide`,
        // if first accessed in `calculateCustomKeyboardHeight`, would have an
        // incorrect height of 34 dp (amount of bottom safe area).
        // Accessing the layout guide before somehow fixes that issue.
        if #available(iOS 26, *), superview != nil {
            _ = keyboardLayoutGuide
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
            setSendButtonEnabled(textView.hasText)
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) { }
}

extension ConversationInputToolbar: StickerPickerDelegate {
    public func didSelectSticker(stickerInfo: StickerInfo) {
        AssertIsOnMainThread()
        inputToolbarDelegate?.sendSticker(stickerInfo)
    }

    public var storyStickerConfiguration: SignalUI.StoryStickerConfiguration {
        .hide
    }
}

extension ConversationInputToolbar: StickerPacksToolbarDelegate {
    public func presentManageStickersView() {
        AssertIsOnMainThread()
        inputToolbarDelegate?.presentManageStickersView()
    }
}

extension ConversationInputToolbar: AttachmentKeyboardDelegate {

    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment) {
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
