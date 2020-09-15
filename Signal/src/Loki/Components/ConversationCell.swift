
final class ConversationCell : UITableViewCell {
    var threadViewModel: ThreadViewModel! { didSet { update() } }
    
    static let reuseIdentifier = "ConversationCell"
    
    // MARK: Components
    private let accentView = UIView()
    
    private lazy var profilePictureView = ProfilePictureView()
    
    private lazy var displayNameLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    private lazy var timestampLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        result.alpha = Values.conversationCellTimestampOpacity
        return result
    }()
    
    private lazy var snippetLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    private lazy var typingIndicatorView = TypingIndicatorView()
    
    private lazy var statusIndicatorView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFit
        result.layer.cornerRadius = Values.conversationCellStatusIndicatorSize / 2
        result.layer.masksToBounds = true
        return result
    }()
    
    // MARK: Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        let cellHeight: CGFloat = 68
        // Set the cell background color
        backgroundColor = Colors.cellBackground
        // Set up the highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Colors.cellSelected
        self.selectedBackgroundView = selectedBackgroundView
        // Set up the accent view
        accentView.set(.width, to: Values.accentLineThickness)
        accentView.set(.height, to: cellHeight)
        // Set up the profile picture view
        let profilePictureViewSize = Values.mediumProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        // Set up the label stack view
        let topLabelSpacer = UIView.hStretchingSpacer()
        let topLabelStackView = UIStackView(arrangedSubviews: [ displayNameLabel, topLabelSpacer, timestampLabel ])
        topLabelStackView.axis = .horizontal
        topLabelStackView.alignment = .center
        topLabelStackView.spacing = Values.smallSpacing / 2 // Effectively Values.smallSpacing because there'll be spacing before and after the invisible spacer
        let snippetLabelContainer = UIView()
        snippetLabelContainer.addSubview(snippetLabel)
        snippetLabelContainer.addSubview(typingIndicatorView)
        let bottomLabelSpacer = UIView.hStretchingSpacer()
        let bottomLabelStackView = UIStackView(arrangedSubviews: [ snippetLabelContainer, bottomLabelSpacer, statusIndicatorView ])
        bottomLabelStackView.axis = .horizontal
        bottomLabelStackView.alignment = .center
        bottomLabelStackView.spacing = Values.smallSpacing / 2 // Effectively Values.smallSpacing because there'll be spacing before and after the invisible spacer
        let labelContainerView = UIView()
        labelContainerView.addSubview(topLabelStackView)
        labelContainerView.addSubview(bottomLabelStackView)
        // Set up the main stack view
        let stackView = UIStackView(arrangedSubviews: [ accentView, profilePictureView, labelContainerView ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Values.mediumSpacing
        contentView.addSubview(stackView)
        // Set up the constraints
        accentView.pin(.top, to: .top, of: contentView)
        accentView.pin(.bottom, to: .bottom, of: contentView)
        // The three lines below are part of a workaround for a weird layout bug
        topLabelStackView.set(.width, to: UIScreen.main.bounds.width - Values.accentLineThickness - Values.mediumSpacing - profilePictureViewSize - Values.mediumSpacing - Values.mediumSpacing)
        topLabelStackView.set(.height, to: 20)
        topLabelSpacer.set(.height, to: 20)
        timestampLabel.setContentCompressionResistancePriority(.required, for: NSLayoutConstraint.Axis.horizontal)
        // The three lines below are part of a workaround for a weird layout bug
        bottomLabelStackView.set(.width, to: UIScreen.main.bounds.width - Values.accentLineThickness - Values.mediumSpacing - profilePictureViewSize - Values.mediumSpacing - Values.mediumSpacing)
        bottomLabelStackView.set(.height, to: 18)
        bottomLabelSpacer.set(.height, to: 18)
        statusIndicatorView.set(.width, to: Values.conversationCellStatusIndicatorSize)
        statusIndicatorView.set(.height, to: Values.conversationCellStatusIndicatorSize)
        snippetLabel.pin(to: snippetLabelContainer)
        typingIndicatorView.pin(.leading, to: .leading, of: snippetLabelContainer)
        typingIndicatorView.centerYAnchor.constraint(equalTo: snippetLabel.centerYAnchor).isActive = true
        // Not using a stack view for this is part of a workaround for a weird layout bug
        topLabelStackView.pin(.leading, to: .leading, of: labelContainerView)
        topLabelStackView.pin(.top, to: .top, of: labelContainerView, withInset: 12)
        topLabelStackView.pin(.trailing, to: .trailing, of: labelContainerView)
        bottomLabelStackView.pin(.leading, to: .leading, of: labelContainerView)
        bottomLabelStackView.pin(.top, to: .bottom, of: topLabelStackView, withInset: 6)
        labelContainerView.pin(.bottom, to: .bottom, of: bottomLabelStackView, withInset: 12)
        // The two lines below are part of a workaround for a weird layout bug
        labelContainerView.set(.width, to: UIScreen.main.bounds.width - Values.accentLineThickness - Values.mediumSpacing - profilePictureViewSize - Values.mediumSpacing - Values.mediumSpacing)
        labelContainerView.set(.height, to: cellHeight)
        stackView.pin(.leading, to: .leading, of: contentView)
        stackView.pin(.top, to: .top, of: contentView)
        // The two lines below are part of a workaround for a weird layout bug
        stackView.set(.width, to: UIScreen.main.bounds.width - Values.mediumSpacing)
        stackView.set(.height, to: cellHeight)
    }
    
    // MARK: Updating
    private func update() {
        AssertIsOnMainThread()
        MentionsManager.populateUserPublicKeyCacheIfNeeded(for: threadViewModel.threadRecord.uniqueId!) // FIXME: This is a terrible place to do this
        let isBlocked: Bool
        if let thread = threadViewModel.threadRecord as? TSContactThread {
            isBlocked = SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(thread.contactIdentifier())
        } else {
            isBlocked = false
        }
        if isBlocked {
            accentView.backgroundColor = Colors.destructive
            accentView.alpha = 1
        } else {
            accentView.backgroundColor = Colors.accent
            accentView.alpha = threadViewModel.hasUnreadMessages ? 1 : 0.0001 // Setting the alpha to exactly 0 causes an issue on iOS 12
        }
        profilePictureView.update(for: threadViewModel.threadRecord)
        displayNameLabel.text = getDisplayName()
        timestampLabel.text = DateUtil.formatDateShort(threadViewModel.lastMessageDate)
        if SSKEnvironment.shared.typingIndicators.typingRecipientId(forThread: self.threadViewModel.threadRecord) != nil {
            snippetLabel.text = ""
            typingIndicatorView.isHidden = false
            typingIndicatorView.startAnimation()
        } else {
            snippetLabel.attributedText = getSnippet()
            typingIndicatorView.isHidden = true
            typingIndicatorView.stopAnimation()
        }
        statusIndicatorView.backgroundColor = nil
        let lastMessage = threadViewModel.lastMessageForInbox
        if let lastMessage = lastMessage as? TSOutgoingMessage {
            let image: UIImage
            let status = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: lastMessage)
            switch status {
            case .calculatingPoW, .uploading, .sending: image = #imageLiteral(resourceName: "CircleDotDotDot").asTintedImage(color: Colors.text)!
            case .sent, .skipped, .delivered: image = #imageLiteral(resourceName: "CircleCheck").asTintedImage(color: Colors.text)!
            case .read:
                statusIndicatorView.backgroundColor = isLightMode ? .black : .white
                image = isLightMode ? #imageLiteral(resourceName: "FilledCircleCheckLightMode") : #imageLiteral(resourceName: "FilledCircleCheckDarkMode")
            case .failed: image = #imageLiteral(resourceName: "message_status_failed").asTintedImage(color: Colors.text)!
            }
            statusIndicatorView.image = image
            statusIndicatorView.isHidden = false
        } else {
            statusIndicatorView.isHidden = true
        }
    }
    
    private func getDisplayName() -> String {
        if threadViewModel.isGroupThread {
            if threadViewModel.name.isEmpty {
                return GroupDisplayNameUtilities.getDefaultDisplayName(for: threadViewModel.threadRecord as! TSGroupThread)
            } else {
                return threadViewModel.name
            }
        } else {
            if threadViewModel.threadRecord.isNoteToSelf() {
                return NSLocalizedString("NOTE_TO_SELF", comment: "")
            } else {
                let hexEncodedPublicKey = threadViewModel.contactIdentifier!
                return UserDisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? hexEncodedPublicKey
            }
        }
    }
    
    private func getSnippet() -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        if threadViewModel.isMuted {
            result.append(NSAttributedString(string: "\u{e067}  ", attributes: [ .font : UIFont.ows_elegantIconsFont(10), .foregroundColor : Colors.unimportant ]))
        }
        if let rawSnippet = threadViewModel.lastMessageText {
            let snippet = MentionUtilities.highlightMentions(in: rawSnippet, threadID: threadViewModel.threadRecord.uniqueId!)
            let font = threadViewModel.hasUnreadMessages ? UIFont.boldSystemFont(ofSize: Values.smallFontSize) : UIFont.systemFont(ofSize: Values.smallFontSize)
            result.append(NSAttributedString(string: snippet, attributes: [ .font : font, .foregroundColor : Colors.text ]))
        }
        return result
    }
}
