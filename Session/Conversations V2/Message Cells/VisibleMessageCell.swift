
final class VisibleMessageCell : MessageCell {
    private var unloadContent: (() -> Void)?
    var albumView: MediaAlbumView?
    var mediaTextOverlayView: MediaTextOverlayView?
    // Constraints
    private lazy var headerViewTopConstraint = headerView.pin(.top, to: .top, of: self, withInset: 1)
    private lazy var profilePictureViewLeftConstraint = profilePictureView.pin(.left, to: .left, of: self, withInset: VisibleMessageCell.groupThreadHSpacing)
    private lazy var profilePictureViewWidthConstraint = profilePictureView.set(.width, to: Values.verySmallProfilePictureSize)
    private lazy var bubbleViewLeftConstraint1 = bubbleView.pin(.left, to: .right, of: profilePictureView, withInset: VisibleMessageCell.groupThreadHSpacing)
    private lazy var bubbleViewLeftConstraint2 = bubbleView.leftAnchor.constraint(greaterThanOrEqualTo: leftAnchor, constant: VisibleMessageCell.gutterSize)
    private lazy var bubbleViewTopConstraint = bubbleView.pin(.top, to: .bottom, of: authorLabel, withInset: VisibleMessageCell.authorLabelBottomSpacing)
    private lazy var bubbleViewRightConstraint1 = bubbleView.pin(.right, to: .right, of: self, withInset: -VisibleMessageCell.contactThreadHSpacing)
    private lazy var bubbleViewRightConstraint2 = bubbleView.rightAnchor.constraint(lessThanOrEqualTo: rightAnchor, constant: -VisibleMessageCell.gutterSize)
    private lazy var messageStatusImageViewTopConstraint = messageStatusImageView.pin(.top, to: .bottom, of: bubbleView, withInset: 0)
    private lazy var messageStatusImageViewWidthConstraint = messageStatusImageView.set(.width, to: VisibleMessageCell.messageStatusImageViewSize)
    private lazy var messageStatusImageViewHeightConstraint = messageStatusImageView.set(.height, to: VisibleMessageCell.messageStatusImageViewSize)
    
    private var positionInCluster: Position? {
        guard let viewItem = viewItem else { return nil }
        if viewItem.isFirstInCluster { return .top }
        if viewItem.isLastInCluster { return .bottom }
        return .middle
    }
    
    private var isOnlyMessageInCluster: Bool { viewItem?.isFirstInCluster == true && viewItem?.isLastInCluster == true }
    
    private var direction: Direction {
        guard let message = viewItem?.interaction as? TSMessage else { preconditionFailure() }
        switch message {
        case is TSIncomingMessage: return .incoming
        case is TSOutgoingMessage: return .outgoing
        default: preconditionFailure()
        }
    }
    
    private var shouldInsetHeader: Bool {
        guard let viewItem = viewItem else { preconditionFailure() }
        return (positionInCluster == .top || isOnlyMessageInCluster) && !viewItem.wasPreviousItemInfoMessage
    }
    
    // MARK: UI Components
    private lazy var profilePictureView: ProfilePictureView = {
        let result = ProfilePictureView()
        let size = Values.verySmallProfilePictureSize
        result.set(.height, to: size)
        result.size = size
        return result
    }()
    
    lazy var bubbleView: UIView = {
        let result = UIView()
        result.layer.cornerRadius = VisibleMessageCell.smallCornerRadius
        return result
    }()
    
    private let bubbleViewMaskLayer = CAShapeLayer()
    
    private lazy var headerView = UIView()
    
    private lazy var authorLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        return result
    }()
    
    private lazy var snContentView = UIView()
    
    private lazy var messageStatusImageView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFit
        result.layer.cornerRadius = VisibleMessageCell.messageStatusImageViewSize / 2
        result.layer.masksToBounds = true
        return result
    }()
    
    // MARK: Settings
    private static let messageStatusImageViewSize: CGFloat = 16
    private static let authorLabelBottomSpacing: CGFloat = 4
    private static let groupThreadHSpacing: CGFloat = 12
    private static let profilePictureSize = Values.verySmallProfilePictureSize
    static let smallCornerRadius: CGFloat = 4
    static let largeCornerRadius: CGFloat = 18
    static let contactThreadHSpacing = Values.mediumSpacing
    
    static var gutterSize: CGFloat { groupThreadHSpacing + profilePictureSize + groupThreadHSpacing }
    
    private var bodyLabelTextColor: UIColor {
        switch (direction, AppModeManager.shared.currentAppMode) {
        case (.outgoing, .dark), (.incoming, .light): return .black
        default: return .white
        }
    }
    
    override class var identifier: String { "VisibleMessageCell" }
    
    // MARK: Direction & Position
    enum Direction { case incoming, outgoing }
    enum Position { case top, middle, bottom }
    
    // MARK: Lifecycle
    override func setUpViewHierarchy() {
        super.setUpViewHierarchy()
        isUserInteractionEnabled = true
        // Header view
        addSubview(headerView)
        headerViewTopConstraint.isActive = true
        headerView.pin([ UIView.HorizontalEdge.left, UIView.HorizontalEdge.right ], to: self)
        // Author label
        addSubview(authorLabel)
        authorLabel.pin(.top, to: .bottom, of: headerView)
        // Profile picture view
        addSubview(profilePictureView)
        profilePictureViewLeftConstraint.isActive = true
        profilePictureViewWidthConstraint.isActive = true
        profilePictureView.pin(.bottom, to: .bottom, of: self, withInset: -1)
        // Bubble view
        addSubview(bubbleView)
        bubbleViewLeftConstraint1.isActive = true
        bubbleViewTopConstraint.isActive = true
        bubbleViewRightConstraint1.isActive = true
        // Content view
        bubbleView.addSubview(snContentView)
        snContentView.pin(to: bubbleView)
        // Message status image view
        addSubview(messageStatusImageView)
        messageStatusImageViewTopConstraint.isActive = true
        messageStatusImageView.pin(.right, to: .right, of: bubbleView, withInset: -1)
        messageStatusImageView.pin(.bottom, to: .bottom, of: self, withInset: -1)
        messageStatusImageViewWidthConstraint.isActive = true
        messageStatusImageViewHeightConstraint.isActive = true
        // Remaining constraints
        authorLabel.pin(.left, to: .left, of: bubbleView, withInset: 12)
    }
    
    override func setUpGestureRecognizers() {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        addGestureRecognizer(longPressRecognizer)
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGestureRecognizer.numberOfTapsRequired = 1
        addGestureRecognizer(tapGestureRecognizer)
        let doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGestureRecognizer)
        tapGestureRecognizer.require(toFail: doubleTapGestureRecognizer)
    }
    
    // MARK: Updating
    override func update() {
        guard let viewItem = viewItem, let message = viewItem.interaction as? TSMessage else { return }
        let thread = message.thread
        let isGroupThread = thread.isGroupThread()
        // Profile picture view
        profilePictureViewLeftConstraint.constant = isGroupThread ? VisibleMessageCell.groupThreadHSpacing : 0
        profilePictureViewWidthConstraint.constant = isGroupThread ? VisibleMessageCell.profilePictureSize : 0
        let senderSessionID = (message as? TSIncomingMessage)?.authorId
        profilePictureView.isHidden = !VisibleMessageCell.shouldShowProfilePicture(for: viewItem)
        if let senderSessionID = senderSessionID {
            profilePictureView.update(for: senderSessionID)
        }
        // Bubble view
        bubbleViewLeftConstraint1.isActive = (direction == .incoming)
        bubbleViewLeftConstraint1.constant = isGroupThread ? VisibleMessageCell.groupThreadHSpacing : VisibleMessageCell.contactThreadHSpacing
        bubbleViewLeftConstraint2.isActive = (direction == .outgoing)
        bubbleViewTopConstraint.constant = (viewItem.senderName == nil) ? 0 : VisibleMessageCell.authorLabelBottomSpacing
        bubbleViewRightConstraint1.isActive = (direction == .outgoing)
        bubbleViewRightConstraint2.isActive = (direction == .incoming)
        bubbleView.backgroundColor = (direction == .incoming) ? Colors.receivedMessageBackground : Colors.sentMessageBackground
        updateBubbleViewCorners()
        // Content view
        populateContentView(for: viewItem)
        // Date break
        headerViewTopConstraint.constant = shouldInsetHeader ? Values.mediumSpacing : 1
        headerView.subviews.forEach { $0.removeFromSuperview() }
        if viewItem.shouldShowDate {
            populateHeader(for: viewItem)
        }
        // Author label
        authorLabel.textColor = Colors.text
        authorLabel.isHidden = (viewItem.senderName == nil)
        authorLabel.text = viewItem.senderName?.string // Will only be set if it should be shown
        // Message status image view
        let (image, backgroundColor) = getMessageStatusImage(for: message)
        messageStatusImageView.image = image
        messageStatusImageView.backgroundColor = backgroundColor
        if let message = message as? TSOutgoingMessage {
            messageStatusImageView.isHidden = (message.messageState == .sent && message.thread.lastInteraction != message)
        } else {
            messageStatusImageView.isHidden = true
        }
        messageStatusImageViewTopConstraint.constant = (messageStatusImageView.isHidden) ? 0 : 5
        [ messageStatusImageViewWidthConstraint, messageStatusImageViewHeightConstraint ].forEach {
            $0.constant = (messageStatusImageView.isHidden) ? 0 : VisibleMessageCell.messageStatusImageViewSize
        }
    }
    
    private func populateHeader(for viewItem: ConversationViewItem) {
        guard viewItem.shouldShowDate else { return }
        let dateBreakLabel = UILabel()
        dateBreakLabel.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        dateBreakLabel.textColor = Colors.text
        dateBreakLabel.textAlignment = .center
        let date = viewItem.interaction.receivedAtDate()
        let description = DateUtil.formatDate(forConversationDateBreaks: date)
        dateBreakLabel.text = description
        headerView.addSubview(dateBreakLabel)
        dateBreakLabel.pin(.top, to: .top, of: headerView, withInset: Values.smallSpacing)
        let additionalBottomInset = shouldInsetHeader ? Values.mediumSpacing : 1
        headerView.pin(.bottom, to: .bottom, of: dateBreakLabel, withInset: Values.smallSpacing + additionalBottomInset)
        dateBreakLabel.center(.horizontal, in: headerView)
    }
    
    private func populateContentView(for viewItem: ConversationViewItem) {
        snContentView.subviews.forEach { $0.removeFromSuperview() }
        albumView = nil
        mediaTextOverlayView = nil
        let isOutgoing = (viewItem.interaction.interactionType() == .outgoingMessage)
        switch viewItem.messageCellType {
        case .textOnlyMessage:
            guard let message = viewItem.interaction as? TSMessage else { return }
            let inset: CGFloat = 12
            // Stack view
            let stackView = UIStackView(arrangedSubviews: [])
            stackView.axis = .vertical
            stackView.spacing = 2
            // Quote label
            if viewItem.quotedReply != nil {
                let maxWidth = VisibleMessageCell.getMaxWidth(for: viewItem) - 2 * inset
                let direction: QuoteView.Direction = isOutgoing ? .outgoing : .incoming
                let hInset: CGFloat = 2
                let quoteView = QuoteView(for: viewItem, direction: direction, hInset: hInset, maxWidth: maxWidth)
                let quoteViewContainer = UIView(wrapping: quoteView, withInsets: UIEdgeInsets(top: 0, leading: hInset, bottom: 0, trailing: hInset))
                stackView.addArrangedSubview(quoteViewContainer)
            }
            // Body label
            let bodyLabel = UILabel()
            bodyLabel.numberOfLines = 0
            bodyLabel.lineBreakMode = .byWordWrapping
            bodyLabel.textColor = bodyLabelTextColor
            bodyLabel.font = .systemFont(ofSize: getFontSize(for: viewItem))
            bodyLabel.attributedText = given(message.body) { MentionUtilities.highlightMentions(in: $0, isOutgoingMessage: isOutgoing, threadID: viewItem.interaction.uniqueThreadId, attributes: [:]) }
            stackView.addArrangedSubview(bodyLabel)
            // Constraints
            snContentView.addSubview(stackView)
            stackView.pin(to: snContentView, withInset: inset)
        case .mediaMessage:
            guard let cache = delegate?.getMediaCache() else { preconditionFailure() }
            let maxMessageWidth = VisibleMessageCell.getMaxWidth(for: viewItem)
            let albumView = MediaAlbumView(mediaCache: cache, items: viewItem.mediaAlbumItems!, isOutgoing: isOutgoing, maxMessageWidth: maxMessageWidth)
            self.albumView = albumView
            snContentView.addSubview(albumView)
            let size = getSize(for: viewItem)
            albumView.set(.width, to: size.width)
            albumView.set(.height, to: size.height)
            albumView.pin(to: snContentView)
            albumView.loadMedia()
            albumView.layer.mask = bubbleViewMaskLayer
            if let message = viewItem.interaction as? TSMessage, let body = message.body, body.count > 0,
                let delegate = delegate { // delegate should always be set at this point
                let overlayView = MediaTextOverlayView(viewItem: viewItem, albumViewWidth: size.width, delegate: delegate)
                self.mediaTextOverlayView = overlayView
                snContentView.addSubview(overlayView)
                overlayView.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.bottom, UIView.HorizontalEdge.right ], to: snContentView)
            }
            unloadContent = { albumView.unloadMedia() }
        case .audio:
            let voiceMessageView = VoiceMessageViewV2(viewItem: viewItem)
            snContentView.addSubview(voiceMessageView)
            voiceMessageView.pin(to: snContentView)
            viewItem.lastAudioMessageView = voiceMessageView
        case .genericAttachment:
            let documentView = DocumentView(viewItem: viewItem, textColor: bodyLabelTextColor)
            snContentView.addSubview(documentView)
            documentView.pin(to: snContentView)
        default: return
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateBubbleViewCorners()
    }
    
    private func updateBubbleViewCorners() {
        let maskPath = UIBezierPath(roundedRect: bubbleView.bounds, byRoundingCorners: getCornersToRound(),
            cornerRadii: CGSize(width: VisibleMessageCell.largeCornerRadius, height: VisibleMessageCell.largeCornerRadius))
        bubbleViewMaskLayer.path = maskPath.cgPath
        bubbleView.layer.mask = bubbleViewMaskLayer
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        unloadContent?()
    }
    
    // MARK: Interaction
    @objc private func handleLongPress() {
        guard let viewItem = viewItem else { return }
        delegate?.handleViewItemLongPressed(viewItem)
    }

    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let viewItem = viewItem else { return }
        delegate?.handleViewItemTapped(viewItem, gestureRecognizer: gestureRecognizer)
    }

    @objc private func handleDoubleTap() {
        guard let viewItem = viewItem else { return }
        delegate?.handleViewItemDoubleTapped(viewItem)
    }
    
    // MARK: Convenience
    private func getCornersToRound() -> UIRectCorner {
        guard !isOnlyMessageInCluster else { return .allCorners }
        let result: UIRectCorner
        switch (positionInCluster, direction) {
        case (.top, .outgoing): result = [ .bottomLeft, .topLeft, .topRight ]
        case (.middle, .outgoing): result = [ .bottomLeft, .topLeft ]
        case (.bottom, .outgoing): result = [ .bottomRight, .bottomLeft, .topLeft ]
        case (.top, .incoming): result = [ .topLeft, .topRight, .bottomRight ]
        case (.middle, .incoming): result = [ .topRight, .bottomRight ]
        case (.bottom, .incoming): result = [ .topRight, .bottomRight, .bottomLeft ]
        case (nil, _): result = .allCorners
        }
        return result
    }
    
    private func getFontSize(for viewItem: ConversationViewItem) -> CGFloat {
        let baselineFontSize = Values.mediumFontSize
        switch viewItem.displayableBodyText?.jumbomojiCount {
        case 1: return baselineFontSize + 30
        case 2: return baselineFontSize + 24
        case 3, 4, 5: return baselineFontSize + 18
        default: return baselineFontSize
        }
    }
    
    private func getMessageStatusImage(for message: TSMessage) -> (image: UIImage?, backgroundColor: UIColor?) {
        guard let message = message as? TSOutgoingMessage else { return (nil, nil) }
        let image: UIImage
        var backgroundColor: UIColor? = nil
        let status = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: message)
        switch status {
        case .uploading, .sending: image = #imageLiteral(resourceName: "CircleDotDotDot").asTintedImage(color: Colors.text)!
        case .sent, .skipped, .delivered: image = #imageLiteral(resourceName: "CircleCheck").asTintedImage(color: Colors.text)!
        case .read:
            backgroundColor = isLightMode ? .black : .white
            image = isLightMode ? #imageLiteral(resourceName: "FilledCircleCheckLightMode") : #imageLiteral(resourceName: "FilledCircleCheckDarkMode")
        case .failed: image = #imageLiteral(resourceName: "message_status_failed").asTintedImage(color: Colors.text)!
        }
        return (image, backgroundColor)
    }

    
    private func getSize(for viewItem: ConversationViewItem) -> CGSize {
        guard let albumItems = viewItem.mediaAlbumItems else { preconditionFailure() }
        let maxMessageWidth = VisibleMessageCell.getMaxWidth(for: viewItem)
        let defaultSize = MediaAlbumView.layoutSize(forMaxMessageWidth: maxMessageWidth, items: albumItems)
        guard albumItems.count == 1 else { return defaultSize }
        // Honor the content aspect ratio for single media
        let albumItem = albumItems.first!
        let size = albumItem.mediaSize
        guard size.width > 0 && size.height > 0 else { return defaultSize }
        var aspectRatio = (size.width / size.height)
        // Clamp the aspect ratio so that very thin/wide content still looks alright
        let minAspectRatio: CGFloat = 0.35
        let maxAspectRatio = 1 / minAspectRatio
        aspectRatio = aspectRatio.clamp(minAspectRatio, maxAspectRatio)
        let maxSize = CGSize(width: maxMessageWidth, height: maxMessageWidth)
        var width = with(maxSize.height * aspectRatio) { $0 > maxSize.width ? maxSize.width : $0 }
        var height = (width > maxSize.width) ? (maxSize.width / aspectRatio) : maxSize.height
        // Don't blow up small images unnecessarily
        let minSize: CGFloat = 150
        let shortSourceDimension = min(size.width, size.height)
        let shortDestinationDimension = min(width, height)
        if shortDestinationDimension > minSize && shortDestinationDimension > shortSourceDimension {
            let factor = minSize / shortDestinationDimension
            width *= factor; height *= factor
        }
        return CGSize(width: width, height: height)
    }

    static func getMaxWidth(for viewItem: ConversationViewItem) -> CGFloat {
        let screen = UIScreen.main.bounds
        switch viewItem.interaction.interactionType() {
        case .outgoingMessage: return screen.width - contactThreadHSpacing - gutterSize
        case .incomingMessage:
            let leftGutterSize = shouldShowProfilePicture(for: viewItem) ? gutterSize : contactThreadHSpacing
            return screen.width - leftGutterSize - gutterSize
        default: preconditionFailure()
        }
    }

    private static func shouldShowProfilePicture(for viewItem: ConversationViewItem) -> Bool {
        guard let message = viewItem.interaction as? TSMessage else { preconditionFailure() }
        let isGroupThread = message.thread.isGroupThread()
        let senderSessionID = (message as? TSIncomingMessage)?.authorId
        return isGroupThread && viewItem.shouldShowSenderProfilePicture && senderSessionID != nil
    }
}
