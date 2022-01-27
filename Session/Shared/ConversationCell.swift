import UIKit
import SessionUIKit

final class ConversationCell : UITableViewCell {
    var isShowingGlobalSearchResult = false
    var threadViewModel: ThreadViewModel! {
        didSet {
            isShowingGlobalSearchResult ? updateForSearchResult() : update()
        }
    }
    
    static let reuseIdentifier = "ConversationCell"
    
    // MARK: UI Components
    private let accentLineView = UIView()
    
    private lazy var profilePictureView = ProfilePictureView()
    
    private lazy var displayNameLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    private lazy var unreadCountView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.text.withAlphaComponent(Values.veryLowOpacity)
        let size = ConversationCell.unreadCountViewSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.layer.masksToBounds = true
        result.layer.cornerRadius = size / 2
        return result
    }()
    
    private lazy var unreadCountLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.textAlignment = .center
        return result
    }()
    
    private lazy var hasMentionView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.accent
        let size = ConversationCell.unreadCountViewSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.layer.masksToBounds = true
        result.layer.cornerRadius = size / 2
        return result
    }()
    
    private lazy var hasMentionLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.text = "@"
        result.textAlignment = .center
        return result
    }()
    
    private lazy var isPinnedIcon: UIImageView = {
        let result = UIImageView(image: UIImage(named: "Pin")!.withRenderingMode(.alwaysTemplate))
        result.contentMode = .scaleAspectFit
        let size = ConversationCell.unreadCountViewSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.tintColor = Colors.pinIcon
        result.layer.masksToBounds = true
        return result
    }()
    
    private lazy var timestampLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        result.alpha = Values.lowOpacity
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
        result.layer.cornerRadius = ConversationCell.statusIndicatorSize / 2
        result.layer.masksToBounds = true
        return result
    }()
    
    private lazy var topLabelStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.alignment = .center
        result.spacing = Values.smallSpacing / 2 // Effectively Values.smallSpacing because there'll be spacing before and after the invisible spacer
        return result
    }()
    
    private lazy var bottomLabelStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.alignment = .center
        result.spacing = Values.smallSpacing / 2 // Effectively Values.smallSpacing because there'll be spacing before and after the invisible spacer
        return result
    }()
    
    // MARK: Settings
    private static let unreadCountViewSize: CGFloat = 20
    private static let statusIndicatorSize: CGFloat = 14
    
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
        // Background color
        backgroundColor = Colors.cellBackground
        // Highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Colors.cellSelected
        self.selectedBackgroundView = selectedBackgroundView
        // Accent line view
        accentLineView.set(.width, to: Values.accentLineThickness)
        accentLineView.set(.height, to: cellHeight)
        // Profile picture view
        let profilePictureViewSize = Values.mediumProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        // Unread count view
        unreadCountView.addSubview(unreadCountLabel)
        unreadCountLabel.pin(to: unreadCountView)
        // Has mention view
        hasMentionView.addSubview(hasMentionLabel)
        hasMentionLabel.pin(to: hasMentionView)
        // Label stack view
        let topLabelSpacer = UIView.hStretchingSpacer()
        [ displayNameLabel, isPinnedIcon, unreadCountView, hasMentionView, topLabelSpacer, timestampLabel ].forEach{ view in
            topLabelStackView.addArrangedSubview(view)
        }
        let snippetLabelContainer = UIView()
        snippetLabelContainer.addSubview(snippetLabel)
        snippetLabelContainer.addSubview(typingIndicatorView)
        let bottomLabelSpacer = UIView.hStretchingSpacer()
        [ snippetLabelContainer, bottomLabelSpacer, statusIndicatorView ].forEach{ view in
            bottomLabelStackView.addArrangedSubview(view)
        }
        let labelContainerView = UIStackView(arrangedSubviews: [ topLabelStackView, bottomLabelStackView ])
        labelContainerView.axis = .vertical
        labelContainerView.alignment = .leading
        labelContainerView.spacing = 6
        // Main stack view
        let stackView = UIStackView(arrangedSubviews: [ accentLineView, profilePictureView, labelContainerView ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Values.mediumSpacing
        contentView.addSubview(stackView)
        // Constraints
        accentLineView.pin(.top, to: .top, of: contentView)
        accentLineView.pin(.bottom, to: .bottom, of: contentView)
        timestampLabel.setContentCompressionResistancePriority(.required, for: NSLayoutConstraint.Axis.horizontal)
        // HACK: The six lines below are part of a workaround for a weird layout bug
        topLabelStackView.set(.width, to: UIScreen.main.bounds.width - Values.accentLineThickness - profilePictureViewSize - 3 * Values.mediumSpacing)
        topLabelStackView.set(.height, to: 20)
        topLabelSpacer.set(.height, to: 20)
        bottomLabelStackView.set(.width, to: UIScreen.main.bounds.width - Values.accentLineThickness - profilePictureViewSize - 3 * Values.mediumSpacing)
        bottomLabelStackView.set(.height, to: 18)
        bottomLabelSpacer.set(.height, to: 18)
        statusIndicatorView.set(.width, to: ConversationCell.statusIndicatorSize)
        statusIndicatorView.set(.height, to: ConversationCell.statusIndicatorSize)
        snippetLabel.pin(to: snippetLabelContainer)
        typingIndicatorView.pin(.leading, to: .leading, of: snippetLabelContainer)
        typingIndicatorView.centerYAnchor.constraint(equalTo: snippetLabel.centerYAnchor).isActive = true
        stackView.pin(.leading, to: .leading, of: contentView)
        stackView.pin(.top, to: .top, of: contentView)
        // HACK: The two lines below are part of a workaround for a weird layout bug
        stackView.set(.width, to: UIScreen.main.bounds.width - Values.mediumSpacing)
        stackView.set(.height, to: cellHeight)
    }
    
    // MARK: Updating for search results
    private func updateForSearchResult() {
        AssertIsOnMainThread()
        guard let thread = threadViewModel?.threadRecord else { return }
        profilePictureView.update(for: thread)
        isPinnedIcon.isHidden = true
        unreadCountView.isHidden = true
        hasMentionView.isHidden = true
    }
    
    public func configureForRecent() {
        displayNameLabel.attributedText = NSMutableAttributedString(string: getDisplayName(), attributes: [.foregroundColor:Colors.text])
        bottomLabelStackView.isHidden = false
        let snippet = String(format: NSLocalizedString("RECENT_SEARCH_LAST_MESSAGE_DATETIME", comment: ""), DateUtil.formatDate(forDisplay: threadViewModel.lastMessageDate))
        snippetLabel.attributedText = NSMutableAttributedString(string: snippet, attributes: [.foregroundColor:Colors.text.withAlphaComponent(Values.lowOpacity)])
        timestampLabel.isHidden = true
    }
    
    public func configure(messageDate: Date?, snippet: String?, searchText: String, message: TSMessage? = nil) {
        let normalizedSearchText = searchText.lowercased()
        if let messageDate = messageDate, let snippet = snippet {
            // Message
            displayNameLabel.attributedText = NSMutableAttributedString(string: getDisplayName(), attributes: [.foregroundColor:Colors.text])
            timestampLabel.isHidden = false
            timestampLabel.text = DateUtil.formatDate(forDisplay: messageDate)
            bottomLabelStackView.isHidden = false
            var rawSnippet = snippet
            if let message = message, let name = getMessageAuthorName(message: message) {
                rawSnippet = "\(name): \(snippet)"
            }
            snippetLabel.attributedText = getHighlightedSnippet(snippet: rawSnippet, searchText: normalizedSearchText, fontSize: Values.smallFontSize)
        } else {
            // Contact
            if threadViewModel.isGroupThread, let thread = threadViewModel.threadRecord as? TSGroupThread {
                displayNameLabel.attributedText = getHighlightedSnippet(snippet: getDisplayName(), searchText: normalizedSearchText, fontSize: Values.mediumFontSize)
                bottomLabelStackView.isHidden = false
                let context: Contact.Context = thread.isOpenGroup ? .openGroup : .regular
                var rawSnippet: String = ""
                thread.groupModel.groupMemberIds.forEach{ id in
                    if let displayName = Storage.shared.getContact(with: id)?.displayName(for: context) {
                        if !rawSnippet.isEmpty {
                            rawSnippet += ", \(displayName)"
                        }
                        if displayName.lowercased().contains(normalizedSearchText) {
                            rawSnippet = displayName
                        }
                    }
                }
                snippetLabel.attributedText = getHighlightedSnippet(snippet: rawSnippet, searchText: normalizedSearchText, fontSize: Values.smallFontSize)
            } else {
                displayNameLabel.attributedText = getHighlightedSnippet(snippet: getDisplayNameForSearch(threadViewModel.contactSessionID!), searchText: normalizedSearchText, fontSize: Values.mediumFontSize)
                bottomLabelStackView.isHidden = true
            }
            timestampLabel.isHidden = true
        }
    }
    
    private func getHighlightedSnippet(snippet: String, searchText: String, fontSize: CGFloat) -> NSMutableAttributedString {
        guard snippet != NSLocalizedString("NOTE_TO_SELF", comment: "") else {
            return NSMutableAttributedString(string: snippet, attributes: [.foregroundColor:Colors.text])
        }
        
        let result = NSMutableAttributedString(string: snippet, attributes: [.foregroundColor:Colors.text.withAlphaComponent(Values.lowOpacity)])
        let normalizedSnippet = snippet.lowercased() as NSString
        
        guard normalizedSnippet.contains(searchText) else { return result }
        
        let range = normalizedSnippet.range(of: searchText)
        result.addAttribute(.foregroundColor, value: Colors.text, range: range)
        result.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: fontSize), range: range)
        return result
    }
    
    // MARK: Updating
    private func update() {
        AssertIsOnMainThread()
        guard let thread = threadViewModel?.threadRecord else { return }
        backgroundColor = threadViewModel.isPinned ? Colors.cellPinned : Colors.cellBackground
        let isBlocked: Bool
        if let thread = thread as? TSContactThread {
            isBlocked = SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(thread.contactSessionID())
        } else {
            isBlocked = false
        }
        if isBlocked {
            accentLineView.backgroundColor = Colors.destructive
            accentLineView.alpha = 1
        } else {
            accentLineView.backgroundColor = Colors.accent
            accentLineView.alpha = threadViewModel.hasUnreadMessages ? 1 : 0.0001 // Setting the alpha to exactly 0 causes an issue on iOS 12
        }
        isPinnedIcon.isHidden = !threadViewModel.isPinned
        unreadCountView.isHidden = !threadViewModel.hasUnreadMessages
        let unreadCount = threadViewModel.unreadCount
        unreadCountLabel.text = unreadCount < 100 ? "\(unreadCount)" : "99+"
        let fontSize = (unreadCount < 100) ? Values.verySmallFontSize : 8
        unreadCountLabel.font = .boldSystemFont(ofSize: fontSize)
        hasMentionView.isHidden = !(threadViewModel.hasUnreadMentions && thread.isGroupThread())
        profilePictureView.update(for: thread)
        displayNameLabel.text = getDisplayName()
        timestampLabel.text = DateUtil.formatDate(forDisplay: threadViewModel.lastMessageDate)
        if SSKEnvironment.shared.typingIndicators.typingRecipientId(forThread: thread) != nil {
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
            case .uploading, .sending: image = #imageLiteral(resourceName: "CircleDotDotDot").asTintedImage(color: Colors.text)!
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
    
    private func getMessageAuthorName(message: TSMessage) -> String? {
        guard threadViewModel.isGroupThread else { return nil }
        if let incomingMessage = message as? TSIncomingMessage {
            return Storage.shared.getContact(with: incomingMessage.authorId)?.displayName(for: .regular) ?? "Anonymous"
        }
        return nil
    }
    
    private func getDisplayNameForSearch(_ sessionID: String) -> String {
        if threadViewModel.threadRecord.isNoteToSelf() {
            return NSLocalizedString("NOTE_TO_SELF", comment: "")
        } else {
            var result = sessionID
            if let contact = Storage.shared.getContact(with: sessionID), let name = contact.name {
                result = name
                if let nickname = contact.nickname { result += "(\(nickname))"}
            }
            return result
        }
    }
    
    private func getDisplayName() -> String {
        if threadViewModel.isGroupThread {
            if threadViewModel.name.isEmpty {
                return "Unknown Group"
            } else {
                return threadViewModel.name
            }
        } else {
            if threadViewModel.threadRecord.isNoteToSelf() {
                return NSLocalizedString("NOTE_TO_SELF", comment: "")
            } else {
                let hexEncodedPublicKey = threadViewModel.contactSessionID!
                return Storage.shared.getContact(with: hexEncodedPublicKey)?.displayName(for: .regular) ?? hexEncodedPublicKey
            }
        }
    }
    
    private func getSnippet() -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        if threadViewModel.isMuted {
            result.append(NSAttributedString(string: "\u{e067}  ", attributes: [ .font : UIFont.ows_elegantIconsFont(10), .foregroundColor : Colors.unimportant ]))
        } else if threadViewModel.isOnlyNotifyingForMentions {
            let imageAttachment = NSTextAttachment()
            imageAttachment.image = UIImage(named: "NotifyMentions.png")?.asTintedImage(color: Colors.unimportant)
            imageAttachment.bounds = CGRect(x: 0, y: -2, width: Values.smallFontSize, height: Values.smallFontSize)
            let imageString = NSAttributedString(attachment: imageAttachment)
            result.append(imageString)
            result.append(NSAttributedString(string: "  ", attributes: [ .font : UIFont.ows_elegantIconsFont(10), .foregroundColor : Colors.unimportant ]))
        }
        let font = threadViewModel.hasUnreadMessages ? UIFont.boldSystemFont(ofSize: Values.smallFontSize) : UIFont.systemFont(ofSize: Values.smallFontSize)
        if threadViewModel.isGroupThread, let message = threadViewModel.lastMessageForInbox as? TSMessage, let name = getMessageAuthorName(message: message) {
            result.append(NSAttributedString(string: "\(name): ", attributes: [ .font : font, .foregroundColor : Colors.text ]))
        }
        if let rawSnippet = threadViewModel.lastMessageText {
            let snippet = MentionUtilities.highlightMentions(in: rawSnippet, threadID: threadViewModel.threadRecord.uniqueId!)
            result.append(NSAttributedString(string: snippet, attributes: [ .font : font, .foregroundColor : Colors.text ]))
        }
        return result
    }
}
