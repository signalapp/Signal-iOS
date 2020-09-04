
@objc(LKConversationTitleView)
final class ConversationTitleView : UIView {
    private let thread: TSThread
    private var currentStatus: Status? { didSet { updateSubtitleForCurrentStatus() } }
    private var handledMessageTimestamps: Set<NSNumber> = []
    
    // MARK: Types
    private enum Status : Int {
        case calculatingPoW = 1
        case routing = 2
        case messageSending = 3
        case messageSent = 4
        case messageFailed = 5
    }
    
    // MARK: Components
    private lazy var profilePictureView: ProfilePictureView = {
        let result = ProfilePictureView()
        let size = Values.smallProfilePictureSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.size = size
        return result
    }()

    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: 13)
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    // MARK: Lifecycle
    @objc init(thread: TSThread) {
        self.thread = thread
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
        updateTitle()
        updateProfilePicture()
        updateSubtitleForCurrentStatus()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleProfileChangedNotification(_:)), name: NSNotification.Name(rawValue: kNSNotificationName_OtherUsersProfileDidChange), object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleCalculatingPoWNotification(_:)), name: .calculatingPoW, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleRoutingNotification(_:)), name: .routing, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleMessageSendingNotification(_:)), name: .messageSending, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleMessageSentNotification(_:)), name: .messageSent, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleMessageFailedNotification(_:)), name: .messageFailed, object: nil)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(thread:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(thread:) instead.")
    }
    
    private func setUpViewHierarchy() {
        let labelStackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
        labelStackView.axis = .vertical
        labelStackView.alignment = .leading
        let stackView = UIStackView(arrangedSubviews: [ profilePictureView, labelStackView ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 12
        addSubview(stackView)
        stackView.pin(to: self)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Updating
    private func updateTitle() {
        let title: String
        if thread.isGroupThread() {
            if thread.name().isEmpty {
                title = GroupDisplayNameUtilities.getDefaultDisplayName(for: thread as! TSGroupThread)
            } else {
                title = thread.name()
            }
        } else {
            if thread.isNoteToSelf() {
                title = NSLocalizedString("Note to Self", comment: "")
            } else {
                let hexEncodedPublicKey = thread.contactIdentifier()!
                title = UserDisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? hexEncodedPublicKey
            }
        }
        titleLabel.text = title
    }

    private func updateProfilePicture() {
        if let thread = thread as? TSGroupThread {
            if thread.name() == "Loki Public Chat" || thread.name() == "Session Public Chat" { // Override the profile picture for the Loki Public Chat and the Session Public Chat
                profilePictureView.hexEncodedPublicKey = ""
                profilePictureView.isRSSFeed = true
            } else if let openGroupProfilePicture = thread.groupModel.groupImage { // An open group with a profile picture
                profilePictureView.openGroupProfilePicture = openGroupProfilePicture
                profilePictureView.isRSSFeed = false
            } else if thread.groupModel.groupType == .openGroup || thread.groupModel.groupType == .rssFeed { // An open group without a profile picture or an RSS feed
                profilePictureView.hexEncodedPublicKey = ""
                profilePictureView.isRSSFeed = true
            } else { // A closed group
                var users = MentionsManager.userPublicKeyCache[thread.uniqueId!] ?? []
                users.remove(getUserHexEncodedPublicKey())
                let randomUsers = users.sorted().prefix(2) // Sort to provide a level of stability
                profilePictureView.hexEncodedPublicKey = randomUsers.count >= 1 ? randomUsers[0] : ""
                profilePictureView.additionalHexEncodedPublicKey = randomUsers.count >= 2 ? randomUsers[1] : ""
                profilePictureView.isRSSFeed = false
            }
        } else { // A one-on-one chat
            profilePictureView.hexEncodedPublicKey = thread.contactIdentifier()!
            profilePictureView.additionalHexEncodedPublicKey = nil
            profilePictureView.isRSSFeed = false
        }
        profilePictureView.update()
    }
    
    @objc private func handleProfileChangedNotification(_ notification: Notification) {
        guard let hexEncodedPublicKey = notification.userInfo?[kNSNotificationKey_ProfileRecipientId] as? String, let thread = self.thread as? TSContactThread,
            hexEncodedPublicKey == thread.contactIdentifier() else { return }
        updateTitle()
        updateProfilePicture()
    }
    
    @objc private func handleCalculatingPoWNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .calculatingPoW, forMessageWithTimestamp: timestamp)
    }
    
    @objc private func handleRoutingNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .routing, forMessageWithTimestamp: timestamp)
    }
    
    @objc private func handleMessageSendingNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .messageSending, forMessageWithTimestamp: timestamp)
    }
    
    @objc private func handleMessageSentNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .messageSent, forMessageWithTimestamp: timestamp)
        handledMessageTimestamps.insert(timestamp)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.clearStatusIfNeededForMessageWithTimestamp(timestamp)
        }
    }
    
    @objc private func handleMessageFailedNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        clearStatusIfNeededForMessageWithTimestamp(timestamp)
    }
    
    private func setStatusIfNeeded(to status: Status, forMessageWithTimestamp timestamp: NSNumber) {
        guard !handledMessageTimestamps.contains(timestamp) else { return }
        var uncheckedTargetInteraction: TSInteraction? = nil
        thread.enumerateInteractions { interaction in
            guard interaction.timestamp == timestamp.uint64Value else { return }
            uncheckedTargetInteraction = interaction
        }
        guard let targetInteraction = uncheckedTargetInteraction, targetInteraction.interactionType() == .outgoingMessage,
            status.rawValue > (currentStatus?.rawValue ?? 0), let hexEncodedPublicKey = targetInteraction.thread.contactIdentifier() else { return }
        var masterHexEncodedPublicKey: String!
        let storage = OWSPrimaryStorage.shared()
        storage.dbReadConnection.read { transaction in
            masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: hexEncodedPublicKey, in: transaction) ?? hexEncodedPublicKey
        }
        let isSlaveDevice = masterHexEncodedPublicKey != hexEncodedPublicKey
        guard !isSlaveDevice else { return }
        currentStatus = status
    }
    
    private func clearStatusIfNeededForMessageWithTimestamp(_ timestamp: NSNumber) {
        var uncheckedTargetInteraction: TSInteraction? = nil
        OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
            guard let interactionsByThread = transaction.ext(TSMessageDatabaseViewExtensionName) as? YapDatabaseViewTransaction else { return }
            interactionsByThread.enumerateKeysAndObjects(inGroup: self.thread.uniqueId!) { _, _, object, _, _ in
                guard let interaction = object as? TSInteraction, interaction.timestamp == timestamp.uint64Value else { return }
                uncheckedTargetInteraction = interaction
            }
        }
        guard let targetInteraction = uncheckedTargetInteraction, targetInteraction.interactionType() == .outgoingMessage else { return }
        self.currentStatus = nil
    }
    
    @objc func updateSubtitleForCurrentStatus() {
        DispatchQueue.main.async {
            self.subtitleLabel.isHidden = false
            let subtitle = NSMutableAttributedString()
            if let muteEndDate = self.thread.mutedUntilDate, self.thread.isMuted {
                subtitle.append(NSAttributedString(string: "\u{e067}  ", attributes: [ .font : UIFont.ows_elegantIconsFont(10), .foregroundColor : Colors.unimportant ]))
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale.current
                dateFormatter.timeStyle = .medium
                dateFormatter.dateStyle = .medium
                subtitle.append(NSAttributedString(string: "Muted until " + dateFormatter.string(from: muteEndDate)))
            } else if let thread = self.thread as? TSGroupThread, !thread.isRSSFeed {
                let storage = OWSPrimaryStorage.shared()
                var userCount: Int?
                if thread.groupModel.groupType == .closedGroup {
                    userCount = GroupUtilities.getClosedGroupMemberCount(thread)
                } else if thread.groupModel.groupType == .openGroup {
                    storage.dbReadConnection.read { transaction in
                        if let publicChat = LokiDatabaseUtilities.getPublicChat(for: self.thread.uniqueId!, in: transaction) {
                            userCount = storage.getUserCount(for: publicChat, in: transaction)
                        }
                    }
                }
                if let userCount = userCount {
                    subtitle.append(NSAttributedString(string: "\(userCount) members"))
                } else if let hexEncodedPublicKey = (self.thread as? TSContactThread)?.contactIdentifier(), ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) {
                    subtitle.append(NSAttributedString(string: hexEncodedPublicKey))
                } else {
                    self.subtitleLabel.isHidden = true
                }
            }
            else {
                self.subtitleLabel.isHidden = true
            }
            self.subtitleLabel.attributedText = subtitle
            self.titleLabel.font = .boldSystemFont(ofSize: self.subtitleLabel.isHidden ? Values.veryLargeFontSize : Values.mediumFontSize)
        }
    }
    
    // MARK: Layout
    public override var intrinsicContentSize: CGSize {
        return UIView.layoutFittingExpandedSize
    }
}
