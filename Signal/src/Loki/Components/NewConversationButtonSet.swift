
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
    private let dragMargin = CGFloat(16)
    
    // MARK: Components
    private lazy var mainButton = NewConversationButton(isMainButton: true, icon: #imageLiteral(resourceName: "Plus").scaled(to: CGSize(width: iconSize, height: iconSize)))
    private lazy var createNewPrivateChatButton = NewConversationButton(isMainButton: false, icon: #imageLiteral(resourceName: "Message").scaled(to: CGSize(width: iconSize, height: iconSize)))
    private lazy var createNewClosedGroupButton = NewConversationButton(isMainButton: false, icon: #imageLiteral(resourceName: "Group").scaled(to: CGSize(width: iconSize, height: iconSize)))
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
        addSubview(createNewPrivateChatButton)
        createNewPrivateChatButton.center(.horizontal, in: self)
        verticalButtonConstraints[createNewPrivateChatButton] = createNewPrivateChatButton.pin(.top, to: .top, of: self, withInset: inset)
        addSubview(createNewClosedGroupButton)
        horizontalButtonConstraints[createNewClosedGroupButton] = createNewClosedGroupButton.pin(.right, to: .right, of: self, withInset: -inset)
        verticalButtonConstraints[createNewClosedGroupButton] = createNewClosedGroupButton.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        addSubview(mainButton)
        mainButton.center(.horizontal, in: self)
        mainButton.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        let width = 2 * Values.newConversationButtonExpandedSize + 2 * spacing + Values.newConversationButtonCollapsedSize
        set(.width, to: width)
        let height = Values.newConversationButtonExpandedSize + spacing + Values.newConversationButtonCollapsedSize
        set(.height, to: height)
        collapse(withAnimation: false)
        isUserInteractionEnabled = true
        let joinOpenGroupButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleJoinOpenGroupButtonTapped))
        joinOpenGroupButton.addGestureRecognizer(joinOpenGroupButtonTapGestureRecognizer)
        let createNewPrivateChatButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCreateNewPrivateChatButtonTapped))
        createNewPrivateChatButton.addGestureRecognizer(createNewPrivateChatButtonTapGestureRecognizer)
        let createNewClosedGroupButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCreateNewClosedGroupButtonTapped))
        createNewClosedGroupButton.addGestureRecognizer(createNewClosedGroupButtonTapGestureRecognizer)
    }
    
    // MARK: Interaction
    @objc private func handleJoinOpenGroupButtonTapped() { delegate?.joinOpenGroup() }
    @objc private func handleCreateNewPrivateChatButtonTapped() { delegate?.createNewPrivateChat() }
    @objc private func handleCreateNewClosedGroupButtonTapped() { delegate?.createNewClosedGroup() }
    
    private func expand(isUserDragging: Bool) {
        let buttons = [ joinOpenGroupButton, createNewPrivateChatButton, createNewClosedGroupButton ]
        UIView.animate(withDuration: 0.25, animations: {
            buttons.forEach { $0.alpha = 1 }
            let inset = (Values.newConversationButtonExpandedSize - Values.newConversationButtonCollapsedSize) / 2
            let size = Values.newConversationButtonCollapsedSize
            self.joinOpenGroupButton.frame = CGRect(origin: CGPoint(x: inset, y: self.height() - size - inset), size: CGSize(width: size, height: size))
            self.createNewPrivateChatButton.frame = CGRect(center: CGPoint(x: self.bounds.center.x, y: inset + size / 2), size: CGSize(width: size, height: size))
            self.createNewClosedGroupButton.frame = CGRect(origin: CGPoint(x: self.width() - size - inset, y: self.height() - size - inset), size: CGSize(width: size, height: size))
        }, completion: { _ in
            self.isUserDragging = isUserDragging
        })
    }
    
    private func collapse(withAnimation isAnimated: Bool) {
        isUserDragging = false
        let buttons = [ joinOpenGroupButton, createNewPrivateChatButton, createNewClosedGroupButton ]
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
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        expand(isUserDragging: true)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, isUserDragging else { return }
        let mainButtonSize = mainButton.frame.size
        let mainButtonLocationInSelfCoordinates = CGPoint(x: width() / 2, y: height() - Values.newConversationButtonExpandedSize / 2)
        let touchLocationInSelfCoordinates = touch.location(in: self)
        mainButton.frame = CGRect(center: touchLocationInSelfCoordinates, size: mainButtonSize)
        mainButton.alpha = 1 - (touchLocationInSelfCoordinates.distance(to: mainButtonLocationInSelfCoordinates) / maxDragDistance)
        let buttons = [ joinOpenGroupButton, createNewPrivateChatButton, createNewClosedGroupButton ]
        let buttonToExpand = buttons.first { button in
            var hasUserDraggedBeyondButton = false
            if button == joinOpenGroupButton && touch.isLeft(of: joinOpenGroupButton, with: dragMargin) { hasUserDraggedBeyondButton = true }
            if button == createNewPrivateChatButton && touch.isAbove(createNewPrivateChatButton, with: dragMargin) { hasUserDraggedBeyondButton = true }
            if button == createNewClosedGroupButton && touch.isRight(of: createNewClosedGroupButton, with: dragMargin) { hasUserDraggedBeyondButton = true }
            return button.contains(touch) || hasUserDraggedBeyondButton
        }
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
        if joinOpenGroupButton.contains(touch) || touch.isLeft(of: joinOpenGroupButton, with: dragMargin) { delegate?.joinOpenGroup() }
        else if createNewPrivateChatButton.contains(touch) || touch.isAbove(createNewPrivateChatButton, with: dragMargin) { delegate?.createNewPrivateChat() }
        else if createNewClosedGroupButton.contains(touch) || touch.isRight(of: createNewClosedGroupButton, with: dragMargin) { delegate?.createNewClosedGroup() }
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
            let glowColor = Colors.newConversationButtonShadow
            let glowConfiguration = UIView.CircularGlowConfiguration(size: size, color: glowColor, isAnimated: true, radius: isLightMode ? 4 : 6)
            button.setCircularGlow(with: glowConfiguration)
            button.backgroundColor = Colors.accent
        }
    }
    
    private func collapse(_ button: NewConversationButton) {
        let inset = (Values.newConversationButtonExpandedSize - Values.newConversationButtonCollapsedSize) / 2
        if joinOpenGroupButton == expandedButton {
            horizontalButtonConstraints[joinOpenGroupButton]!.constant = inset
            verticalButtonConstraints[joinOpenGroupButton]!.constant = -inset
        } else if createNewPrivateChatButton == expandedButton {
            verticalButtonConstraints[createNewPrivateChatButton]!.constant = inset
        } else if createNewClosedGroupButton == expandedButton {
            horizontalButtonConstraints[createNewClosedGroupButton]!.constant = -inset
            verticalButtonConstraints[createNewClosedGroupButton]!.constant = -inset
        }
        let size = Values.newConversationButtonCollapsedSize
        let frame = CGRect(center: button.center, size: CGSize(width: size, height: size))
        button.widthConstraint.constant = size
        button.heightConstraint.constant = size
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
            button.frame = frame
            button.layer.cornerRadius = size / 2
            let glowColor = isLightMode ? UIColor.black.withAlphaComponent(0.4) : UIColor.black
            let glowConfiguration = UIView.CircularGlowConfiguration(size: size, color: glowColor, isAnimated: true, radius: isLightMode ? 4 : 6)
            button.setCircularGlow(with: glowConfiguration)
            button.backgroundColor = Colors.newConversationButtonCollapsedBackground
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !bounds.contains(point), isUserDragging { collapse(withAnimation: true) }
        return super.hitTest(point, with: event)
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

    init(isMainButton: Bool, icon: UIImage) {
        self.isMainButton = isMainButton
        self.icon = icon
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppModeChangedNotification(_:)), name: .appModeChanged, object: nil)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(isMainButton:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(isMainButton:) instead.")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setUpViewHierarchy(isUpdate: Bool = false) {
        let newConversationButtonCollapsedBackground = isLightMode ? UIColor(hex: 0xF5F5F5) : UIColor(hex: 0x1F1F1F)
        backgroundColor = isMainButton ? Colors.accent : newConversationButtonCollapsedBackground
        let size = Values.newConversationButtonCollapsedSize
        layer.cornerRadius = size / 2
        let glowColor = isMainButton ? Colors.newConversationButtonShadow : (isLightMode ? UIColor.black.withAlphaComponent(0.4) : UIColor.black)
        let glowConfiguration = UIView.CircularGlowConfiguration(size: size, color: glowColor, isAnimated: false, radius: isLightMode ? 4 : 6)
        setCircularGlow(with: glowConfiguration)
        layer.masksToBounds = false
        let iconColor = (isMainButton && isLightMode) ? UIColor.white : (isLightMode ? UIColor.black : UIColor.white)
        image = icon.asTintedImage(color: iconColor)!
        contentMode = .center
        if !isUpdate {
            widthConstraint = set(.width, to: size)
            heightConstraint = set(.height, to: size)
        }
    }

    @objc private func handleAppModeChangedNotification(_ notification: Notification) {
        setUpViewHierarchy(isUpdate: true)
    }
}

// MARK: Convenience
private extension UIView {
    
    func contains(_ touch: UITouch) -> Bool {
        return bounds.contains(touch.location(in: self))
    }
}

private extension UITouch {
    
    func isLeft(of view: UIView, with margin: CGFloat = 0) -> Bool {
        return isContainedVertically(in: view, with: margin) && location(in: view).x < view.bounds.minX
    }
    
    func isAbove(_ view: UIView, with margin: CGFloat = 0) -> Bool {
        return isContainedHorizontally(in: view, with: margin) && location(in: view).y < view.bounds.minY
    }
    
    func isRight(of view: UIView, with margin: CGFloat = 0) -> Bool {
        return isContainedVertically(in: view, with: margin) && location(in: view).x > view.bounds.maxX
    }
    
    func isBelow(_ view: UIView, with margin: CGFloat = 0) -> Bool {
        return isContainedHorizontally(in: view, with: margin) && location(in: view).y > view.bounds.maxY
    }
    
    private func isContainedHorizontally(in view: UIView, with margin: CGFloat = 0) -> Bool {
        return ((view.bounds.minX - margin)...(view.bounds.maxX + margin)) ~= location(in: view).x
    }
    
    private func isContainedVertically(in view: UIView, with margin: CGFloat = 0) -> Bool {
        return ((view.bounds.minY - margin)...(view.bounds.maxY + margin)) ~= location(in: view).y
    }
}

private extension CGPoint {
    
    func distance(to otherPoint: CGPoint) -> CGFloat {
        return sqrt(pow(self.x - otherPoint.x, 2) + pow(self.y - otherPoint.y, 2))
    }
}
