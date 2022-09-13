// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class InputView: UIView, InputViewButtonDelegate, InputTextViewDelegate, MentionSelectionViewDelegate {
    // MARK: - Variables
    
    private static let linkPreviewViewInset: CGFloat = 6

    private let threadVariant: SessionThread.Variant
    private weak var delegate: InputViewDelegate?
    
    var quoteDraftInfo: (model: QuotedReplyModel, isOutgoing: Bool)? { didSet { handleQuoteDraftChanged() } }
    var linkPreviewInfo: (url: String, draft: LinkPreviewDraft?)?
    private var voiceMessageRecordingView: VoiceMessageRecordingView?
    private lazy var mentionsViewHeightConstraint = mentionsView.set(.height, to: 0)

    private lazy var linkPreviewView: LinkPreviewView = {
        let maxWidth: CGFloat = (self.additionalContentContainer.bounds.width - InputView.linkPreviewViewInset)
        
        return LinkPreviewView(maxWidth: maxWidth) { [weak self] in
            self?.linkPreviewInfo = nil
            self?.additionalContentContainer.subviews.forEach { $0.removeFromSuperview() }
        }
    }()

    var text: String {
        get { inputTextView.text ?? "" }
        set { inputTextView.text = newValue }
    }
    
    var selectedRange: NSRange {
        get { inputTextView.selectedRange }
        set { inputTextView.selectedRange = newValue }
    }
    
    var inputTextViewIsFirstResponder: Bool { inputTextView.isFirstResponder }
    
    var enabledMessageTypes: MessageInputTypes = .all {
        didSet {
            setEnabledMessageTypes(enabledMessageTypes, message: nil)
        }
    }

    override var intrinsicContentSize: CGSize { CGSize.zero }
    var lastSearchedText: String? { nil }

    // MARK: - UI

    private var bottomStackView: UIStackView?
    private lazy var attachmentsButton = ExpandingAttachmentsButton(delegate: delegate)

    private lazy var voiceMessageButton: InputViewButton = {
        let result = InputViewButton(icon: #imageLiteral(resourceName: "Microphone"), delegate: self)
        result.accessibilityLabel = "VOICE_MESSAGE_TOO_SHORT_ALERT_TITLE".localized()
        result.accessibilityHint = "VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE".localized()
        
        return result
    }()

    private lazy var sendButton: InputViewButton = {
        let result = InputViewButton(icon: #imageLiteral(resourceName: "ArrowUp"), isSendButton: true, delegate: self)
        result.isHidden = true
        result.accessibilityLabel = "ATTACHMENT_APPROVAL_SEND_BUTTON".localized()
        
        return result
    }()
    private lazy var voiceMessageButtonContainer = container(for: voiceMessageButton)

    private lazy var mentionsView: MentionSelectionView = {
        let result: MentionSelectionView = MentionSelectionView()
        result.delegate = self
        
        return result
    }()

    private lazy var mentionsViewContainer: UIView = {
        let result: UIView = UIView()
        let backgroundView = UIView()
        backgroundView.themeBackgroundColor = .backgroundSecondary
        backgroundView.alpha = Values.lowOpacity
        result.addSubview(backgroundView)
        backgroundView.pin(to: result)
        
        let blurView: UIVisualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        result.addSubview(blurView)
        blurView.pin(to: result)
        result.alpha = 0
        
        return result
    }()

    private lazy var inputTextView: InputTextView = {
        // HACK: When restoring a draft the input text view won't have a frame yet, and therefore it won't
        // be able to calculate what size it should be to accommodate the draft text. As a workaround, we
        // just calculate the max width that the input text view is allowed to be and pass it in. See
        // setUpViewHierarchy() for why these values are the way they are.
        let adjustment = (InputViewButton.expandedSize - InputViewButton.size) / 2
        let maxWidth = UIScreen.main.bounds.width - 2 * InputViewButton.expandedSize - 2 * Values.smallSpacing - 2 * (Values.mediumSpacing - adjustment)
        return InputTextView(delegate: self, maxWidth: maxWidth)
    }()

    private lazy var disabledInputLabel: UILabel = {
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Values.smallFontSize)
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        label.alpha = 0

        return label
    }()

    private lazy var additionalContentContainer = UIView()

    // MARK: - Initialization
    
    init(threadVariant: SessionThread.Variant, delegate: InputViewDelegate) {
        self.threadVariant = threadVariant
        self.delegate = delegate
        
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(delegate:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(delegate:) instead.")
    }

    private func setUpViewHierarchy() {
        autoresizingMask = .flexibleHeight
        
        // Background & blur
        let backgroundView = UIView()
        backgroundView.themeBackgroundColor = .backgroundSecondary
        backgroundView.alpha = Values.lowOpacity
        addSubview(backgroundView)
        backgroundView.pin(to: self)
        
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        addSubview(blurView)
        blurView.pin(to: self)
        
        // Separator
        let separator = UIView()
        separator.themeBackgroundColor = .borderSeparator
        separator.set(.height, to: Values.separatorThickness)
        addSubview(separator)
        separator.pin([ UIView.HorizontalEdge.leading, UIView.VerticalEdge.top, UIView.HorizontalEdge.trailing ], to: self)
        
        // Bottom stack view
        let bottomStackView = UIStackView(arrangedSubviews: [ attachmentsButton, inputTextView, container(for: sendButton) ])
        bottomStackView.axis = .horizontal
        bottomStackView.spacing = Values.smallSpacing
        bottomStackView.alignment = .center
        self.bottomStackView = bottomStackView
        
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ additionalContentContainer, bottomStackView ])
        mainStackView.axis = .vertical
        mainStackView.isLayoutMarginsRelativeArrangement = true
        
        let adjustment = (InputViewButton.expandedSize - InputViewButton.size) / 2
        mainStackView.layoutMargins = UIEdgeInsets(top: 2, leading: Values.mediumSpacing - adjustment, bottom: 2, trailing: Values.mediumSpacing - adjustment)
        addSubview(mainStackView)
        mainStackView.pin(.top, to: .bottom, of: separator)
        mainStackView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing ], to: self)
        mainStackView.pin(.bottom, to: .bottom, of: self)

        addSubview(disabledInputLabel)

        disabledInputLabel.pin(.top, to: .top, of: mainStackView)
        disabledInputLabel.pin(.left, to: .left, of: mainStackView)
        disabledInputLabel.pin(.right, to: .right, of: mainStackView)
        disabledInputLabel.set(.height, to: InputViewButton.expandedSize)

        // Mentions
        insertSubview(mentionsViewContainer, belowSubview: mainStackView)
        mentionsViewContainer.pin([ UIView.HorizontalEdge.left, UIView.HorizontalEdge.right ], to: self)
        mentionsViewContainer.pin(.bottom, to: .top, of: self)
        mentionsViewContainer.addSubview(mentionsView)
        mentionsView.pin(to: mentionsViewContainer)
        mentionsViewHeightConstraint.isActive = true
        
        // Voice message button
        addSubview(voiceMessageButtonContainer)
        voiceMessageButtonContainer.center(in: sendButton)
    }

    // MARK: - Updating
    
    func inputTextViewDidChangeSize(_ inputTextView: InputTextView) {
        invalidateIntrinsicContentSize()
    }

    func inputTextViewDidChangeContent(_ inputTextView: InputTextView) {
        let hasText = !text.isEmpty
        sendButton.isHidden = !hasText
        voiceMessageButtonContainer.isHidden = hasText
        autoGenerateLinkPreviewIfPossible()
        delegate?.inputTextViewDidChangeContent(inputTextView)
    }

    func didPasteImageFromPasteboard(_ inputTextView: InputTextView, image: UIImage) {
        delegate?.didPasteImageFromPasteboard(image)
    }

    // We want to show either a link preview or a quote draft, but never both at the same time. When trying to
    // generate a link preview, wait until we're sure that we'll be able to build a link preview from the given
    // URL before removing the quote draft.

    private func handleQuoteDraftChanged() {
        additionalContentContainer.subviews.forEach { $0.removeFromSuperview() }
        linkPreviewInfo = nil
        
        guard let quoteDraftInfo = quoteDraftInfo else { return }
        
        let hInset: CGFloat = 6 // Slight visual adjustment
        let maxWidth = additionalContentContainer.bounds.width
        
        let quoteView: QuoteView = QuoteView(
            for: .draft,
            authorId: quoteDraftInfo.model.authorId,
            quotedText: quoteDraftInfo.model.body,
            threadVariant: threadVariant,
            currentUserPublicKey: nil,
            currentUserBlindedPublicKey: nil,
            direction: (quoteDraftInfo.isOutgoing ? .outgoing : .incoming),
            attachment: quoteDraftInfo.model.attachment,
            hInset: hInset,
            maxWidth: maxWidth
        ) { [weak self] in
            self?.quoteDraftInfo = nil
        }
        
        additionalContentContainer.addSubview(quoteView)
        quoteView.pin(.left, to: .left, of: additionalContentContainer, withInset: hInset)
        quoteView.pin(.top, to: .top, of: additionalContentContainer, withInset: 12)
        quoteView.pin(.right, to: .right, of: additionalContentContainer, withInset: -hInset)
        quoteView.pin(.bottom, to: .bottom, of: additionalContentContainer, withInset: -6)
    }

    private func autoGenerateLinkPreviewIfPossible() {
        // Don't allow link previews on 'none' or 'textOnly' input
        guard enabledMessageTypes == .all else { return }

        // Suggest that the user enable link previews if they haven't already and we haven't
        // told them about link previews yet
        let text = inputTextView.text!
        let areLinkPreviewsEnabled: Bool = Storage.shared[.areLinkPreviewsEnabled]
        
        if
            !LinkPreview.allPreviewUrls(forMessageBodyText: text).isEmpty &&
            !areLinkPreviewsEnabled &&
            !UserDefaults.standard[.hasSeenLinkPreviewSuggestion]
        {
            delegate?.showLinkPreviewSuggestionModal()
            UserDefaults.standard[.hasSeenLinkPreviewSuggestion] = true
            return
        }
        // Check that link previews are enabled
        guard areLinkPreviewsEnabled else { return }
        
        // Proceed
        autoGenerateLinkPreview()
    }

    func autoGenerateLinkPreview() {
        // Check that a valid URL is present
        guard let linkPreviewURL = LinkPreview.previewUrl(for: text, selectedRange: inputTextView.selectedRange) else {
            return
        }
        
        // Guard against obsolete updates
        guard linkPreviewURL != self.linkPreviewInfo?.url else { return }
        
        // Clear content container
        additionalContentContainer.subviews.forEach { $0.removeFromSuperview() }
        quoteDraftInfo = nil
        
        // Set the state to loading
        linkPreviewInfo = (url: linkPreviewURL, draft: nil)
        linkPreviewView.update(with: LinkPreview.LoadingState(), isOutgoing: false)

        // Add the link preview view
        additionalContentContainer.addSubview(linkPreviewView)
        linkPreviewView.pin(.left, to: .left, of: additionalContentContainer, withInset: InputView.linkPreviewViewInset)
        linkPreviewView.pin(.top, to: .top, of: additionalContentContainer, withInset: 10)
        linkPreviewView.pin(.right, to: .right, of: additionalContentContainer)
        linkPreviewView.pin(.bottom, to: .bottom, of: additionalContentContainer, withInset: -4)
        
        // Build the link preview
        LinkPreview.tryToBuildPreviewInfo(previewUrl: linkPreviewURL)
            .done { [weak self] draft in
                guard self?.linkPreviewInfo?.url == linkPreviewURL else { return } // Obsolete
                
                self?.linkPreviewInfo = (url: linkPreviewURL, draft: draft)
                self?.linkPreviewView.update(with: LinkPreview.DraftState(linkPreviewDraft: draft), isOutgoing: false)
            }
            .catch { [weak self] _ in
                guard self?.linkPreviewInfo?.url == linkPreviewURL else { return } // Obsolete
                
                self?.linkPreviewInfo = nil
                self?.additionalContentContainer.subviews.forEach { $0.removeFromSuperview() }
            }
            .retainUntilComplete()
    }

    func setEnabledMessageTypes(_ messageTypes: MessageInputTypes, message: String?) {
        guard enabledMessageTypes != messageTypes else { return }

        enabledMessageTypes = messageTypes
        disabledInputLabel.text = (message ?? "")

        attachmentsButton.isUserInteractionEnabled = (messageTypes == .all)
        voiceMessageButton.isUserInteractionEnabled = (messageTypes == .all)

        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.bottomStackView?.alpha = (messageTypes != .none ? 1 : 0)
            self?.attachmentsButton.alpha = (messageTypes == .all ?
                1 :
                (messageTypes == .textOnly ? 0.4 : 0)
            )
            self?.voiceMessageButton.alpha =  (messageTypes == .all ?
                1 :
                (messageTypes == .textOnly ? 0.4 : 0)
            )
            self?.disabledInputLabel.alpha = (messageTypes != .none ? 0 : Values.mediumOpacity)
        }
    }

    // MARK: - Interaction
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Needed so that the user can tap the buttons when the expanding attachments button is expanded
        let buttonContainers = [ attachmentsButton.mainButton, attachmentsButton.cameraButton,
            attachmentsButton.libraryButton, attachmentsButton.documentButton, attachmentsButton.gifButton ]
        
        if let buttonContainer: InputViewButton = buttonContainers.first(where: { $0.superview?.convert($0.frame, to: self).contains(point) == true }) {
            return buttonContainer
        }
        
        return super.hitTest(point, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let buttonContainers = [ attachmentsButton.gifButtonContainer, attachmentsButton.documentButtonContainer,
            attachmentsButton.libraryButtonContainer, attachmentsButton.cameraButtonContainer, attachmentsButton.mainButtonContainer ]
        let isPointInsideAttachmentsButton = buttonContainers
            .contains { $0.superview!.convert($0.frame, to: self).contains(point) }
        
        if isPointInsideAttachmentsButton {
            // Needed so that the user can tap the buttons when the expanding attachments button is expanded
            return true
        }
        
        if mentionsViewContainer.frame.contains(point) {
            // Needed so that the user can tap mentions
            return true
        }
        
        return super.point(inside: point, with: event)
    }

    func handleInputViewButtonTapped(_ inputViewButton: InputViewButton) {
        if inputViewButton == sendButton { delegate?.handleSendButtonTapped() }
    }

    func handleInputViewButtonLongPressBegan(_ inputViewButton: InputViewButton?) {
        guard inputViewButton == voiceMessageButton else { return }
        
        delegate?.startVoiceMessageRecording()
        showVoiceMessageUI()
    }

    func handleInputViewButtonLongPressMoved(_ inputViewButton: InputViewButton, with touch: UITouch) {
        guard let voiceMessageRecordingView = voiceMessageRecordingView, inputViewButton == voiceMessageButton else { return }
        let location = touch.location(in: voiceMessageRecordingView)
        voiceMessageRecordingView.handleLongPressMoved(to: location)
    }

    func handleInputViewButtonLongPressEnded(_ inputViewButton: InputViewButton, with touch: UITouch) {
        guard let voiceMessageRecordingView = voiceMessageRecordingView, inputViewButton == voiceMessageButton else { return }
        let location = touch.location(in: voiceMessageRecordingView)
        voiceMessageRecordingView.handleLongPressEnded(at: location)
    }

    override func resignFirstResponder() -> Bool {
        inputTextView.resignFirstResponder()
    }
    
    func inputTextViewBecomeFirstResponder() {
        inputTextView.becomeFirstResponder()
    }

    func handleLongPress(_ gestureRecognizer: UITapGestureRecognizer) {
        // Not relevant in this case
    }

    @objc private func showVoiceMessageUI() {
        voiceMessageRecordingView?.removeFromSuperview()
        let voiceMessageButtonFrame = voiceMessageButton.superview!.convert(voiceMessageButton.frame, to: self)
        let voiceMessageRecordingView = VoiceMessageRecordingView(voiceMessageButtonFrame: voiceMessageButtonFrame, delegate: delegate)
        voiceMessageRecordingView.alpha = 0
        addSubview(voiceMessageRecordingView)
        voiceMessageRecordingView.pin(to: self)
        self.voiceMessageRecordingView = voiceMessageRecordingView
        voiceMessageRecordingView.animate()
        let allOtherViews = [ attachmentsButton, sendButton, inputTextView, additionalContentContainer ]
        UIView.animate(withDuration: 0.25) {
            allOtherViews.forEach { $0.alpha = 0 }
        }
    }

    func hideVoiceMessageUI() {
        let allOtherViews = [ attachmentsButton, sendButton, inputTextView, additionalContentContainer ]
        UIView.animate(withDuration: 0.25, animations: {
            allOtherViews.forEach { $0.alpha = 1 }
            self.voiceMessageRecordingView?.alpha = 0
        }, completion: { _ in
            self.voiceMessageRecordingView?.removeFromSuperview()
            self.voiceMessageRecordingView = nil
        })
    }

    func hideMentionsUI() {
        UIView.animate(
            withDuration: 0.25,
            animations: { [weak self] in
                self?.mentionsViewContainer.alpha = 0
            },
            completion: { [weak self] _ in
                self?.mentionsViewHeightConstraint.constant = 0
                self?.mentionsView.contentOffset = CGPoint.zero
            }
        )
    }

    func showMentionsUI(for candidates: [ConversationViewModel.MentionInfo]) {
        mentionsView.candidates = candidates
        
        let mentionCellHeight = (Values.smallProfilePictureSize + 2 * Values.smallSpacing)
        mentionsViewHeightConstraint.constant = CGFloat(min(3, candidates.count)) * mentionCellHeight
        layoutIfNeeded()
        
        UIView.animate(withDuration: 0.25) {
            self.mentionsViewContainer.alpha = 1
        }
    }

    func handleMentionSelected(_ mentionInfo: ConversationViewModel.MentionInfo, from view: MentionSelectionView) {
        delegate?.handleMentionSelected(mentionInfo, from: view)
    }
    
    func tapableLabel(_ label: TappableLabel, didTapUrl url: String, atRange range: NSRange) {
        // Do nothing
    }

    // MARK: - Convenience
    
    private func container(for button: InputViewButton) -> UIView {
        let result: UIView = UIView()
        result.addSubview(button)
        result.set(.width, to: InputViewButton.expandedSize)
        result.set(.height, to: InputViewButton.expandedSize)
        button.center(in: result)
        
        return result
    }
}

// MARK: - Delegate

protocol InputViewDelegate: ExpandingAttachmentsButtonDelegate, VoiceMessageRecordingViewDelegate {
    func showLinkPreviewSuggestionModal()
    func handleSendButtonTapped()
    func inputTextViewDidChangeContent(_ inputTextView: InputTextView)
    func handleMentionSelected(_ mentionInfo: ConversationViewModel.MentionInfo, from view: MentionSelectionView)
    func didPasteImageFromPasteboard(_ image: UIImage)
}
