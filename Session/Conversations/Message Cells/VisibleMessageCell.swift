
final class VisibleMessageCell : MessageCell, LinkPreviewViewDelegate {
    private var unloadContent: (() -> Void)?
    private var previousX: CGFloat = 0
    var albumView: MediaAlbumView?
    var bodyTextView: UITextView?
    var mediaTextOverlayView: MediaTextOverlayView?
    // Constraints
    private lazy var headerViewTopConstraint = headerView.pin(.top, to: .top, of: self, withInset: 1)
    private lazy var authorLabelHeightConstraint = authorLabel.set(.height, to: 0)
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
    private lazy var timerViewOutgoingMessageConstraint = timerView.pin(.left, to: .left, of: self, withInset: VisibleMessageCell.contactThreadHSpacing)
    private lazy var timerViewIncomingMessageConstraint = timerView.pin(.right, to: .right, of: self, withInset: -VisibleMessageCell.contactThreadHSpacing)

    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let result = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        result.delegate = self
        return result
    }()

    var lastSearchedText: String? { delegate?.lastSearchedText }
    
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
    
    private lazy var moderatorIconImageView = UIImageView(image: #imageLiteral(resourceName: "Crown"))
    
    lazy var bubbleView: UIView = {
        let result = UIView()
        result.layer.cornerRadius = VisibleMessageCell.largeCornerRadius
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
    
    internal lazy var messageStatusImageView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFit
        result.layer.cornerRadius = VisibleMessageCell.messageStatusImageViewSize / 2
        result.layer.masksToBounds = true
        return result
    }()
    
    private lazy var replyButton: UIView = {
        let result = UIView()
        let size = VisibleMessageCell.replyButtonSize + 8
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.layer.borderWidth = 1
        result.layer.borderColor = Colors.text.cgColor
        result.layer.cornerRadius = size / 2
        result.layer.masksToBounds = true
        result.alpha = 0
        return result
    }()
    
    private lazy var replyIconImageView: UIImageView = {
        let result = UIImageView()
        let size = VisibleMessageCell.replyButtonSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.image = UIImage(named: "ic_reply")!.withTint(Colors.text)
        return result
    }()
    
    private lazy var timerView = OWSMessageTimerView()
    
    // MARK: Settings
    private static let messageStatusImageViewSize: CGFloat = 16
    private static let authorLabelBottomSpacing: CGFloat = 4
    private static let groupThreadHSpacing: CGFloat = 12
    private static let profilePictureSize = Values.verySmallProfilePictureSize
    private static let authorLabelInset: CGFloat = 12
    private static let replyButtonSize: CGFloat = 24
    private static let maxBubbleTranslationX: CGFloat = 40
    private static let swipeToReplyThreshold: CGFloat = 130
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
        // Header view
        addSubview(headerView)
        headerViewTopConstraint.isActive = true
        headerView.pin([ UIView.HorizontalEdge.left, UIView.HorizontalEdge.right ], to: self)
        // Author label
        addSubview(authorLabel)
        authorLabelHeightConstraint.isActive = true
        authorLabel.pin(.top, to: .bottom, of: headerView)
        // Profile picture view
        addSubview(profilePictureView)
        profilePictureViewLeftConstraint.isActive = true
        profilePictureViewWidthConstraint.isActive = true
        profilePictureView.pin(.bottom, to: .bottom, of: self, withInset: -1)
        // Moderator icon image view
        moderatorIconImageView.set(.width, to: 20)
        moderatorIconImageView.set(.height, to: 20)
        addSubview(moderatorIconImageView)
        moderatorIconImageView.pin(.trailing, to: .trailing, of: profilePictureView, withInset: 1)
        moderatorIconImageView.pin(.bottom, to: .bottom, of: profilePictureView, withInset: 4.5)
        // Bubble view
        addSubview(bubbleView)
        bubbleViewLeftConstraint1.isActive = true
        bubbleViewTopConstraint.isActive = true
        bubbleViewRightConstraint1.isActive = true
        // Timer view
        addSubview(timerView)
        timerView.center(.vertical, in: bubbleView)
        timerViewOutgoingMessageConstraint.isActive = true
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
        // Reply button
        addSubview(replyButton)
        replyButton.addSubview(replyIconImageView)
        replyIconImageView.center(in: replyButton)
        replyButton.pin(.left, to: .right, of: bubbleView, withInset: Values.smallSpacing)
        replyButton.center(.vertical, in: bubbleView)
        // Remaining constraints
        authorLabel.pin(.left, to: .left, of: bubbleView, withInset: VisibleMessageCell.authorLabelInset)
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
        if let thread = thread as? TSGroupThread, thread.isOpenGroup, let senderSessionID = senderSessionID {
            if let openGroupV2 = Storage.shared.getV2OpenGroup(for: thread.uniqueId!) {
                let isUserModerator = OpenGroupAPIV2.isUserModerator(senderSessionID, for: openGroupV2.room, on: openGroupV2.server)
                moderatorIconImageView.isHidden = !isUserModerator || profilePictureView.isHidden
            } else {
                moderatorIconImageView.isHidden = true
            }
        } else {
            moderatorIconImageView.isHidden = true
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
        populateContentView(for: viewItem, message: message)
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
        let authorLabelAvailableWidth = VisibleMessageCell.getMaxWidth(for: viewItem) - 2 * VisibleMessageCell.authorLabelInset
        let authorLabelAvailableSpace = CGSize(width: authorLabelAvailableWidth, height: .greatestFiniteMagnitude)
        let authorLabelSize = authorLabel.sizeThatFits(authorLabelAvailableSpace)
        authorLabelHeightConstraint.constant = (viewItem.senderName != nil) ? authorLabelSize.height : 0
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
        // Timer
        if viewItem.isExpiringMessage {
            let expirationTimestamp = message.expiresAt
            let expiresInSeconds = message.expiresInSeconds
            timerView.configure(withExpirationTimestamp: expirationTimestamp, initialDurationSeconds: expiresInSeconds, tintColor: Colors.text)
        }
        timerView.isHidden = !viewItem.isExpiringMessage
        timerViewOutgoingMessageConstraint.isActive = (direction == .outgoing)
        timerViewIncomingMessageConstraint.isActive = (direction == .incoming)
        // Swipe to reply
        if (message.isDeleted) {
            removeGestureRecognizer(panGestureRecognizer)
        } else {
            addGestureRecognizer(panGestureRecognizer)
        }
    }
    
    private func populateHeader(for viewItem: ConversationViewItem) {
        guard viewItem.shouldShowDate else { return }
        let dateBreakLabel = UILabel()
        dateBreakLabel.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        dateBreakLabel.textColor = Colors.text
        dateBreakLabel.textAlignment = .center
        let date = viewItem.interaction.dateForUI()
        let description = DateUtil.formatDate(forDisplay: date)
        dateBreakLabel.text = description
        headerView.addSubview(dateBreakLabel)
        dateBreakLabel.pin(.top, to: .top, of: headerView, withInset: Values.smallSpacing)
        let additionalBottomInset = shouldInsetHeader ? Values.mediumSpacing : 1
        headerView.pin(.bottom, to: .bottom, of: dateBreakLabel, withInset: Values.smallSpacing + additionalBottomInset)
        dateBreakLabel.center(.horizontal, in: headerView)
        let availableWidth = VisibleMessageCell.getMaxWidth(for: viewItem)
        let availableSpace = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        let dateBreakLabelSize = dateBreakLabel.sizeThatFits(availableSpace)
        dateBreakLabel.set(.height, to: dateBreakLabelSize.height)
    }
    
    private func populateContentView(for viewItem: ConversationViewItem, message: TSMessage) {
        snContentView.subviews.forEach { $0.removeFromSuperview() }
        func showMediaPlaceholder() {
            let mediaPlaceholderView = MediaPlaceholderView(viewItem: viewItem, textColor: bodyLabelTextColor)
            snContentView.addSubview(mediaPlaceholderView)
            mediaPlaceholderView.pin(to: snContentView)
        }
        albumView = nil
        bodyTextView = nil
        mediaTextOverlayView = nil
        let isOutgoing = (viewItem.interaction.interactionType() == .outgoingMessage)
        switch viewItem.messageCellType {
        case .textOnlyMessage:
            let inset: CGFloat = 12
            let maxWidth = VisibleMessageCell.getMaxWidth(for: viewItem) - 2 * inset
            if let linkPreview = viewItem.linkPreview {
                let linkPreviewView = LinkPreviewView(for: viewItem, maxWidth: maxWidth, delegate: self)
                linkPreviewView.linkPreviewState = LinkPreviewSent(linkPreview: linkPreview, imageAttachment: viewItem.linkPreviewAttachment)
                snContentView.addSubview(linkPreviewView)
                linkPreviewView.pin(to: snContentView)
            } else if let openGroupInvitationName = message.openGroupInvitationName, let openGroupInvitationURL = message.openGroupInvitationURL {
                let openGroupInvitationView = OpenGroupInvitationView(name: openGroupInvitationName, url: openGroupInvitationURL, textColor: bodyLabelTextColor, isOutgoing: isOutgoing)
                snContentView.addSubview(openGroupInvitationView)
                openGroupInvitationView.pin(to: snContentView)
            } else {
                // Stack view
                let stackView = UIStackView(arrangedSubviews: [])
                stackView.axis = .vertical
                stackView.spacing = 2
                // Quote view
                if viewItem.quotedReply != nil {
                    let direction: QuoteView.Direction = isOutgoing ? .outgoing : .incoming
                    let hInset: CGFloat = 2
                    let quoteView = QuoteView(for: viewItem, direction: direction, hInset: hInset, maxWidth: maxWidth)
                    let quoteViewContainer = UIView(wrapping: quoteView, withInsets: UIEdgeInsets(top: 0, leading: hInset, bottom: 0, trailing: hInset))
                    stackView.addArrangedSubview(quoteViewContainer)
                }
                // Body text view
                let bodyTextView = VisibleMessageCell.getBodyTextView(for: viewItem, with: maxWidth, textColor: bodyLabelTextColor, searchText: delegate?.lastSearchedText, delegate: self)
                self.bodyTextView = bodyTextView
                stackView.addArrangedSubview(bodyTextView)
                // Constraints
                snContentView.addSubview(stackView)
                stackView.pin(to: snContentView, withInset: inset)
            }
        case .mediaMessage:
            if viewItem.interaction is TSIncomingMessage,
                let thread = viewItem.interaction.thread as? TSContactThread,
                Storage.shared.getContact(with: thread.contactSessionID())?.isTrusted != true {
                showMediaPlaceholder()
            } else {
                guard let cache = delegate?.getMediaCache() else { preconditionFailure() }
                // Stack view
                let stackView = UIStackView(arrangedSubviews: [])
                stackView.axis = .vertical
                stackView.spacing = Values.smallSpacing
                // Album view
                let maxMessageWidth = VisibleMessageCell.getMaxWidth(for: viewItem)
                let albumView = MediaAlbumView(mediaCache: cache, items: viewItem.mediaAlbumItems!, isOutgoing: isOutgoing, maxMessageWidth: maxMessageWidth)
                self.albumView = albumView
                let size = getSize(for: viewItem)
                albumView.set(.width, to: size.width)
                albumView.set(.height, to: size.height)
                albumView.loadMedia()
                albumView.layer.mask = bubbleViewMaskLayer
                stackView.addArrangedSubview(albumView)
                // Body text view
                if let message = viewItem.interaction as? TSMessage, let body = message.body, body.count > 0,
                    let delegate = delegate { // delegate should always be set at this point
                    let overlayView = MediaTextOverlayView(viewItem: viewItem, albumViewWidth: size.width, textColor: bodyLabelTextColor, delegate: delegate)
                    self.mediaTextOverlayView = overlayView
                    stackView.addArrangedSubview(overlayView)
                }
                unloadContent = { albumView.unloadMedia() }
                // Constraints
                snContentView.addSubview(stackView)
                stackView.pin(to: snContentView)
            }
        case .audio:
            if viewItem.interaction is TSIncomingMessage,
                let thread = viewItem.interaction.thread as? TSContactThread,
                Storage.shared.getContact(with: thread.contactSessionID())?.isTrusted != true {
                showMediaPlaceholder()
            } else {
                let voiceMessageView = VoiceMessageView(viewItem: viewItem)
                snContentView.addSubview(voiceMessageView)
                voiceMessageView.pin(to: snContentView)
                viewItem.lastAudioMessageView = voiceMessageView
            }
        case .genericAttachment:
            if viewItem.interaction is TSIncomingMessage,
                let thread = viewItem.interaction.thread as? TSContactThread,
                Storage.shared.getContact(with: thread.contactSessionID())?.isTrusted != true {
                showMediaPlaceholder()
            } else {
                let inset: CGFloat = 12
                let maxWidth = VisibleMessageCell.getMaxWidth(for: viewItem) - 2 * inset
                // Stack view
                let stackView = UIStackView(arrangedSubviews: [])
                stackView.axis = .vertical
                stackView.spacing = Values.smallSpacing
                // Document view
                let documentView = DocumentView(viewItem: viewItem, textColor: bodyLabelTextColor)
                stackView.addArrangedSubview(documentView)
                // Body text view
                if let message = viewItem.interaction as? TSMessage, let body = message.body, body.count > 0,
                    let delegate = delegate { // delegate should always be set at this point
                    let bodyTextView = VisibleMessageCell.getBodyTextView(for: viewItem, with: maxWidth, textColor: bodyLabelTextColor, searchText: delegate.lastSearchedText, delegate: self)
                    self.bodyTextView = bodyTextView
                    stackView.addArrangedSubview(bodyTextView)
                }
                // Constraints
                snContentView.addSubview(stackView)
                stackView.pin(to: snContentView, withInset: inset)
            }
        case .deletedMessage:
            let deletedMessageView = DeletedMessageView(viewItem: viewItem, textColor: bodyLabelTextColor)
            snContentView.addSubview(deletedMessageView)
            deletedMessageView.pin(to: snContentView)
        default: return
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateBubbleViewCorners()
    }
    
    private func updateBubbleViewCorners() {
        let cornersToRound = getCornersToRound()
        let maskPath = UIBezierPath(roundedRect: bubbleView.bounds, byRoundingCorners: cornersToRound,
            cornerRadii: CGSize(width: VisibleMessageCell.largeCornerRadius, height: VisibleMessageCell.largeCornerRadius))
        bubbleViewMaskLayer.path = maskPath.cgPath
        bubbleView.layer.cornerRadius = VisibleMessageCell.largeCornerRadius
        bubbleView.layer.maskedCorners = getCornerMask(from: cornersToRound)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        unloadContent?()
        let viewsToMove = [ bubbleView, profilePictureView, replyButton, timerView, messageStatusImageView ]
        viewsToMove.forEach { $0.transform = .identity }
        replyButton.alpha = 0
        timerView.prepareForReuse()
    }
    
    // MARK: Interaction
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let bodyTextView = bodyTextView {
            let pointInBodyTextViewCoordinates = convert(point, to: bodyTextView)
            if bodyTextView.bounds.contains(pointInBodyTextViewCoordinates) {
                return bodyTextView
            }
        }
        return super.hitTest(point, with: event)
    }
    
    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true // Needed for the pan gesture recognizer to work with the table view's pan gesture recognizer
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGestureRecognizer {
            let v = panGestureRecognizer.velocity(in: self)
            // Only allow swipes to the left; allowing swipes to the right gets in the way of the default
            // iOS swipe to go back gesture
            guard v.x < 0 else { return false }
            return abs(v.x) > abs(v.y) // It has to be more horizontal than vertical
        } else {
            return true
            
        }
    }
    
    func highlight() {
        let shawdowColour = isLightMode ? UIColor.black.cgColor : Colors.accent.cgColor
        let opacity : Float = isLightMode ? 0.5 : 1
        bubbleView.setShadow(radius: 10, opacity: opacity, offset: .zero, color: shawdowColour)
        DispatchQueue.main.async {
            UIView.animate(withDuration: 1.6) {
                self.bubbleView.setShadow(radius: 0, opacity: 0, offset: .zero, color: UIColor.clear.cgColor)
            }
        }
    }
    
    @objc func handleLongPress() {
        guard let viewItem = viewItem else { return }
        delegate?.handleViewItemLongPressed(viewItem)
    }

    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let viewItem = viewItem else { return }
        let location = gestureRecognizer.location(in: self)
        if profilePictureView.frame.contains(location) && VisibleMessageCell.shouldShowProfilePicture(for: viewItem) {
            guard let message = viewItem.interaction as? TSIncomingMessage else { return }
            guard !message.isOpenGroupMessage else { return } // Do not show user details to prevent spam
            delegate?.showUserDetails(for: message.authorId)
        } else if replyButton.frame.contains(location) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            reply()
        } else {
            delegate?.handleViewItemTapped(viewItem, gestureRecognizer: gestureRecognizer)
        }
    }

    @objc private func handleDoubleTap() {
        guard let viewItem = viewItem else { return }
        delegate?.handleViewItemDoubleTapped(viewItem)
    }
    
    @objc private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let viewItem = viewItem else { return }
        let viewsToMove = [ bubbleView, profilePictureView, replyButton, timerView, messageStatusImageView ]
        let translationX = gestureRecognizer.translation(in: self).x.clamp(-CGFloat.greatestFiniteMagnitude, 0)
        switch gestureRecognizer.state {
        case .began:
            delegate?.handleViewItemSwiped(viewItem, state: .began)
        case .changed:
            // The idea here is to asymptotically approach a maximum drag distance
            let damping: CGFloat = 20
            let sign: CGFloat = -1
            let x = (damping * (sqrt(abs(translationX)) / sqrt(damping))) * sign
            viewsToMove.forEach { $0.transform = CGAffineTransform(translationX: x, y: 0) }
            if timerView.isHidden {
                replyButton.alpha = abs(translationX) / VisibleMessageCell.maxBubbleTranslationX
            } else {
                replyButton.alpha = 0 // Always hide the reply button if the timer view is showing, otherwise they can overlap
            }
            if abs(translationX) > VisibleMessageCell.swipeToReplyThreshold && abs(previousX) < VisibleMessageCell.swipeToReplyThreshold {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred() // Let the user know when they've hit the swipe to reply threshold
            }
            previousX = translationX
        case .ended, .cancelled:
            if abs(translationX) > VisibleMessageCell.swipeToReplyThreshold {
                delegate?.handleViewItemSwiped(viewItem, state: .ended)
                reply()
            } else {
                delegate?.handleViewItemSwiped(viewItem, state: .cancelled)
                resetReply()
            }
        default: break
        }
    }
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        delegate?.openURL(URL)
        return false
    }
    
    private func resetReply() {
        let viewsToMove = [ bubbleView, profilePictureView, replyButton, timerView, messageStatusImageView ]
        UIView.animate(withDuration: 0.25) {
            viewsToMove.forEach { $0.transform = .identity }
            self.replyButton.alpha = 0
        }
    }
    
    private func reply() {
        guard let viewItem = viewItem else { return }
        resetReply()
        delegate?.handleReplyButtonTapped(for: viewItem)
    }

    func handleLinkPreviewCanceled() {
        // Not relevant in this case
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
    
    private func getCornerMask(from rectCorner: UIRectCorner) -> CACornerMask {
        var cornerMask = CACornerMask()
        if rectCorner.contains(.allCorners) {
            cornerMask = [ .layerMaxXMinYCorner, .layerMinXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]
        } else {
            if rectCorner.contains(.topRight) { cornerMask.insert(.layerMaxXMinYCorner) }
            if rectCorner.contains(.topLeft) { cornerMask.insert(.layerMinXMinYCorner) }
            if rectCorner.contains(.bottomRight) { cornerMask.insert(.layerMaxXMaxYCorner) }
            if rectCorner.contains(.bottomLeft) { cornerMask.insert(.layerMinXMaxYCorner) }
        }
        return cornerMask
    }
    
    private static func getFontSize(for viewItem: ConversationViewItem) -> CGFloat {
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
        case .failed: image = #imageLiteral(resourceName: "message_status_failed").asTintedImage(color: Colors.destructive)!
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
            let isGroupThread = viewItem.isGroupThread
            let leftGutterSize = isGroupThread ? gutterSize : contactThreadHSpacing
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
    
    static func getBodyTextView(for viewItem: ConversationViewItem, with availableWidth: CGFloat, textColor: UIColor, searchText: String?, delegate: UITextViewDelegate & BodyTextViewDelegate) -> UITextView {
        // Take care of:
        // • Highlighting mentions
        // • Linkification
        // • Highlighting search results
        guard let message = viewItem.interaction as? TSMessage else { preconditionFailure() }
        let isOutgoing = (message.interactionType() == .outgoingMessage)
        let result = BodyTextView(snDelegate: delegate)
        result.isEditable = false
        let attributes: [NSAttributedString.Key:Any] = [
            .foregroundColor : textColor,
            .font : UIFont.systemFont(ofSize: getFontSize(for: viewItem))
        ]
        let attributedText = NSMutableAttributedString(attributedString: MentionUtilities.highlightMentions(in: message.body ?? "", isOutgoingMessage: isOutgoing, threadID: viewItem.interaction.uniqueThreadId, attributes: attributes))
        if let searchText = searchText, searchText.count >= ConversationSearchController.kMinimumSearchTextLength {
            let normalizedSearchText = FullTextSearchFinder.normalize(text: searchText)
            do {
                let regex = try NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: normalizedSearchText), options: .caseInsensitive)
                let matches = regex.matches(in: attributedText.string, options: .withoutAnchoringBounds, range: NSRange(location: 0, length: (attributedText.string as NSString).length))
                for match in matches {
                    guard match.range.location + match.range.length < attributedText.length else { continue }
                    attributedText.addAttribute(.backgroundColor, value: UIColor.white, range: match.range)
                    attributedText.addAttribute(.foregroundColor, value: UIColor.black, range: match.range)
                }
            } catch {
                // Do nothing
            }
        }
        result.attributedText = attributedText
        result.dataDetectorTypes = .link
        result.backgroundColor = .clear
        result.isOpaque = false
        result.textContainerInset = UIEdgeInsets.zero
        result.contentInset = UIEdgeInsets.zero
        result.textContainer.lineFragmentPadding = 0
        result.isScrollEnabled = false
        result.isUserInteractionEnabled = true
        result.delegate = delegate
        result.linkTextAttributes = [ .foregroundColor : textColor, .underlineStyle : NSUnderlineStyle.single.rawValue ]
        let availableSpace = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        let size = result.sizeThatFits(availableSpace)
        result.set(.height, to: size.height)
        return result
    }
}
