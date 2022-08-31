import UIKit
import SessionUIKit

final class NewConversationButtonSet : UIView {
    private var isUserDragging = false
    private var horizontalButtonConstraints: [NewConversationButton:NSLayoutConstraint] = [:]
    private var verticalButtonConstraints: [NewConversationButton:NSLayoutConstraint] = [:]
    private var expandedButton: NewConversationButton?
    var delegate: NewConversationButtonSetDelegate?
    
    // MARK: - Settings
    
    private let spacing = Values.veryLargeSpacing
    private let iconSize: CGFloat = 24
    private let maxDragDistance: CGFloat = 56
    private let dragMargin: CGFloat = 16
    static let collapsedButtonSize: CGFloat = 60
    static let expandedButtonSize: CGFloat = 72
    
    // MARK: - Components
    
    private lazy var mainButton = NewConversationButton(isMainButton: true, icon: #imageLiteral(resourceName: "Plus").scaled(to: CGSize(width: iconSize, height: iconSize)))
    private lazy var newDMButton = NewConversationButton(isMainButton: false, icon: #imageLiteral(resourceName: "Message").scaled(to: CGSize(width: iconSize, height: iconSize)))
    private lazy var createClosedGroupButton = NewConversationButton(isMainButton: false, icon: #imageLiteral(resourceName: "Group").scaled(to: CGSize(width: iconSize, height: iconSize)))
    private lazy var joinOpenGroupButton = NewConversationButton(isMainButton: false, icon: #imageLiteral(resourceName: "Globe").scaled(to: CGSize(width: iconSize, height: iconSize)))
    
    private lazy var newDMLabel: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeBackgroundColor = .backgroundPrimary
        result.layer.cornerRadius = 4
        
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        label.text = "NEW_CONVERSATION_MENU_DIRECT_MESSAGE".localized().uppercased()
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        result.addSubview(label)
        
        label.pin(to: result, withInset: 4)
        
        return result
    }()
    
    private lazy var createClosedGroupLabel: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeBackgroundColor = .backgroundPrimary
        result.layer.cornerRadius = 4
        
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        label.text = "NEW_CONVERSATION_MENU_CLOSED_GROUP".localized().uppercased()
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        result.addSubview(label)
        
        label.pin(to: result, withInset: 4)
        
        return result
    }()
    
    private lazy var joinOpenGroupLabel: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeBackgroundColor = .backgroundPrimary
        result.layer.cornerRadius = 4
        
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        label.text = "NEW_CONVERSATION_MENU_OPEN_GROUP".localized().uppercased()
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        result.addSubview(label)
        
        label.pin(to: result, withInset: 4)
        
        return result
    }()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        mainButton.accessibilityLabel = "Toggle conversation options button"
        mainButton.isAccessibilityElement = true
        newDMButton.accessibilityLabel = "Start new one-on-one conversation button"
        newDMButton.isAccessibilityElement = true
        createClosedGroupButton.accessibilityLabel = "Start new closed group button"
        createClosedGroupButton.isAccessibilityElement = true
        joinOpenGroupButton.accessibilityLabel = "Join open group button"
        joinOpenGroupButton.isAccessibilityElement = true
        
        let inset = (NewConversationButtonSet.expandedButtonSize - NewConversationButtonSet.collapsedButtonSize) / 2
        addSubview(joinOpenGroupLabel)
        addSubview(joinOpenGroupButton)
        
        horizontalButtonConstraints[joinOpenGroupButton] = joinOpenGroupButton.pin(.left, to: .left, of: self, withInset: inset)
        verticalButtonConstraints[joinOpenGroupButton] = joinOpenGroupButton.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        joinOpenGroupLabel.center(.horizontal, in: joinOpenGroupButton)
        joinOpenGroupLabel.pin(.top, to: .bottom, of: joinOpenGroupButton, withInset: 8)
        addSubview(newDMLabel)
        addSubview(newDMButton)
        
        newDMButton.center(.horizontal, in: self)
        verticalButtonConstraints[newDMButton] = newDMButton.pin(.top, to: .top, of: self, withInset: inset)
        newDMLabel.center(.horizontal, in: newDMButton)
        newDMLabel.pin(.top, to: .bottom, of: newDMButton, withInset: 8)
        addSubview(createClosedGroupLabel)
        addSubview(createClosedGroupButton)
        
        horizontalButtonConstraints[createClosedGroupButton] = createClosedGroupButton.pin(.right, to: .right, of: self, withInset: -inset)
        verticalButtonConstraints[createClosedGroupButton] = createClosedGroupButton.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        createClosedGroupLabel.center(.horizontal, in: createClosedGroupButton)
        createClosedGroupLabel.pin(.top, to: .bottom, of: createClosedGroupButton, withInset: 8)
        addSubview(mainButton)
        
        mainButton.center(.horizontal, in: self)
        mainButton.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        
        let width = 2 * NewConversationButtonSet.expandedButtonSize + 2 * spacing + NewConversationButtonSet.collapsedButtonSize
        set(.width, to: width)
        
        let height = NewConversationButtonSet.expandedButtonSize + spacing + NewConversationButtonSet.collapsedButtonSize
        set(.height, to: height)
        collapse(withAnimation: false)
        isUserInteractionEnabled = true
        
        let joinOpenGroupButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleJoinOpenGroupButtonTapped))
        joinOpenGroupButton.addGestureRecognizer(joinOpenGroupButtonTapGestureRecognizer)
        
        let createNewPrivateChatButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCreateNewPrivateChatButtonTapped))
        newDMButton.addGestureRecognizer(createNewPrivateChatButtonTapGestureRecognizer)
        
        let createNewClosedGroupButtonTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCreateNewClosedGroupButtonTapped))
        createClosedGroupButton.addGestureRecognizer(createNewClosedGroupButtonTapGestureRecognizer)
    }
    
    // MARK: - Interaction
    
    @objc private func handleJoinOpenGroupButtonTapped() { delegate?.joinOpenGroup() }
    @objc private func handleCreateNewPrivateChatButtonTapped() { delegate?.createNewDM() }
    @objc private func handleCreateNewClosedGroupButtonTapped() { delegate?.createClosedGroup() }
    
    private func expand(isUserDragging: Bool) {
        let views = [ joinOpenGroupButton, joinOpenGroupLabel, newDMButton, newDMLabel, createClosedGroupButton, createClosedGroupLabel ]
        
        UIView.animate(withDuration: 0.25, animations: {
            views.forEach { $0.alpha = 1 }
            let inset = (NewConversationButtonSet.expandedButtonSize - NewConversationButtonSet.collapsedButtonSize) / 2
            let size = NewConversationButtonSet.collapsedButtonSize
            self.joinOpenGroupButton.frame = CGRect(origin: CGPoint(x: inset, y: self.height() - size - inset), size: CGSize(width: size, height: size))
            self.joinOpenGroupLabel.center = CGPoint(x: self.joinOpenGroupButton.center.x, y: self.joinOpenGroupButton.frame.maxY + 8 + (self.joinOpenGroupLabel.bounds.height / 2))
            self.newDMButton.frame = CGRect(center: CGPoint(x: self.bounds.center.x, y: inset + size / 2), size: CGSize(width: size, height: size))
            self.newDMLabel.center = CGPoint(x: self.newDMButton.center.x, y: self.newDMButton.frame.maxY + 8 + (self.newDMLabel.bounds.height / 2))
            self.createClosedGroupButton.frame = CGRect(origin: CGPoint(x: self.width() - size - inset, y: self.height() - size - inset), size: CGSize(width: size, height: size))
            self.createClosedGroupLabel.center = CGPoint(x: self.createClosedGroupButton.center.x, y: self.createClosedGroupButton.frame.maxY + 8 + (self.createClosedGroupLabel.bounds.height / 2))
        }, completion: { _ in
            self.isUserDragging = isUserDragging
        })
    }
    
    private func collapse(withAnimation isAnimated: Bool) {
        isUserDragging = false
        let buttons = [ joinOpenGroupButton, newDMButton, createClosedGroupButton ]
        let labels = [ joinOpenGroupLabel, newDMLabel, createClosedGroupLabel ]
        
        UIView.animate(withDuration: isAnimated ? 0.25 : 0) {
            labels.forEach { label in
                label.alpha = 0
                label.center = self.mainButton.center
            }
            buttons.forEach { button in
                button.alpha = 0
                let size = NewConversationButtonSet.collapsedButtonSize
                button.frame = CGRect(center: self.mainButton.center, size: CGSize(width: size, height: size))
            }
        }
    }
    
    private func reset() {
        let mainButtonLocationInSelfCoordinates = CGPoint(x: width() / 2, y: height() - NewConversationButtonSet.expandedButtonSize / 2)
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
        let mainButtonLocationInSelfCoordinates = CGPoint(x: width() / 2, y: height() - NewConversationButtonSet.expandedButtonSize / 2)
        let touchLocationInSelfCoordinates = touch.location(in: self)
        mainButton.frame = CGRect(center: touchLocationInSelfCoordinates, size: mainButtonSize)
        mainButton.alpha = 1 - (touchLocationInSelfCoordinates.distance(to: mainButtonLocationInSelfCoordinates) / maxDragDistance)
        let buttons = [ joinOpenGroupButton, newDMButton, createClosedGroupButton ]
        let buttonToExpand = buttons.first { button in
            var hasUserDraggedBeyondButton = false
            if button == joinOpenGroupButton && touch.isLeft(of: joinOpenGroupButton, with: dragMargin) { hasUserDraggedBeyondButton = true }
            if button == newDMButton && touch.isAbove(newDMButton, with: dragMargin) { hasUserDraggedBeyondButton = true }
            if button == createClosedGroupButton && touch.isRight(of: createClosedGroupButton, with: dragMargin) { hasUserDraggedBeyondButton = true }
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
        else if newDMButton.contains(touch) || touch.isAbove(newDMButton, with: dragMargin) { delegate?.createNewDM() }
        else if createClosedGroupButton.contains(touch) || touch.isRight(of: createClosedGroupButton, with: dragMargin) { delegate?.createClosedGroup() }
        reset()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserDragging else { return }
        reset()
    }
    
    private func expand(_ button: NewConversationButton) {
        if let horizontalConstraint = horizontalButtonConstraints[button] { horizontalConstraint.constant = 0 }
        if let verticalConstraint = verticalButtonConstraints[button] { verticalConstraint.constant = 0 }
        let size = NewConversationButtonSet.expandedButtonSize
        let frame = CGRect(center: button.center, size: CGSize(width: size, height: size))
        button.widthConstraint.constant = size
        button.heightConstraint.constant = size
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
            button.frame = frame
            button.layer.cornerRadius = size / 2
            let glowColor = Colors.expandedButtonGlowColor
            let glowConfiguration = UIView.CircularGlowConfiguration(size: size, color: glowColor, isAnimated: true, radius: isLightMode ? 4 : 6)
            button.setCircularGlow(with: glowConfiguration)
            button.backgroundColor = Colors.accent
        }
    }
    
    private func collapse(_ button: NewConversationButton) {
        let inset = (NewConversationButtonSet.expandedButtonSize - NewConversationButtonSet.collapsedButtonSize) / 2
        if joinOpenGroupButton == expandedButton {
            horizontalButtonConstraints[joinOpenGroupButton]!.constant = inset
            verticalButtonConstraints[joinOpenGroupButton]!.constant = -inset
        } else if newDMButton == expandedButton {
            verticalButtonConstraints[newDMButton]!.constant = inset
        } else if createClosedGroupButton == expandedButton {
            horizontalButtonConstraints[createClosedGroupButton]!.constant = -inset
            verticalButtonConstraints[createClosedGroupButton]!.constant = -inset
        }
        let size = NewConversationButtonSet.collapsedButtonSize
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
        let allButtons = [ mainButton, joinOpenGroupButton, newDMButton, createClosedGroupButton ]
        if allButtons.contains(where: { $0.frame.contains(point) }) {
            return super.hitTest(point, with: event)
        } else {
            collapse(withAnimation: true)
            return nil
        }
    }
}

// MARK: - Delegate

protocol NewConversationButtonSetDelegate {
    func joinOpenGroup()
    func createNewDM()
    func createClosedGroup()
}

// MARK: - Button

private final class NewConversationButton: UIImageView {
    private let isMainButton: Bool
    private let icon: UIImage
    var widthConstraint: NSLayoutConstraint!
    var heightConstraint: NSLayoutConstraint!
    
    // MARK: - UI
    
    private let innerShadowLayer: CALayer = {
        let result: CALayer = CALayer()
        result.masksToBounds = true
        result.themeShadowColor = .menuButton_innerShadow
        result.position = CGPoint(
            x: (NewConversationButtonSet.collapsedButtonSize / 2),
            y: (NewConversationButtonSet.collapsedButtonSize / 2)
        )
        result.bounds = CGRect(
            x: 0,
            y: 0,
            width: NewConversationButtonSet.collapsedButtonSize,
            height: NewConversationButtonSet.collapsedButtonSize
        )
        result.cornerRadius = (NewConversationButtonSet.collapsedButtonSize / 2)
        result.shadowOffset = .zero
        result.shadowOpacity = 0.4
        result.shadowRadius = 2
        
        let cutout: UIBezierPath = UIBezierPath(
            roundedRect: result.bounds
                .insetBy(dx: result.shadowRadius, dy: result.shadowRadius),
            cornerRadius: (NewConversationButtonSet.collapsedButtonSize / 2)
        ).reversing()
        let path: UIBezierPath = UIBezierPath(
            roundedRect: result.bounds,
            cornerRadius: (NewConversationButtonSet.collapsedButtonSize / 2)
        )
        path.append(cutout)
        result.shadowPath = path.cgPath
        
        return result
    }()
    
    // MARK: - Initialization

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
    
    private func setUpViewHierarchy(isUpdate: Bool = false) {
        clipsToBounds = false
        image = icon.withRenderingMode(.alwaysTemplate)
        contentMode = .center
        layer.cornerRadius = (NewConversationButtonSet.collapsedButtonSize / 2)
        
        themeBackgroundColor = .menuButton_background
        themeTintColor = .menuButton_icon
        
        if isMainButton {
            themeShadowColor = .menuButton_outerShadow
            layer.shadowRadius = 15
            layer.shadowOpacity = 0.3
            layer.shadowOffset = .zero
            layer.cornerRadius = (NewConversationButtonSet.collapsedButtonSize / 2)
            layer.shadowPath = UIBezierPath(
                ovalIn: CGRect(
                    origin: CGPoint.zero,
                    size: CGSize(
                        width: NewConversationButtonSet.collapsedButtonSize,
                        height: NewConversationButtonSet.collapsedButtonSize
                    )
                )
            ).cgPath
            
            self.layer.addSublayer(innerShadowLayer)
            
        }
        
        if !isUpdate {
            widthConstraint = set(.width, to: NewConversationButtonSet.collapsedButtonSize)
            heightConstraint = set(.height, to: NewConversationButtonSet.collapsedButtonSize)
        }
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
