
final class PublicKeyVC : UIViewController {
    private var seed: Data! { didSet { updateKeyPair() } }
    private var keyPair: ECKeyPair! { didSet { updatePublicKeyLabel() } }
    
    // MARK: Components
    private lazy var publicKeyLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = Fonts.spaceMono(ofSize: Values.largeFontSize)
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byCharWrapping
        return result
    }()
    
    private lazy var copyPublicKeyButton: Button = {
        let result = Button(style: .prominentOutline, size: .large)
        result.setTitle(NSLocalizedString("Copy Public Key", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var legalLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.verySmallFontSize)
        let text = "By using this service, you agree to our Terms and Conditions and Privacy Statement"
        let attributedText = NSMutableAttributedString(string: text)
        attributedText.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.verySmallFontSize), range: (text as NSString).range(of: "Terms and Conditions"))
        attributedText.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.verySmallFontSize), range: (text as NSString).range(of: "Privacy Statement"))
        result.attributedText = attributedText
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
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
        titleLabel.text = NSLocalizedString("Say hello to your unique public key", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = "explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation"
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up public key label container
        let publicKeyLabelContainer = UIView()
        publicKeyLabelContainer.addSubview(publicKeyLabel)
        publicKeyLabel.pin(to: publicKeyLabelContainer, withInset: Values.mediumSpacing)
        publicKeyLabelContainer.layer.cornerRadius = Values.textFieldCornerRadius
        publicKeyLabelContainer.layer.borderWidth = Values.borderThickness
        publicKeyLabelContainer.layer.borderColor = Colors.text.cgColor
        // Set up spacers
        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        // Set up register button
        let registerButton = Button(style: .prominentFilled, size: .large)
        registerButton.setTitle(NSLocalizedString("Continue", comment: ""), for: UIControl.State.normal)
        registerButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        registerButton.addTarget(self, action: #selector(register), for: UIControl.Event.touchUpInside)
        // Set up button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ registerButton, copyPublicKeyButton ])
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
        // Set up legal label
        legalLabel.isUserInteractionEnabled = true
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleLegalLabelTapped))
        legalLabel.addGestureRecognizer(tapGestureRecognizer)
        // Set up legal label container
        let legalLabelContainer = UIView()
        legalLabelContainer.set(.height, to: Values.onboardingButtonBottomOffset)
        legalLabelContainer.addSubview(legalLabel)
        legalLabel.pin(.leading, to: .leading, of: legalLabelContainer, withInset: Values.massiveSpacing)
        legalLabel.pin(.top, to: .top, of: legalLabelContainer)
        legalLabelContainer.pin(.trailing, to: .trailing, of: legalLabel, withInset: Values.massiveSpacing)
        legalLabelContainer.pin(.bottom, to: .bottom, of: legalLabel, withInset: 10)
        // Set up top stack view
        let topStackView = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, publicKeyLabelContainer ])
        topStackView.axis = .vertical
        topStackView.spacing = Values.veryLargeSpacing
        topStackView.alignment = .fill
        // Set up top stack view container
        let topStackViewContainer = UIView()
        topStackViewContainer.addSubview(topStackView)
        topStackView.pin(.leading, to: .leading, of: topStackViewContainer, withInset: Values.veryLargeSpacing)
        topStackView.pin(.top, to: .top, of: topStackViewContainer)
        topStackViewContainer.pin(.trailing, to: .trailing, of: topStackView, withInset: Values.veryLargeSpacing)
        topStackViewContainer.pin(.bottom, to: .bottom, of: topStackView)
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ topSpacer, topStackViewContainer, bottomSpacer, buttonStackViewContainer, legalLabelContainer ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        view.addSubview(mainStackView)
        mainStackView.pin(to: view)
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 1).isActive = true
        // Peform initial seed update
        updateSeed()
    }
    
    // MARK: General
    @objc private func enableCopyButton() {
        copyPublicKeyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyPublicKeyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyPublicKeyButton.setTitle(NSLocalizedString("Copy Public Key", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
    }
    
    // MARK: Updating
    private func updateSeed() {
        seed = Randomness.generateRandomBytes(16)
    }
    
    private func updateKeyPair() {
        keyPair = Curve25519.generateKeyPair(fromSeed: seed + seed)
    }
    
    private func updatePublicKeyLabel() {
        publicKeyLabel.text = keyPair.hexEncodedPublicKey
    }
    
    // MARK: Interaction
    @objc private func register() {
        let identityManager = OWSIdentityManager.shared()
        let databaseConnection = identityManager.value(forKey: "dbConnection") as! YapDatabaseConnection
        databaseConnection.setObject(seed.toHexString(), forKey: "LKLokiSeed", inCollection: OWSPrimaryStorageIdentityKeyStoreCollection)
        databaseConnection.setObject(keyPair!, forKey: OWSPrimaryStorageIdentityKeyStoreIdentityKey, inCollection: OWSPrimaryStorageIdentityKeyStoreCollection)
        let hexEncodedPublicKey = keyPair!.hexEncodedPublicKey
        TSAccountManager.sharedInstance().phoneNumberAwaitingVerification = hexEncodedPublicKey
        TSAccountManager.sharedInstance().didRegister()
        UserDefaults.standard.set(true, forKey: "didUpdateForMainnet")
        OWSProfileManager.shared().updateLocalProfileName("User", avatarImage: nil, success: { }, failure: { }) // Try to save the user name but ignore the result
        let homeVC = HomeVC()
        navigationController!.setViewControllers([ homeVC ], animated: true)
    }
    
    @objc private func copyPublicKey() {
        UIPasteboard.general.string = keyPair.hexEncodedPublicKey
        copyPublicKeyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyPublicKeyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyPublicKeyButton.setTitle(NSLocalizedString("Copied", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func handleLegalLabelTapped(_ tapGestureRecognizer: UITapGestureRecognizer) {
        let url = URL(string: "https://github.com/loki-project/loki-messenger-ios/blob/master/privacy-policy.md")!
        UIApplication.shared.open(url)
    }
}
