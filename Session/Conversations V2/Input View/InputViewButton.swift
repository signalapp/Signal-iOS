
final class InputViewButton : UIView {
    private let icon: UIImage
    private let isSendButton: Bool
    private let delegate: InputViewButtonDelegate
    private lazy var widthConstraint = set(.width, to: InputViewButton.size)
    private lazy var heightConstraint = set(.height, to: InputViewButton.size)
    
    // MARK: Settings
    static let size = CGFloat(40)
    static let expandedSize = CGFloat(48)
    
    // MARK: Lifecycle
    init(icon: UIImage, isSendButton: Bool = false, delegate: InputViewButtonDelegate) {
        self.icon = icon
        self.isSendButton = isSendButton
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(icon:delegate:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(icon:delegate:) instead.")
    }
    
    private func setUpViewHierarchy() {
        backgroundColor = isSendButton ? Colors.accent : Colors.text.withAlphaComponent(0.05)
        layer.cornerRadius = InputViewButton.size / 2
        layer.masksToBounds = true
        isUserInteractionEnabled = true
        widthConstraint.isActive = true
        heightConstraint.isActive = true
        let tint = isSendButton ? UIColor.black : Colors.text
        let iconImageView = UIImageView(image: icon.withTint(tint))
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.set(.width, to: 20)
        iconImageView.set(.height, to: 20)
        addSubview(iconImageView)
        iconImageView.center(in: self)
    }
    
    // MARK: Animation
    private func animate(to size: CGFloat, glowColor: UIColor, backgroundColor: UIColor) {
        let frame = CGRect(center: center, size: CGSize(width: size, height: size))
        widthConstraint.constant = size
        heightConstraint.constant = size
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
            self.frame = frame
            self.layer.cornerRadius = size / 2
            let glowConfiguration = UIView.CircularGlowConfiguration(size: size, color: glowColor, isAnimated: true, radius: isLightMode ? 4 : 6)
            self.setCircularGlow(with: glowConfiguration)
            self.backgroundColor = backgroundColor
        }
    }
    
    private func expand() {
        animate(to: InputViewButton.expandedSize, glowColor: Colors.expandedButtonGlowColor, backgroundColor: Colors.accent)
    }
    
    private func collapse() {
        let backgroundColor = isSendButton ? Colors.accent : Colors.text.withAlphaComponent(0.05)
        animate(to: InputViewButton.size, glowColor: .clear, backgroundColor: backgroundColor)
    }
    
    // MARK: Interaction
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        expand()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        collapse()
        delegate.handleInputViewButtonTapped(self)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        collapse()
    }
}

// MARK: Delegate
protocol InputViewButtonDelegate {
    
    func handleInputViewButtonTapped(_ inputViewButton: InputViewButton)
}
