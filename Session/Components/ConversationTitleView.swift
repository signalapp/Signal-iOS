
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
        let size: CGFloat = 40
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
        notificationCenter.addObserver(self, selector: #selector(handleCalculatingMessagePoWNotification(_:)), name: .calculatingMessagePoW, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleEncryptingMessageNotification(_:)), name: .encryptingMessage, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleMessageSendingNotification(_:)), name: .messageSending, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleMessageSentNotification(_:)), name: .messageSent, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleMessageSendingFailedNotification(_:)), name: .messageSendingFailed, object: nil)
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
        profilePictureView.update(for: thread)
    }
    
    @objc private func handleProfileChangedNotification(_ notification: Notification) {
        guard let hexEncodedPublicKey = notification.userInfo?[kNSNotificationKey_ProfileRecipientId] as? String, let thread = self.thread as? TSContactThread,
            hexEncodedPublicKey == thread.contactIdentifier() else { return }
        updateTitle()
        updateProfilePicture()
    }
    
    @objc private func handleCalculatingMessagePoWNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .calculatingPoW, forMessageWithTimestamp: timestamp)
    }
    
    @objc private func handleEncryptingMessageNotification(_ notification: Notification) {
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
    
    @objc private func handleMessageSendingFailedNotification(_ notification: Notification) {
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
            status.rawValue > (currentStatus?.rawValue ?? 0) else { return }
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
            } else if let thread = self.thread as? TSGroupThread {
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
