
final class NewConversationButtonSet : UIView {
    private var isUserDragging = false
    private var horizontalButtonConstraints: [NewConversationButton:NSLayoutConstraint] = [:]
    private var verticalButtonConstraints: [NewConversationButton:NSLayoutConstraint] = [:]
    private var expandedButton: NewConversationButton?
    var delegate: NewConversationButtonSetDelegate?
    
    // MARK: Settings
    private let spacing = Values.largeSpacing
    private let iconSize = CGFloat(24)
    private let maxDragDistance = CGFloat(56)
    
    // MARK: Components
    private lazy var mainButton = NewConversationButton(isMainButton: true, icon: #imageLiteral(resourceName: "Plus").scaled(to: CGSize(width: iconSize, height: iconSize)))
    private lazy var newPrivateChatButton = NewConversationButton(isMainButton: false, icon: #imageLiteral(resourceName: "Message").scaled(to: CGSize(width: iconSize, height: iconSize)))
    private lazy var newClosedGroupButton = NewConversationButton(isMainButton: false, icon: #imageLiteral(resourceName: "Group").scaled(to: CGSize(width: iconSize, height: iconSize)))
    private lazy var joinOpenGroupButton = NewConversationButton(isMainButton: false, icon: #imageLiteral(resourceName: "Globe").scaled(to: CGSize(width: iconSize, height: iconSize)))
    
    // MARK: Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        let inset = (Values.newConversationButtonExpandedSize - Values.newConversationButtonCollapsedSize) / 2
        addSubview(joinOpenGroupButton)
        horizontalButtonConstraints[joinOpenGroupButton] = joinOpenGroupButton.pin(.left, to: .left, of: self, withInset: inset)
        verticalButtonConstraints[joinOpenGroupButton] = joinOpenGroupButton.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        addSubview(newPrivateChatButton)
        newPrivateChatButton.center(.horizontal, in: self)
        verticalButtonConstraints[newPrivateChatButton] = newPrivateChatButton.pin(.top, to: .top, of: self, withInset: inset)
        addSubview(newClosedGroupButton)
        horizontalButtonConstraints[newClosedGroupButton] = newClosedGroupButton.pin(.right, to: .right, of: self, withInset: -inset)
        verticalButtonConstraints[newClosedGroupButton] = newClosedGroupButton.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        addSubview(mainButton)
        mainButton.center(.horizontal, in: self)
        mainButton.pin(.bottom, to: .bottom, of: self)
        let width = 3 * Values.newConversationButtonExpandedSize + 2 * spacing
        set(.width, to: width)
        let height = 2 * Values.newConversationButtonExpandedSize + spacing
        set(.height, to: height)
        collapse(withAnimation: false)
        isUserInteractionEnabled = true
        let mainButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleMainButtonTapped))
        mainButton.addGestureRecognizer(mainButtonTapGestureRecognizer)
        let joinOpenGroupButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleJoinOpenGroupButtonTapped))
        joinOpenGroupButton.addGestureRecognizer(joinOpenGroupButtonTapGestureRecognizer)
        let createNewPrivateChatButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCreateNewPrivateChatButtonTapped))
        newPrivateChatButton.addGestureRecognizer(createNewPrivateChatButtonTapGestureRecognizer)
        let createNewClosedGroupButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCreateNewClosedGroupButtonTapped))
        newClosedGroupButton.addGestureRecognizer(createNewClosedGroupButtonTapGestureRecognizer)
    }
    
    // MARK: Interaction
    @objc private func handleMainButtonTapped() { expand(isUserDragging: false) }
    @objc private func handleJoinOpenGroupButtonTapped() { delegate?.joinOpenGroup() }
    @objc private func handleCreateNewPrivateChatButtonTapped() { delegate?.createNewPrivateChat() }
    @objc private func handleCreateNewClosedGroupButtonTapped() { delegate?.createNewClosedGroup() }
    
    private func expand(isUserDragging: Bool) {
        let buttons = [ joinOpenGroupButton, newPrivateChatButton, newClosedGroupButton ]
        UIView.animate(withDuration: 0.25, animations: {
            buttons.forEach { $0.alpha = 1 }
            let inset = (Values.newConversationButtonExpandedSize - Values.newConversationButtonCollapsedSize) / 2
            let size = Values.newConversationButtonCollapsedSize
            self.joinOpenGroupButton.frame = CGRect(origin: CGPoint(x: inset, y: self.height() - size - inset), size: CGSize(width: size, height: size))
            self.newPrivateChatButton.frame = CGRect(center: CGPoint(x: self.bounds.center.x, y: inset + size / 2), size: CGSize(width: size, height: size))
            self.newClosedGroupButton.frame = CGRect(origin: CGPoint(x: self.width() - size - inset, y: self.height() - size - inset), size: CGSize(width: size, height: size))
        }, completion: { _ in
            self.isUserDragging = isUserDragging
        })
    }
    
    private func collapse(withAnimation isAnimated: Bool) {
        isUserDragging = false
        let buttons = [ joinOpenGroupButton, newPrivateChatButton, newClosedGroupButton ]
        UIView.animate(withDuration: isAnimated ? 0.25 : 0) {
            buttons.forEach { button in
                button.alpha = 0
                let size = Values.newConversationButtonCollapsedSize
                button.frame = CGRect(center: self.mainButton.center, size: CGSize(width: size, height: size))
            }
        }
    }
    
    private func reset() {
        let mainButtonLocationInSelfCoordinates = CGPoint(x: width() / 2, y: height() - Values.newConversationButtonExpandedSize / 2)
        let mainButtonSize = mainButton.frame.size
        UIView.animate(withDuration: 0.25) {
            self.mainButton.frame = CGRect(center: mainButtonLocationInSelfCoordinates, size: mainButtonSize)
            self.mainButton.alpha = 1
        }
        if let expandedButton = expandedButton { collapse(expandedButton) }
        expandedButton = nil
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
            self.collapse(withAnimation: true)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, mainButton.contains(touch), !isUserDragging else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        expand(isUserDragging: true)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, isUserDragging else { return }
        let mainButtonSize = mainButton.frame.size
        let mainButtonLocationInSelfCoordinates = CGPoint(x: width() / 2, y: height() - Values.newConversationButtonExpandedSize / 2)
        let touchLocationInSelfCoordinates = touch.location(in: self)
        mainButton.frame = CGRect(center: touchLocationInSelfCoordinates, size: mainButtonSize)
        mainButton.alpha = 1 - (touchLocationInSelfCoordinates.distance(to: mainButtonLocationInSelfCoordinates) / maxDragDistance)
        let buttons = [ joinOpenGroupButton, newPrivateChatButton, newClosedGroupButton ]
        let buttonToExpand = buttons.first { $0.contains(touch) }
        if let buttonToExpand = buttonToExpand {
            guard buttonToExpand != expandedButton else { return }
            if let expandedButton = expandedButton { collapse(expandedButton) }
            expand(buttonToExpand)
            expandedButton = buttonToExpand
        } else {
            if let expandedButton = expandedButton { collapse(expandedButton) }
            expandedButton = nil
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, isUserDragging else { return }
        if joinOpenGroupButton.contains(touch) { delegate?.joinOpenGroup() }
        else if newPrivateChatButton.contains(touch) { delegate?.createNewPrivateChat() }
        else if newClosedGroupButton.contains(touch) { delegate?.createNewClosedGroup() }
        reset()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserDragging else { return }
        reset()
    }
    
    private func expand(_ button: NewConversationButton) {
        if let horizontalConstraint = horizontalButtonConstraints[button] { horizontalConstraint.constant = 0 }
        if let verticalConstraint = verticalButtonConstraints[button] { verticalConstraint.constant = 0 }
        let size = Values.newConversationButtonExpandedSize
        let frame = CGRect(center: button.center, size: CGSize(width: size, height: size))
        button.widthConstraint.constant = size
        button.heightConstraint.constant = size
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
            button.frame = frame
            button.layer.cornerRadius = size / 2
            button.addGlow(ofSize: size)
            button.backgroundColor = Colors.accent
        }
    }
    
    private func collapse(_ button: NewConversationButton) {
        let inset = (Values.newConversationButtonExpandedSize - Values.newConversationButtonCollapsedSize) / 2
        if joinOpenGroupButton == expandedButton {
            horizontalButtonConstraints[joinOpenGroupButton]!.constant = inset
            verticalButtonConstraints[joinOpenGroupButton]!.constant = -inset
        } else if newPrivateChatButton == expandedButton {
            verticalButtonConstraints[newPrivateChatButton]!.constant = inset
        } else if newClosedGroupButton == expandedButton {
            horizontalButtonConstraints[newClosedGroupButton]!.constant = -inset
            verticalButtonConstraints[newClosedGroupButton]!.constant = -inset
        }
        let size = Values.newConversationButtonCollapsedSize
        let frame = CGRect(center: button.center, size: CGSize(width: size, height: size))
        button.widthConstraint.constant = size
        button.heightConstraint.constant = size
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
            button.frame = frame
            button.layer.cornerRadius = size / 2
            button.removeGlow()
            button.backgroundColor = Colors.newConversationButtonCollapsedBackground
        }
    }
}

// MARK: Delegate
protocol NewConversationButtonSetDelegate {
    
    func joinOpenGroup()
    func createNewPrivateChat()
    func createNewClosedGroup()
}

// MARK: Button
private final class NewConversationButton : UIImageView {
    private let isMainButton: Bool
    private let icon: UIImage
    var widthConstraint: NSLayoutConstraint!
    var heightConstraint: NSLayoutConstraint!
    
    // Initialization
    init(isMainButton: Bool, icon: UIImage) {
        self.isMainButton = isMainButton
        self.icon = icon
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(isMainButton:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(isMainButton:) instead.")
    }
    
    private func setUpViewHierarchy() {
        backgroundColor = isMainButton ? Colors.accent : Colors.newConversationButtonCollapsedBackground
        let size = isMainButton ? Values.newConversationButtonExpandedSize : Values.newConversationButtonCollapsedSize
        layer.cornerRadius = size / 2
        if isMainButton { addGlow(ofSize: size) }
        layer.masksToBounds = false
        image = icon
        contentMode = .center
        widthConstraint = set(.width, to: size)
        heightConstraint = set(.height, to: size)
    }
    
    // General
    func addGlow(ofSize size: CGFloat) {
        layer.shadowPath = UIBezierPath(ovalIn: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: size, height: size))).cgPath
        layer.shadowColor = Colors.newConversationButtonShadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 0.8)
        layer.shadowOpacity = 1
        layer.shadowRadius = 6
    }
    
    func removeGlow() {
        layer.shadowPath = nil
        layer.shadowColor = nil
        layer.shadowOffset = CGSize.zero
        layer.shadowOpacity = 0
        layer.shadowRadius = 0
    }
}

// MARK: Convenience
private extension UIView {
    
    func contains(_ touch: UITouch) -> Bool {
        return bounds.contains(touch.location(in: self))
    }
}

private extension CGPoint {
    
    func distance(to otherPoint: CGPoint) -> CGFloat {
        return sqrt(pow(self.x - otherPoint.x, 2) + pow(self.y - otherPoint.y, 2))
    }
}

private extension CGRect {
    
    init(center: CGPoint, size: CGSize) {
        let originX = center.x - size.width / 2
        let originY = center.y - size.height / 2
        let origin = CGPoint(x: originX, y: originY)
        self.init(origin: origin, size: size)
    }
}
