
final class ConversationCell : UITableViewCell {
    var threadViewModel: ThreadViewModel! { didSet { update() } }
    
    static let reuseIdentifier = "ConversationCell"
    
    // MARK: Components
    private lazy var unreadMessagesIndicatorView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.accent
        return result
    }()
    
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
    
    private lazy var bottomLabelStackViewSpacer = UIView.hStretchingSpacer()
    
    private lazy var statusIndicatorView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .center
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
        // Set the cell background color
        backgroundColor = Colors.conversationCellBackground
        // Set up the highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Colors.conversationCellSelected
        self.selectedBackgroundView = selectedBackgroundView
        // Set up the unread messages indicator view
        unreadMessagesIndicatorView.set(.width, to: Values.accentLineThickness)
        // Set up the profile picture view
        let profilePictureViewSize = Values.mediumProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        // Set up the label stack view
        let topLabelStackView = UIStackView(arrangedSubviews: [ displayNameLabel, UIView.hStretchingSpacer(), timestampLabel ])
        topLabelStackView.axis = .horizontal
        topLabelStackView.spacing = Values.smallSpacing / 2 // Effectively Values.smallSpacing because there'll be spacing before and after the invisible spacer
        let snippetLabelContainer = UIView()
        snippetLabelContainer.addSubview(snippetLabel)
        snippetLabelContainer.addSubview(typingIndicatorView)
        let bottomLabelStackView = UIStackView(arrangedSubviews: [ snippetLabelContainer, bottomLabelStackViewSpacer, statusIndicatorView ])
        bottomLabelStackView.axis = .horizontal
        bottomLabelStackView.spacing = Values.smallSpacing / 2 // Effectively Values.smallSpacing because there'll be spacing before and after the invisible spacer
        let labelStackView = UIStackView(arrangedSubviews: [ UIView.spacer(withHeight: Values.smallSpacing), topLabelStackView, bottomLabelStackView, UIView.spacer(withHeight: Values.smallSpacing) ])
        labelStackView.axis = .vertical
        labelStackView.spacing = Values.smallSpacing
        // Set up the main stack view
        let stackView = UIStackView(arrangedSubviews: [ unreadMessagesIndicatorView, profilePictureView, labelStackView ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Values.mediumSpacing
        contentView.addSubview(stackView)
        // Set up the constraints
        unreadMessagesIndicatorView.pin(.top, to: .top, of: stackView)
        unreadMessagesIndicatorView.pin(.bottom, to: .bottom, of: stackView)
        timestampLabel.setContentCompressionResistancePriority(.required, for: NSLayoutConstraint.Axis.horizontal)
        statusIndicatorView.set(.width, to: Values.conversationCellStatusIndicatorSize)
        statusIndicatorView.set(.height, to: Values.conversationCellStatusIndicatorSize)
        snippetLabel.pin(to: snippetLabelContainer)
        typingIndicatorView.pin(.leading, to: .leading, of: snippetLabelContainer)
        typingIndicatorView.centerYAnchor.constraint(equalTo: snippetLabel.centerYAnchor).isActive = true
        stackView.pin(.leading, to: .leading, of: contentView)
        stackView.pin(.top, to: .top, of: contentView)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.mediumSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView)
        stackView.set(.width, to: UIScreen.main.bounds.width - Values.mediumSpacing) // Workaround for weird constraints issue
    }
    
    // MARK: Updating
    private func update() {
        LokiAPI.populateUserHexEncodedPublicKeyCacheIfNeeded(for: threadViewModel.threadRecord.uniqueId!) // FIXME: This is a terrible place to do this
        unreadMessagesIndicatorView.alpha = threadViewModel.hasUnreadMessages ? 1 : 0
        if threadViewModel.isGroupThread {
            let users = LokiAPI.userHexEncodedPublicKeyCache[threadViewModel.threadRecord.uniqueId!] ?? []
            let randomUsers = users.sorted().prefix(2) // Sort to provide a level of stability
            if !randomUsers.isEmpty {
                profilePictureView.hexEncodedPublicKey = randomUsers[0]
                profilePictureView.additionalHexEncodedPublicKey = randomUsers.count == 2 ? randomUsers[1] : nil
            } else {
                // TODO: Handle
            }
        } else {
            profilePictureView.hexEncodedPublicKey = threadViewModel.contactIdentifier!
            profilePictureView.additionalHexEncodedPublicKey = nil
        }
        profilePictureView.update()
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
        let lastMessage = threadViewModel.lastMessageForInbox
        if let lastMessage = lastMessage as? TSOutgoingMessage {
            let image: UIImage
            let status = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: lastMessage)
            switch status {
            case .calculatingPoW, .uploading, .sending: image = #imageLiteral(resourceName: "Cog")
            case .sent, .skipped, .delivered: image = #imageLiteral(resourceName: "TickOutline")
            case .read: image = #imageLiteral(resourceName: "TickFilled")
            case .failed: image = #imageLiteral(resourceName: "message_status_failed")
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
                return NSLocalizedString("New Group", comment: "")
            } else {
                return threadViewModel.name
            }
        } else {
            if threadViewModel.threadRecord.isNoteToSelf() {
                return NSLocalizedString("Note to Self", comment: "")
            } else {
                let hexEncodedPublicKey = threadViewModel.contactIdentifier!
                return DisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? hexEncodedPublicKey
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
