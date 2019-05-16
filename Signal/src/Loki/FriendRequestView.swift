
@objc final class FriendRequestView : UIView {
    @objc var message: TSMessage! { didSet { handleMessageChanged() } }
    @objc weak var delegate: FriendRequestViewDelegate?
    private let kind: Kind

    private var didAcceptRequest: Bool {
        guard let message = message as? TSIncomingMessage else { preconditionFailure() }
        return message.thread.friendRequestStatus == .friends
    }

    private var didDeclineRequest: Bool {
        guard let message = message as? TSIncomingMessage else { preconditionFailure() }
        return message.thread.friendRequestStatus == .none
    }

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
    }
    
    // MARK: Updating
    private func handleMessageChanged() {
        precondition(message != nil)
        switch kind {
        case .incoming:
            guard let message = message as? TSIncomingMessage else { preconditionFailure() }
            buttonStackView.isHidden = didDeclineRequest
            let text: String = {
                if didAcceptRequest {
                    return String(format: NSLocalizedString("You've accepted %@'s friend request", comment: ""), message.authorId)
                } else if didDeclineRequest {
                    return String(format: NSLocalizedString("You've declined %@'s friend request", comment: ""), message.authorId)
                } else {
                    return String(format: NSLocalizedString("%@ sent you a friend request", comment: ""), message.authorId)
                }
            }()
            label.text = text
        case .outgoing:
            guard let message = message as? TSOutgoingMessage else { preconditionFailure() }
            label.text = String(format: NSLocalizedString("You've sent %@ a friend request", comment: ""), message.thread.contactIdentifier()!)
        }
    }
    
    // MARK: Interaction
    @objc private func accept() {
        guard let message = message as? TSIncomingMessage else { preconditionFailure() }
        delegate?.acceptFriendRequest(message)
    }
    
    @objc private func decline() {
        guard let message = message as? TSIncomingMessage else { preconditionFailure() }
        delegate?.declineFriendRequest(message)
        handleMessageChanged() // Update UI
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
