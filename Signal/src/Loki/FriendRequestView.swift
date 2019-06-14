
@objc final class FriendRequestView : UIView {
    private let message: TSMessage
    @objc weak var delegate: FriendRequestViewDelegate?

    private var kind: Kind {
        let isIncoming = message.interactionType() == .incomingMessage
        return isIncoming ? .incoming : .outgoing
    }

    // MARK: Types
    enum Kind : String { case incoming, outgoing }
    
    // MARK: Components
    private lazy var topSpacer: UIView = {
        let result = UIView()
        result.autoSetDimension(.height, toSize: 12)
        return result
    }()
    
    private lazy var label: UILabel = {
        let result = UILabel()
        result.textColor = Theme.secondaryColor
        result.font = UIFont.ows_dynamicTypeSubheadlineClamped
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var buttonStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.distribution = .fillEqually
        return result
    }()

    private lazy var buttonFont = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
    private lazy var buttonHeight = buttonFont.pointSize * 48 / 17
    
    // MARK: Initialization
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
        mainStackView.addArrangedSubview(topSpacer)
        mainStackView.addArrangedSubview(label)
        switch kind {
        case .incoming:
            mainStackView.addArrangedSubview(buttonStackView)
            let acceptButton = OWSFlatButton.button(title: NSLocalizedString("Accept", comment: ""), font: buttonFont, titleColor: .ows_materialBlue, backgroundColor: .white, target: self, selector: #selector(accept))
            acceptButton.setBackgroundColors(upColor: .clear, downColor: .clear)
            acceptButton.autoSetDimension(.height, toSize: buttonHeight)
            buttonStackView.addArrangedSubview(acceptButton)
            let declineButton = OWSFlatButton.button(title: NSLocalizedString("Decline", comment: ""), font: buttonFont, titleColor: .ows_destructiveRed, backgroundColor: .white, target: self, selector: #selector(decline))
            declineButton.setBackgroundColors(upColor: .clear, downColor: .clear)
            declineButton.autoSetDimension(.height, toSize: buttonHeight)
            buttonStackView.addArrangedSubview(declineButton)
        case .outgoing: break
        }
        addSubview(mainStackView)
        mainStackView.autoPin(toEdgesOf: self)
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
        guard messageID == message.uniqueId else { return }
        message.reload()
        updateUI()
    }
    
    private func updateUI() {
        switch kind {
        case .incoming:
            guard let message = message as? TSIncomingMessage else { preconditionFailure() }
            buttonStackView.isHidden = message.friendRequestStatus != .pending
            let format: String = {
                switch (message.friendRequestStatus) {
                case .none, .sendingOrFailed: preconditionFailure()
                case .pending: return NSLocalizedString("%@ sent you a friend request", comment: "")
                case .accepted: return NSLocalizedString("You've accepted %@'s friend request", comment: "")
                case .declined: return NSLocalizedString("You've declined %@'s friend request", comment: "")
                case .expired: return NSLocalizedString("%@'s friend request has expired", comment: "")
                default: preconditionFailure()
                }
            }()
            let contactID = message.authorId
            let displayName = Environment.shared.contactsManager.profileName(forRecipientId: contactID) ?? contactID
            label.text = String(format: format, displayName)
        case .outgoing:
            guard let message = message as? TSOutgoingMessage else { preconditionFailure() }
            let format: String? = {
                switch (message.friendRequestStatus) {
                case .none: preconditionFailure()
                case .sendingOrFailed: return nil
                case .pending: return NSLocalizedString("You've sent %@ a friend request", comment: "")
                case .accepted: return NSLocalizedString("%@ accepted your friend request", comment: "")
                case .declined: preconditionFailure()
                case .expired: return NSLocalizedString("Your friend request to %@ has expired", comment: "")
                default: preconditionFailure()
                }
            }()
            if let format = format {
                let contactID = message.thread.contactIdentifier()!
                let displayName = Environment.shared.contactsManager.profileName(forRecipientId: contactID) ?? contactID
                label.text = String(format: format, displayName)
            }
            label.isHidden = (format == nil)
            topSpacer.isHidden = (label.isHidden)
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
        let width = conversationStyle.contentWidth
        let dummyFriendRequestView = FriendRequestView(message: message)
        let hasTopSpacer = !dummyFriendRequestView.topSpacer.isHidden
        let topSpacing: CGFloat = hasTopSpacer ? 12 : 0
        let hasLabel = !dummyFriendRequestView.label.isHidden
        let labelHeight = hasLabel ? dummyFriendRequestView.label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height : 0
        let hasButtonStackView = dummyFriendRequestView.buttonStackView.superview != nil && !dummyFriendRequestView.buttonStackView.isHidden
        let buttonHeight = hasButtonStackView ? dummyFriendRequestView.buttonHeight : 0
        let totalHeight = topSpacing + labelHeight + buttonHeight
        return totalHeight.rounded(.up)
    }
}
