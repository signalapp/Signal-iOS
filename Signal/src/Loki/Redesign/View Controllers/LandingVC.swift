
final class LandingVC : UIViewController {
    private var fakeChatViewContentOffset: CGPoint!
    
    // MARK: Components
    private lazy var fakeChatView: FakeChatView = {
        let result = FakeChatView()
        result.set(.height, to: Values.fakeChatViewHeight)
        return result
    }()
    
    // MARK: Settings
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Set up navigation bar
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
        // Set up logo image view
        let logoImageView = UIImageView()
        logoImageView.image = #imageLiteral(resourceName: "Loki")
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.set(.width, to: 32)
        logoImageView.set(.height, to: 32)
        navigationItem.titleView = logoImageView
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        titleLabel.text = NSLocalizedString("Your Loki Messenger begins here...", comment: "")
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
        // Set up register button
        let registerButton = Button(style: .prominentFilled, size: .large)
        registerButton.setTitle(NSLocalizedString("Create Account", comment: ""), for: UIControl.State.normal)
        registerButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        registerButton.addTarget(self, action: #selector(register), for: UIControl.Event.touchUpInside)
        // Set up restore button
        let restoreButton = Button(style: .prominentOutline, size: .large)
        restoreButton.setTitle(NSLocalizedString("Continue your Loki Messenger", comment: ""), for: UIControl.State.normal)
        restoreButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        restoreButton.addTarget(self, action: #selector(restore), for: UIControl.Event.touchUpInside)
        // Set up button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ registerButton, restoreButton ])
        buttonStackView.axis = .vertical
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.alignment = .fill
        // Set up button stack view container
        let buttonStackViewContainer = UIView()
        buttonStackViewContainer.addSubview(buttonStackView)
        buttonStackView.pin(.leading, to: .leading, of: buttonStackViewContainer, withInset: Values.massiveSpacing)
        buttonStackView.pin(.top, to: .top, of: buttonStackViewContainer)
        buttonStackViewContainer.pin(.trailing, to: .trailing, of: buttonStackView, withInset: Values.massiveSpacing)
        buttonStackViewContainer.pin(.bottom, to: .bottom, of: buttonStackView)
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ topSpacer, titleLabelContainer, UIView.spacer(withHeight: Values.mediumSpacing), fakeChatView, bottomSpacer, buttonStackViewContainer, UIView.spacer(withHeight: Values.onboardingButtonBottomOffset) ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        view.addSubview(mainStackView)
        mainStackView.pin(to: view)
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 1).isActive = true
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidAppear(animated)
        fakeChatView.contentOffset = fakeChatViewContentOffset
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
}
