
@objc final class FriendRequestView : UIView {
    @objc var message: TSIncomingMessage! { didSet { handleMessageChanged() } }
    @objc weak var delegate: FriendRequestViewDelegate?
    
    // MARK: Components
    private lazy var buttonFont = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
    private lazy var buttonHeight = buttonFont.pointSize * 48 / 17
    
    private lazy var label: UILabel = {
        let result = UILabel()
        result.textColor = Theme.secondaryColor
        result.font = UIFont.ows_dynamicTypeSubheadlineClamped
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        return result
    }()
    
    // MARK: Initialization
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    private func initialize() {
        let mainStackView = UIStackView()
        mainStackView.axis = .vertical
        mainStackView.distribution = .fill
        mainStackView.addArrangedSubview(label)
        let buttonStackView = UIStackView()
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
        mainStackView.addArrangedSubview(buttonStackView)
        let acceptButton = OWSFlatButton.button(title: NSLocalizedString("Accept", comment: ""), font: buttonFont, titleColor: .ows_materialBlue, backgroundColor: .white, target: self, selector: #selector(accept))
        acceptButton.autoSetDimension(.height, toSize: buttonHeight)
        buttonStackView.addArrangedSubview(acceptButton)
        let declineButton = OWSFlatButton.button(title: NSLocalizedString("Decline", comment: ""), font: buttonFont, titleColor: .ows_destructiveRed, backgroundColor: .white, target: self, selector: #selector(decline))
        declineButton.autoSetDimension(.height, toSize: buttonHeight)
        buttonStackView.addArrangedSubview(declineButton)
        addSubview(mainStackView)
        mainStackView.autoPin(toEdgesOf: self)
    }
    
    // MARK: Updating
    private func handleMessageChanged() {
        assert(message != nil)
        label.text = String(format: NSLocalizedString("%@ sent you a friend request", comment: ""), message.authorId)
    }
    
    // MARK: Interaction
    @objc private func accept() {
        delegate?.acceptFriendRequest(message)
    }
    
    @objc private func decline() {
        delegate?.declineFriendRequest(message)
    }
    
    // MARK: Measuring
    @objc static func calculateHeight(message: TSIncomingMessage, conversationStyle: ConversationStyle) -> CGFloat {
        let width = conversationStyle.contentWidth
        let topSpacing: CGFloat = 12
        let dummyFriendRequestView = FriendRequestView()
        dummyFriendRequestView.message = message
        let messageHeight = dummyFriendRequestView.label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        let buttonHeight = dummyFriendRequestView.buttonHeight
        let totalHeight = topSpacing + messageHeight + buttonHeight
        return totalHeight.rounded(.up)
    }
}
