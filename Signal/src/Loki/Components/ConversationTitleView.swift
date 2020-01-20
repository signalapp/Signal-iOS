
@objc final class ConversationTitleView : UIView {
    private let thread: TSThread
    private var currentStatus: Status? { didSet { updateSubtitleForCurrentStatus() } }
    
    // MARK: Types
    private enum Status : Int {
        case calculatingPoW = 1
        case contactingNetwork = 2
        case sendingMessage = 3
        case messageSent = 4
        case messageFailed = 5
    }
    
    // MARK: Components
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
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    // MARK: Lifecycle
    @objc init(thread: TSThread) {
        self.thread = thread
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
        updateTitle()
        updateSubtitleForCurrentStatus()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleProfileChangedNotification(_:)), name: NSNotification.Name(rawValue: kNSNotificationName_OtherUsersProfileDidChange), object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleCalculatingPoWNotification(_:)), name: .calculatingPoW, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleContactingNetworkNotification(_:)), name: .contactingNetwork, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleSendingMessageNotification(_:)), name: .sendingMessage, object: nil)
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
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 0) // Compensate for settings button trailing margin
        stackView.isLayoutMarginsRelativeArrangement = true
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
                title = NSLocalizedString("New Group", comment: "")
            } else {
                title = thread.name()
            }
        } else {
            if thread.isNoteToSelf() {
                title = NSLocalizedString("Note to Self", comment: "")
            } else {
                let hexEncodedPublicKey = thread.contactIdentifier()!
                title = DisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? hexEncodedPublicKey
            }
        }
        titleLabel.text = title
    }
    
    @objc private func handleProfileChangedNotification(_ notification: Notification) {
        guard let hexEncodedPublicKey = notification.userInfo?[kNSNotificationKey_ProfileRecipientId] as? String, let thread = self.thread as? TSContactThread,
            hexEncodedPublicKey == thread.contactIdentifier() else { return }
        updateTitle()
    }
    
    @objc private func handleCalculatingPoWNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .calculatingPoW, forMessageWithTimestamp: timestamp)
    }
    
    @objc private func handleContactingNetworkNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .contactingNetwork, forMessageWithTimestamp: timestamp)
    }
    
    @objc private func handleSendingMessageNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .sendingMessage, forMessageWithTimestamp: timestamp)
    }
    
    @objc private func handleMessageSentNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        setStatusIfNeeded(to: .messageSent, forMessageWithTimestamp: timestamp)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.clearStatusIfNeededForMessageWithTimestamp(timestamp)
        }
    }
    
    @objc private func handleMessageFailedNotification(_ notification: Notification) {
        guard let timestamp = notification.object as? NSNumber else { return }
        clearStatusIfNeededForMessageWithTimestamp(timestamp)
    }
    
    private func setStatusIfNeeded(to status: Status, forMessageWithTimestamp timestamp: NSNumber) {
        var uncheckedTargetInteraction: TSInteraction? = nil
        thread.enumerateInteractions { interaction in
            guard interaction.timestamp == timestamp.uint64Value else { return }
            uncheckedTargetInteraction = interaction
        }
        guard let targetInteraction = uncheckedTargetInteraction, targetInteraction.interactionType() == .outgoingMessage, status.rawValue > (currentStatus?.rawValue ?? 0) else { return }
        currentStatus = status
    }
    
    private func clearStatusIfNeededForMessageWithTimestamp(_ timestamp: NSNumber) {
        var uncheckedTargetInteraction: TSInteraction? = nil
        thread.enumerateInteractions { interaction in
            guard interaction.timestamp == timestamp.uint64Value else { return }
            uncheckedTargetInteraction = interaction
        }
        guard let targetInteraction = uncheckedTargetInteraction, targetInteraction.interactionType() == .outgoingMessage else { return }
        self.currentStatus = nil
    }
    
    private func updateSubtitleForCurrentStatus() {
        DispatchQueue.main.async {
            self.subtitleLabel.isHidden = false
            switch self.currentStatus {
            case .calculatingPoW: self.subtitleLabel.text = NSLocalizedString("Encrypting message", comment: "")
            case .contactingNetwork: self.subtitleLabel.text = NSLocalizedString("Tracing a path", comment: "")
            case .sendingMessage: self.subtitleLabel.text = NSLocalizedString("Sending message", comment: "")
            case .messageSent: self.subtitleLabel.text = NSLocalizedString("Message sent securely", comment: "")
            case .messageFailed: self.subtitleLabel.text = NSLocalizedString("Message failed to send", comment: "")
            case nil:
                let subtitle = NSMutableAttributedString()
                if let muteEndDate = self.thread.mutedUntilDate {
                    subtitle.append(NSAttributedString(string: "\u{e067}  ", attributes: [ .font : UIFont.ows_elegantIconsFont(10), .foregroundColor : Colors.unimportant ]))
                    let dateFormatter = DateFormatter()
                    dateFormatter.locale = Locale.current
                    dateFormatter.timeStyle = .medium
                    dateFormatter.dateStyle = .medium
                    subtitle.append(NSAttributedString(string: "Muted until " + dateFormatter.string(from: muteEndDate)))
                } else if self.thread.isGroupThread() {
                    subtitle.append(NSAttributedString(string: "26 members")) // TODO: Implement
                } else {
                    self.subtitleLabel.isHidden = true
                }
                self.subtitleLabel.attributedText = subtitle
            }
        }
    }
    
    // MARK: Layout
    public override var intrinsicContentSize: CGSize {
        return UIView.layoutFittingExpandedSize
    }
}
