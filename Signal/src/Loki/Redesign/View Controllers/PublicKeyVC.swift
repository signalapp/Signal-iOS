
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
        let legalLabel = UILabel()
        legalLabel.set(.height, to: Values.onboardingButtonBottomOffset)
        legalLabel.textColor = Colors.text
        legalLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        let legalLabelText = "By using this service, you agree to our Terms and Conditions and Privacy Statement"
        let attributedLegalLabelText = NSMutableAttributedString(string: legalLabelText)
        attributedLegalLabelText.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.verySmallFontSize), range: (legalLabelText as NSString).range(of: "Terms and Conditions"))
        attributedLegalLabelText.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.verySmallFontSize), range: (legalLabelText as NSString).range(of: "Privacy Statement"))
        legalLabel.attributedText = attributedLegalLabelText
        legalLabel.numberOfLines = 0
        legalLabel.textAlignment = .center
        legalLabel.lineBreakMode = .byWordWrapping
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
        let mainStackView = UIStackView(arrangedSubviews: [ topSpacer, topStackViewContainer, bottomSpacer, buttonStackViewContainer, legalLabel ])
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
}
