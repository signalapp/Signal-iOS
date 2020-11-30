
final class LandingVC : BaseVC {
    private var fakeChatViewContentOffset: CGPoint!
    
    // MARK: Components
    private lazy var fakeChatView: FakeChatView = {
        let result = FakeChatView()
        result.set(.height, to: Values.fakeChatViewHeight)
        return result
    }()
    
    private lazy var registerButton: Button = {
        let result = Button(style: .prominentFilled, size: .large)
        result.setTitle(NSLocalizedString("vc_landing_register_button_title", comment: ""), for: UIControl.State.normal)
        result.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.addTarget(self, action: #selector(register), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var restoreButton: Button = {
        let result = Button(style: .prominentOutline, size: .large)
        result.setTitle(NSLocalizedString("vc_landing_restore_button_title", comment: ""), for: UIControl.State.normal)
        result.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.addTarget(self, action: #selector(restore), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setUpNavBarSessionIcon()
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = NSLocalizedString("vc_landing_title_2", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up title label container
        let titleLabelContainer = UIView()
        titleLabelContainer.addSubview(titleLabel)
        titleLabel.pin(.leading, to: .leading, of: titleLabelContainer, withInset: Values.veryLargeSpacing)
        titleLabel.pin(.top, to: .top, of: titleLabelContainer)
        titleLabelContainer.pin(.trailing, to: .trailing, of: titleLabel, withInset: Values.veryLargeSpacing)
        titleLabelContainer.pin(.bottom, to: .bottom, of: titleLabel)
        // Set up spacers
        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        // Set up link button container
        let linkButtonContainer = UIView()
        linkButtonContainer.set(.height, to: Values.onboardingButtonBottomOffset)
        // Set up button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ registerButton, restoreButton ])
        buttonStackView.axis = .vertical
        buttonStackView.spacing = isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        buttonStackView.alignment = .fill
        // Set up button stack view container
        let buttonStackViewContainer = UIView()
        buttonStackViewContainer.addSubview(buttonStackView)
        buttonStackView.pin(.leading, to: .leading, of: buttonStackViewContainer, withInset: isIPhone5OrSmaller ? CGFloat(52) : Values.massiveSpacing)
        buttonStackView.pin(.top, to: .top, of: buttonStackViewContainer)
        buttonStackViewContainer.pin(.trailing, to: .trailing, of: buttonStackView, withInset: isIPhone5OrSmaller ? CGFloat(52) : Values.massiveSpacing)
        buttonStackViewContainer.pin(.bottom, to: .bottom, of: buttonStackView)
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ topSpacer, titleLabelContainer, UIView.spacer(withHeight: isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing), fakeChatView, bottomSpacer, buttonStackViewContainer, linkButtonContainer ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        view.addSubview(mainStackView)
        mainStackView.pin(to: view)
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 1).isActive = true
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let fakeChatViewContentOffset = fakeChatViewContentOffset {
            fakeChatView.contentOffset = fakeChatViewContentOffset
        }
    }
    
    // MARK: Interaction
    @objc private func register() {
        fakeChatViewContentOffset = fakeChatView.contentOffset
        DispatchQueue.main.async {
            self.fakeChatView.contentOffset = self.fakeChatViewContentOffset
        }
        let registerVC = RegisterVC()
        navigationController!.pushViewController(registerVC, animated: true)
    }
    
    @objc private func restore() {
        fakeChatViewContentOffset = fakeChatView.contentOffset
        DispatchQueue.main.async {
            self.fakeChatView.contentOffset = self.fakeChatViewContentOffset
        }
        let restoreVC = RestoreVC()
        navigationController!.pushViewController(restoreVC, animated: true)
    }
    
    // MARK: Convenience
    private func setUserInteractionEnabled(_ isEnabled: Bool) {
        [ registerButton, restoreButton ].forEach {
            $0.isUserInteractionEnabled = isEnabled
        }
    }
}
