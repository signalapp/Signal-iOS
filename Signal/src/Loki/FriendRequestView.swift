
@objc final class FriendRequestView : UIView {
    @objc var message: TSMessage! { didSet { handleMessageChanged() } }
    @objc weak var delegate: FriendRequestViewDelegate?
    private let kind: Kind

    // MARK: Types
    enum Kind : String { case incoming, outgoing }
    
    // MARK: Components
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
    init(kind: Kind) {
        self.kind = kind
        super.init(frame: CGRect.zero)
        initialize()
    }
    
    @objc convenience init?(rawKind: String) {
        guard let kind = Kind(rawValue: rawKind) else { return nil }
        self.init(kind: kind)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Using FriendRequestView.init(coder:) isn't allowed. Use FriendRequestView.init(kind:) instead.")
    }
    
    override init(frame: CGRect) {
        fatalError("Using FriendRequestView.init(frame:) isn't allowed. Use FriendRequestView.init(kind:) instead.")
    }
    
    private func initialize() {
        let mainStackView = UIStackView()
        mainStackView.axis = .vertical
        mainStackView.distribution = .fill
        mainStackView.addArrangedSubview(label)
        switch kind {
        case .incoming:
            mainStackView.addArrangedSubview(buttonStackView)
            let acceptButton = OWSFlatButton.button(title: NSLocalizedString("Accept", comment: ""), font: buttonFont, titleColor: .ows_materialBlue, backgroundColor: .white, target: self, selector: #selector(accept))
            acceptButton.autoSetDimension(.height, toSize: buttonHeight)
            buttonStackView.addArrangedSubview(acceptButton)
            let declineButton = OWSFlatButton.button(title: NSLocalizedString("Decline", comment: ""), font: buttonFont, titleColor: .ows_destructiveRed, backgroundColor: .white, target: self, selector: #selector(decline))
            declineButton.autoSetDimension(.height, toSize: buttonHeight)
            buttonStackView.addArrangedSubview(declineButton)
        case .outgoing: break
        }
        addSubview(mainStackView)
        mainStackView.autoPin(toEdgesOf: self)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFriendRequestStatusChangedNotification), name: .messageFriendRequestStatusChanged, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Updating
    @objc private func handleFriendRequestStatusChangedNotification(_ notification: Notification) {
        guard let messageID = notification.object as? String, messageID == message?.uniqueId else { return }
        message.reload()
        handleMessageChanged()
    }
    
    @objc private func handleMessageChanged() {
        precondition(message != nil)
        switch kind {
        case .incoming:
            guard let message = message as? TSIncomingMessage else { preconditionFailure() }
            buttonStackView.isHidden = !(message.friendRequestStatus == .pending)
            let format: String = {
                switch (message.friendRequestStatus) {
                case .accepted: return NSLocalizedString("You've accepted %@'s friend request", comment: "")
                case .declined: return NSLocalizedString("You've declined %@'s friend request", comment: "")
                case .expired: return NSLocalizedString("%@'s friend request has expired", comment: "")
                default: return NSLocalizedString("%@ sent you a friend request", comment: "")
                }
            }()
            label.text = String(format: format, message.authorId)
        case .outgoing:
            guard let message = message as? TSOutgoingMessage else { preconditionFailure() }
            let format: String = {
                switch (message.friendRequestStatus) {
                case .accepted: return NSLocalizedString("%@ accepted your friend request", comment: "")
                case .expired: return NSLocalizedString("Your friend request to %@ has expired", comment: "")
                default: return NSLocalizedString("You've sent %@ a friend request", comment: "")
                }
            }()
            label.text = String(format: format, message.thread.contactIdentifier()!)
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
        let topSpacing: CGFloat = 12
        let kind: Kind = {
            switch (message) {
            case is TSIncomingMessage: return .incoming
            case is TSOutgoingMessage: return .outgoing
            default: preconditionFailure()
            }
        }()
        let dummyFriendRequestView = FriendRequestView(kind: kind)
        dummyFriendRequestView.message = message
        let messageHeight = dummyFriendRequestView.label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        let totalHeight: CGFloat = {
            switch kind {
            case .incoming:
                let buttonHeight = dummyFriendRequestView.buttonStackView.isHidden ? 0 : dummyFriendRequestView.buttonHeight
                return topSpacing + messageHeight + buttonHeight
            case .outgoing:
                return topSpacing + messageHeight
            }
        }()
        return totalHeight.rounded(.up)
    }
}
