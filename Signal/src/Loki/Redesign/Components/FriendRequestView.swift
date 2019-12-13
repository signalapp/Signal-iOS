
@objc(LKFriendRequestView)
final class FriendRequestView : UIView {
    private let message: TSMessage
    @objc weak var delegate: FriendRequestViewDelegate?

    private var kind: Kind {
        let isIncoming = message.interactionType() == .incomingMessage
        return isIncoming ? .incoming : .outgoing
    }

    // MARK: Types
    enum Kind : String { case incoming, outgoing }
    
    // MARK: Components
    private lazy var spacer1: UIView = {
        let result = UIView()
        result.set(.height, to: 12)
        return result
    }()
    
    private lazy var spacer2: UIView = {
        let result = UIView()
        result.set(.height, to: Values.mediumSpacing)
        return result
    }()
    
    private lazy var label: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var buttonStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.spacing = Values.mediumSpacing
        result.distribution = .fillEqually
        return result
    }()
    
    // MARK: Lifecycle
    @objc init(message: TSMessage) {
        self.message = message
        super.init(frame: CGRect.zero)
        initialize()
    }
    
    required init?(coder: NSCoder) { fatalError("Using FriendRequestView.init(coder:) isn't allowed. Use FriendRequestView.init(message:) instead.") }
    override init(frame: CGRect) { fatalError("Using FriendRequestView.init(frame:) isn't allowed. Use FriendRequestView.init(message:) instead.") }
    
    private func initialize() {
        // Set up UI
        let mainStackView = UIStackView()
        mainStackView.axis = .vertical
        mainStackView.distribution = .fill
        mainStackView.layoutMargins = UIEdgeInsets(top: 0, left: Values.largeSpacing, bottom: 0, right: Values.largeSpacing)
        mainStackView.isLayoutMarginsRelativeArrangement = true
        mainStackView.addArrangedSubview(spacer1)
        mainStackView.addArrangedSubview(label)
        switch kind {
        case .incoming:
            mainStackView.addArrangedSubview(spacer2)
            mainStackView.addArrangedSubview(buttonStackView)
            let declineButton = UIButton()
            declineButton.set(.height, to: Values.mediumButtonHeight)
            declineButton.layer.cornerRadius = Values.modalButtonCornerRadius
            declineButton.backgroundColor = Colors.buttonBackground
            declineButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
            declineButton.setTitleColor(Colors.text, for: UIControl.State.normal)
            declineButton.setTitle(NSLocalizedString("Decline", comment: ""), for: UIControl.State.normal)
            declineButton.addTarget(self, action: #selector(decline), for: UIControl.Event.touchUpInside)
            buttonStackView.addArrangedSubview(declineButton)
            let acceptButton = UIButton()
            acceptButton.set(.height, to: Values.mediumButtonHeight)
            acceptButton.layer.cornerRadius = Values.modalButtonCornerRadius
            acceptButton.backgroundColor = Colors.accent
            acceptButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
            acceptButton.setTitleColor(Colors.text, for: UIControl.State.normal)
            acceptButton.setTitle(NSLocalizedString("Accept", comment: ""), for: UIControl.State.normal)
            acceptButton.addTarget(self, action: #selector(accept), for: UIControl.Event.touchUpInside)
            buttonStackView.addArrangedSubview(acceptButton)
        case .outgoing: break
        }
        addSubview(mainStackView)
        mainStackView.pin(to: self)
        updateUI()
        // Observe friend request status changes
        NotificationCenter.default.addObserver(self, selector: #selector(handleFriendRequestStatusChangedNotification), name: .messageFriendRequestStatusChanged, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Updating
    @objc private func handleFriendRequestStatusChangedNotification(_ notification: Notification) {
        let messageID = notification.object as! String
        guard messageID == message.uniqueId && TSMessage.fetch(uniqueId: messageID) != nil else { return } // It's possible for the message to be deleted at this point
        message.reload()
        updateUI()
    }
    
    private func updateUI() {
        switch kind {
        case .incoming:
            guard let message = message as? TSIncomingMessage else { preconditionFailure() }
            buttonStackView.isHidden = message.friendRequestStatus != .pending
            spacer2.isHidden = buttonStackView.isHidden
            let format: String = {
                switch (message.friendRequestStatus) {
                case .none, .sendingOrFailed: preconditionFailure()
                case .pending: return NSLocalizedString("%@ sent you a message request", comment: "")
                case .accepted: return NSLocalizedString("You've accepted %@'s message request", comment: "")
                case .declined: return NSLocalizedString("You've declined %@'s message request", comment: "")
                case .expired: return NSLocalizedString("%@'s message request has expired", comment: "")
                default: preconditionFailure()
                }
            }()
            let contactID = message.authorId
            let displayName = DisplayNameUtilities.getPrivateChatDisplayName(for: contactID) ?? contactID
            label.text = String(format: format, displayName)
        case .outgoing:
            guard let message = message as? TSOutgoingMessage else { preconditionFailure() }
            let format: String? = {
                switch (message.friendRequestStatus) {
                case .none: preconditionFailure()
                case .sendingOrFailed: return nil
                case .pending: return NSLocalizedString("You've sent %@ a message request", comment: "")
                case .accepted: return NSLocalizedString("%@ accepted your message request", comment: "")
                case .declined: preconditionFailure()
                case .expired: return NSLocalizedString("Your message request to %@ has expired", comment: "")
                default: preconditionFailure()
                }
            }()
            if let format = format {
                let contactID = message.thread.contactIdentifier()!
                let displayName = DisplayNameUtilities.getPrivateChatDisplayName(for: contactID) ?? contactID
                label.text = String(format: format, displayName)
            }
            label.isHidden = (format == nil)
            spacer1.isHidden = (label.isHidden)
        }
    }
    
    // MARK: Interaction
    @objc private func accept() {
        guard let message = message as? TSIncomingMessage else { preconditionFailure() }
        message.saveFriendRequestStatus(.accepted, with: nil)
        delegate?.acceptFriendRequest(message)
    }
    
    @objc private func decline() {
        guard let message = message as? TSIncomingMessage else { preconditionFailure() }
        message.saveFriendRequestStatus(.declined, with: nil)
        delegate?.declineFriendRequest(message)
    }
    
    // MARK: Measuring
    @objc static func calculateHeight(message: TSMessage, conversationStyle: ConversationStyle) -> CGFloat {
        let width = conversationStyle.contentWidth - 2 * Values.largeSpacing
        let dummyFriendRequestView = FriendRequestView(message: message)
        let hasTopSpacer = !dummyFriendRequestView.spacer1.isHidden
        let topSpacing: CGFloat = hasTopSpacer ? 12 : 0
        let hasLabel = !dummyFriendRequestView.label.isHidden
        let labelHeight = hasLabel ? dummyFriendRequestView.label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height : 0
        let hasButtonStackView = dummyFriendRequestView.buttonStackView.superview != nil && !dummyFriendRequestView.buttonStackView.isHidden
        let buttonHeight = hasButtonStackView ? Values.mediumButtonHeight + Values.mediumSpacing : 0 // Values.mediumSpacing is the height of the spacer
        let totalHeight = topSpacing + labelHeight + buttonHeight
        return totalHeight.rounded(.up)
    }
}
