
final class InputView : UIView, InputViewButtonDelegate, InputTextViewDelegate, QuoteViewDelegate, LinkPreviewViewV2Delegate {
    private let delegate: InputViewDelegate
    var quoteDraftInfo: (model: OWSQuotedReplyModel, isOutgoing: Bool)? { didSet { handleQuoteDraftChanged() } }
    var linkPreviewInfo: (url: String, draft: OWSLinkPreviewDraft?)?
    private var voiceMessageRecordingView: VoiceMessageRecordingView?

    private lazy var linkPreviewView: LinkPreviewViewV2 = {
        let maxWidth = self.additionalContentContainer.bounds.width - InputView.linkPreviewViewInset
        return LinkPreviewViewV2(for: nil, maxWidth: maxWidth, delegate: self)
    }()

    var text: String {
        get { inputTextView.text }
        set { inputTextView.text = newValue }
    }
    
    override var intrinsicContentSize: CGSize { CGSize.zero }
    
    // MARK: UI Components
    private lazy var cameraButton = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_camera_black"), delegate: self)
    private lazy var libraryButton = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_camera_roll_black"), delegate: self)
    private lazy var gifButton = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_gif_black"), delegate: self)
    private lazy var documentButton = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_document_black"), delegate: self)
    private lazy var voiceMessageButton = InputViewButton(icon: #imageLiteral(resourceName: "Microphone"), delegate: self)
    private lazy var sendButton: InputViewButton = {
        let result = InputViewButton(icon: #imageLiteral(resourceName: "ArrowUp"), isSendButton: true, delegate: self)
        result.isHidden = true
        return result
    }()
    private lazy var voiceMessageButtonContainer = container(for: voiceMessageButton)
    
    private lazy var inputTextView = InputTextView(delegate: self)

    private lazy var additionalContentContainer: UIView = {
        let result = UIView()
        result.heightAnchor.constraint(greaterThanOrEqualToConstant: 4).isActive = true
        return result
    }()

    // MARK: Settings
    private static let linkPreviewViewInset: CGFloat = 6
    
    // MARK: Lifecycle
    init(delegate: InputViewDelegate) {
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
        backgroundView.backgroundColor = isLightMode ? .white : .black
        backgroundView.alpha = Values.lowOpacity
        addSubview(backgroundView)
        backgroundView.pin(to: self)
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        addSubview(blurView)
        blurView.pin(to: self)
        // Separator
        let separator = UIView()
        separator.backgroundColor = Colors.text.withAlphaComponent(0.2)
        separator.set(.height, to: 1 / UIScreen.main.scale)
        addSubview(separator)
        separator.pin([ UIView.HorizontalEdge.leading, UIView.VerticalEdge.top, UIView.HorizontalEdge.trailing ], to: self)
        // Buttons
        let (cameraButtonContainer, libraryButtonContainer, gifButtonContainer, documentButtonContainer) = (container(for: cameraButton), container(for: libraryButton), container(for: gifButton), container(for: documentButton))
        let buttonStackView = UIStackView(arrangedSubviews: [ cameraButtonContainer, libraryButtonContainer, gifButtonContainer, documentButtonContainer, UIView.hStretchingSpacer() ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.smallSpacing
        // Bottom stack view
        let bottomStackView = UIStackView(arrangedSubviews: [ inputTextView, container(for: sendButton) ])
        bottomStackView.axis = .horizontal
        bottomStackView.spacing = Values.smallSpacing
        bottomStackView.alignment = .center
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ buttonStackView, additionalContentContainer, bottomStackView ])
        mainStackView.axis = .vertical
        mainStackView.isLayoutMarginsRelativeArrangement = true
        let adjustment = (InputViewButton.expandedSize - InputViewButton.size) / 2
        mainStackView.layoutMargins = UIEdgeInsets(top: Values.smallSpacing, leading: Values.largeSpacing, bottom: Values.smallSpacing, trailing: Values.largeSpacing - adjustment)
        addSubview(mainStackView)
        mainStackView.pin(.top, to: .bottom, of: separator)
        mainStackView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing ], to: self)
        mainStackView.pin(.bottom, to: .bottom, of: self, withInset: -2)
        // Voice message button
        addSubview(voiceMessageButtonContainer)
        voiceMessageButtonContainer.center(in: sendButton)
    }
    
    // MARK: Updating
    func inputTextViewDidChangeSize(_ inputTextView: InputTextView) {
        invalidateIntrinsicContentSize()
    }

    func inputTextViewDidChangeContent(_ inputTextView: InputTextView) {
        let hasText = !text.isEmpty
        sendButton.isHidden = !hasText
        voiceMessageButtonContainer.isHidden = hasText
        autoGenerateLinkPreviewIfPossible()
    }

    private func handleQuoteDraftChanged() {
        additionalContentContainer.subviews.forEach { $0.removeFromSuperview() }
        linkPreviewInfo = nil
        guard let quoteDraftInfo = quoteDraftInfo else { return }
        let direction: QuoteView.Direction = quoteDraftInfo.isOutgoing ? .outgoing : .incoming
        let hInset: CGFloat = 6
        let maxWidth = additionalContentContainer.bounds.width
        let quoteView = QuoteView(for: quoteDraftInfo.model, direction: direction, hInset: hInset, maxWidth: maxWidth, delegate: self)
        additionalContentContainer.addSubview(quoteView)
        quoteView.pin(.left, to: .left, of: additionalContentContainer, withInset: hInset)
        quoteView.pin(.top, to: .top, of: additionalContentContainer, withInset: 12)
        quoteView.pin(.right, to: .right, of: additionalContentContainer, withInset: -hInset)
        quoteView.pin(.bottom, to: .bottom, of: additionalContentContainer, withInset: -6)
    }

    private func autoGenerateLinkPreviewIfPossible() {
        additionalContentContainer.subviews.forEach { $0.removeFromSuperview() }
        quoteDraftInfo = nil
        // Suggest that the user enable link previews if they haven't already and we haven't
        // told them about link previews yet
        let text = inputTextView.text!
        let userDefaults = UserDefaults.standard
        if !OWSLinkPreview.allPreviewUrls(forMessageBodyText: text).isEmpty && !SSKPreferences.areLinkPreviewsEnabled
            && !userDefaults[.hasSeenLinkPreviewSuggestion] {
            delegate.showLinkPreviewSuggestionModal()
            userDefaults[.hasSeenLinkPreviewSuggestion] = true
            return
        }
        // Check that link previews are enabled
        guard SSKPreferences.areLinkPreviewsEnabled else { return }
        // Proceed
        autoGenerateLinkPreview()
    }

    func autoGenerateLinkPreview() {
        // Check that a valid URL is present
        guard let linkPreviewURL = OWSLinkPreview.previewUrl(forRawBodyText: text, selectedRange: inputTextView.selectedRange) else {
            return
        }
        // Guard against obsolete updates
        guard linkPreviewURL != self.linkPreviewInfo?.url else { return }
        // Set the state to loading
        linkPreviewInfo = (url: linkPreviewURL, draft: nil)
        linkPreviewView.linkPreviewState = LinkPreviewLoading()
        // Add the link preview view
        additionalContentContainer.addSubview(linkPreviewView)
        linkPreviewView.pin(.left, to: .left, of: additionalContentContainer, withInset: InputView.linkPreviewViewInset)
        linkPreviewView.pin(.top, to: .top, of: additionalContentContainer, withInset: 10)
        linkPreviewView.pin(.right, to: .right, of: additionalContentContainer)
        linkPreviewView.pin(.bottom, to: .bottom, of: additionalContentContainer, withInset: -4)
        // Build the link preview
        OWSLinkPreview.tryToBuildPreviewInfo(previewUrl: linkPreviewURL).done { [weak self] draft in
            guard let self = self else { return }
            guard self.linkPreviewInfo?.url == linkPreviewURL else { return } // Obsolete
            self.linkPreviewInfo = (url: linkPreviewURL, draft: draft)
            self.linkPreviewView.linkPreviewState = LinkPreviewDraft(linkPreviewDraft: draft)
        }.catch { _ in
            guard self.linkPreviewInfo?.url == linkPreviewURL else { return } // Obsolete
            self.linkPreviewInfo = nil
            self.additionalContentContainer.subviews.forEach { $0.removeFromSuperview() }
        }.retainUntilComplete()
    }
    
    // MARK: Interaction
    func handleInputViewButtonTapped(_ inputViewButton: InputViewButton) {
        if inputViewButton == cameraButton { delegate.handleCameraButtonTapped() }
        if inputViewButton == libraryButton { delegate.handleLibraryButtonTapped() }
        if inputViewButton == gifButton { delegate.handleGIFButtonTapped() }
        if inputViewButton == documentButton { delegate.handleDocumentButtonTapped() }
        if inputViewButton == sendButton { delegate.handleSendButtonTapped() }
    }

    func handleInputViewButtonLongPressBegan(_ inputViewButton: InputViewButton) {
        guard inputViewButton == voiceMessageButton else { return }
        delegate.startVoiceMessageRecording()
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

    func handleQuoteViewCancelButtonTapped() {
        delegate.handleQuoteViewCancelButtonTapped()
    }

    override func resignFirstResponder() -> Bool {
        inputTextView.resignFirstResponder()
    }

    func handleLongPress() {
        // Not relevant in this case
    }

    func handleLinkPreviewCanceled() {
        linkPreviewInfo = nil
        additionalContentContainer.subviews.forEach { $0.removeFromSuperview() }
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
        let allOtherViews = [ cameraButton, libraryButton, gifButton, documentButton, sendButton, inputTextView, additionalContentContainer ]
        UIView.animate(withDuration: 0.25) {
            allOtherViews.forEach { $0.alpha = 0 }
        }
    }

    func hideVoiceMessageUI() {
        let allOtherViews = [ cameraButton, libraryButton, gifButton, documentButton, sendButton, inputTextView, additionalContentContainer ]
        UIView.animate(withDuration: 0.25, animations: {
            allOtherViews.forEach { $0.alpha = 1 }
            self.voiceMessageRecordingView?.alpha = 0
        }, completion: { _ in
            self.voiceMessageRecordingView?.removeFromSuperview()
            self.voiceMessageRecordingView = nil
        })
    }

    // MARK: Convenience
    private func container(for button: InputViewButton) -> UIView {
        let result = UIView()
        result.addSubview(button)
        result.set(.width, to: InputViewButton.expandedSize)
        result.set(.height, to: InputViewButton.expandedSize)
        button.center(in: result)
        return result
    }
}

// MARK: Delegate
protocol InputViewDelegate : VoiceMessageRecordingViewDelegate {

    func showLinkPreviewSuggestionModal()
    func handleCameraButtonTapped()
    func handleLibraryButtonTapped()
    func handleGIFButtonTapped()
    func handleDocumentButtonTapped()
    func handleSendButtonTapped()
    func handleQuoteViewCancelButtonTapped()
}
