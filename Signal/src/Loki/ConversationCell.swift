
final class ConversationCell : UITableViewCell {
    public var threadViewModel: ThreadViewModel! { didSet { update() } }
    
    public static let reuseIdentifier = "ConversationCell"
    
    // MARK: Components
    private lazy var unreadMessagesIndicator: UIView = {
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
    
    private lazy var snippetLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    private lazy var typingIndicatorView = TypingIndicatorView()
    
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
        // Make the cell transparent
        backgroundColor = .clear
        // Set up the unread messages indicator
        unreadMessagesIndicator.set(.width, to: Values.accentLineThickness)
        // Set up the profile picture view
        let profilePictureViewSize = Values.mediumProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        // Set up the label stack view
        let snippetLabelContainer = UIView()
        snippetLabelContainer.addSubview(snippetLabel)
        snippetLabelContainer.addSubview(typingIndicatorView)
        let labelStackView = UIStackView(arrangedSubviews: [ UIView.spacer(withHeight: Values.smallSpacing), displayNameLabel, snippetLabelContainer, UIView.spacer(withHeight: Values.smallSpacing) ])
        labelStackView.axis = .vertical
        labelStackView.spacing = Values.smallSpacing
        // Set up the main stack view
        let stackView = UIStackView(arrangedSubviews: [ unreadMessagesIndicator, profilePictureView, labelStackView ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Values.mediumSpacing
        contentView.addSubview(stackView)
        // Set up the constraints
        unreadMessagesIndicator.pin(.top, to: .top, of: stackView)
        unreadMessagesIndicator.pin(.bottom, to: .bottom, of: stackView)
        snippetLabel.pin(to: snippetLabelContainer)
        typingIndicatorView.pin(.leading, to: .leading, of: snippetLabelContainer)
        typingIndicatorView.centerYAnchor.constraint(equalTo: snippetLabel.centerYAnchor).isActive = true
        stackView.pin(.leading, to: .leading, of: contentView)
        stackView.pin(.top, to: .top, of: contentView)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.mediumSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView)
        stackView.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing) // Workaround for weird constraints issue
    }
    
    // MARK: Updating
    private func update() {
        LokiAPI.populateUserHexEncodedPublicKeyCacheIfNeeded(for: threadViewModel.threadRecord.uniqueId!) // FIXME: This is a terrible place to do this
        unreadMessagesIndicator.isHidden = !threadViewModel.hasUnreadMessages
        if threadViewModel.hasUnreadMessages {
            backgroundColor = UIColor(hex: 0x1B1B1B)
        } else {
            backgroundColor = .clear
        }
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
        if SSKEnvironment.shared.typingIndicators.typingRecipientId(forThread: self.threadViewModel.threadRecord) != nil {
            snippetLabel.text = ""
            typingIndicatorView.isHidden = false
            typingIndicatorView.startAnimation()
        } else {
            snippetLabel.attributedText = getSnippet()
            typingIndicatorView.isHidden = true
            typingIndicatorView.stopAnimation()
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
            result.append(NSAttributedString(string: "\u{e067} ", attributes: [ .font : UIFont.ows_elegantIconsFont(10), .foregroundColor : Colors.unimportant ]))
        }
        if let rawSnippet = threadViewModel.lastMessageText {
            let snippet = MentionUtilities.highlightMentions(in: rawSnippet, threadID: threadViewModel.threadRecord.uniqueId!)
            result.append(NSAttributedString(string: snippet, attributes: [ .font : UIFont.systemFont(ofSize: Values.smallFontSize), .foregroundColor : Colors.text ]))
        }
        return result
    }
}
