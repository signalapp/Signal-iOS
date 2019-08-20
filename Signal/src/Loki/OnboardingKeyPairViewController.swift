
final class OnboardingKeyPairViewController : OnboardingBaseViewController {
    private var mode: Mode = .register { didSet { if mode != oldValue { handleModeChanged() } } }
    private var seed: Data! { didSet { updateMnemonic() } }
    private var mnemonic: String! { didSet { handleMnemonicChanged() } }
    private var userName: String?
    
    // MARK: Components
    private lazy var registerStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ explanationLabel, UIView.spacer(withHeight: 32), mnemonicLabel, UIView.spacer(withHeight: 24), copyButton, UIView.spacer(withHeight: 8), restoreButton ])
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerStackView"
        result.axis = .vertical
        return result
    }()
    
    private lazy var explanationLabel: UILabel = {
        let result = createExplanationLabel(text: NSLocalizedString("Please save the seed below in a safe location. It can be used to restore your account if you lose access, or to migrate to a new device.", comment: ""))
        result.accessibilityIdentifier = "onboarding.keyPairStep.explanationLabel"
        result.textColor = Theme.primaryColor
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitBold)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: result.font.pointSize)
        return result
    }()
    
    private lazy var mnemonicLabel: UILabel = {
        let result = createExplanationLabel(text: "")
        result.accessibilityIdentifier = "onboarding.keyPairStep.mnemonicLabel"
        result.alpha = 0.8
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitItalic)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: result.font.pointSize)
        return result
    }()

    private lazy var copyButton: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Copy", comment: ""), selector: #selector(copyMnemonic))
        result.accessibilityIdentifier = "onboarding.keyPairStep.copyButton"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var restoreButton: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Restore Using Mnemonic", comment: ""), selector: #selector(switchMode))
        result.accessibilityIdentifier = "onboarding.keyPairStep.restoreButton"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var restoreStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ errorLabel, UIView.spacer(withHeight: 32), mnemonicTextField, UIView.spacer(withHeight: 24), registerButton ])
        result.accessibilityIdentifier = "onboarding.keyPairStep.restoreStackView"
        result.axis = .vertical
        return result
    }()
    
    private lazy var errorLabel: UILabel = {
        let result = createExplanationLabel(text: "")
        result.accessibilityIdentifier = "onboarding.keyPairStep.errorLabel"
        result.textColor = UIColor.red
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitBold)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: result.font.pointSize)
        return result
    }()
    
    private lazy var mnemonicTextField: UITextField = {
        let result = UITextField(frame: CGRect.zero)
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeBodyClamped
        result.textAlignment = .center
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Enter Your Mnemonic", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Theme.placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = UIColor.lokiGreen()
        result.accessibilityIdentifier = "onboarding.keyPairStep.mnemonicTextField"
        result.keyboardAppearance = .dark
        return result
    }()
    
    private lazy var registerButton: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Register a New Account", comment: ""), selector: #selector(switchMode))
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerButton"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var registerOrRestoreButton: OWSFlatButton = {
        let result = createButton(title: "", selector: #selector(registerOrRestore))
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerOrRestoreButton"
        return result
    }()
    
    // MARK: Types
    enum Mode { case register, restore }
    
    // MARK: Lifecycle
    init(onboardingController: OnboardingController, userName: String?) {
        super.init(onboardingController: onboardingController)
        self.userName = userName
    }
    
    override func viewDidLoad() {
        super.loadView()
        setUpViewHierarchy()
        handleModeChanged() // Perform initial update
        updateSeed()
    }
    
    private func setUpViewHierarchy() {
        // Prepare
        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero
        // Set up view hierarchy
        let titleLabel = createTitleLabel(text: NSLocalizedString("Create Your Loki Messenger Account", comment: ""))
        titleLabel.accessibilityIdentifier = "onboarding.keyPairStep.titleLabel"
        titleLabel.setContentHuggingPriority(.required, for: NSLayoutConstraint.Axis.vertical)
        let mainView = UIView(frame: CGRect.zero)
        mainView.addSubview(restoreStackView)
        mainView.addSubview(registerStackView)
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabel, mainView, registerOrRestoreButton ])
        mainStackView.axis = .vertical
        mainStackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        mainStackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(mainStackView)
        // Set up constraints
        mainStackView.autoPinWidthToSuperview()
        mainStackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: mainStackView, avoidNotch: true)
        registerStackView.autoPinWidthToSuperview()
        registerStackView.autoVCenterInSuperview()
        restoreStackView.autoPinWidthToSuperview()
        restoreStackView.autoVCenterInSuperview()
    }
    
    // MARK: General
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("Copy", comment: ""))
        }, completion: nil)
    }
    
    // MARK: Updating
    private func handleModeChanged() {
        UIView.animate(withDuration: 0.25) {
            self.registerStackView.alpha = (self.mode == .register ? 1 : 0)
            self.restoreStackView.alpha = (self.mode == .restore ? 1 : 0)
        }
        let registerOrRestoreButtonTitle: String = {
            switch mode {
            case .register: return NSLocalizedString("Register", comment: "")
            case .restore: return NSLocalizedString("Restore", comment: "")
            }
        }()
        UIView.transition(with: registerOrRestoreButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.registerOrRestoreButton.setTitle(registerOrRestoreButtonTitle)
        }, completion: nil)
        if mode == .register { mnemonicTextField.resignFirstResponder() }
    }
    
    private func updateSeed() {
        seed = Randomness.generateRandomBytes(16)
    }
    
    private func updateMnemonic() {
        let hexEncodedSeed = seed!.toHexString()
        mnemonic = Mnemonic.encode(hexEncodedString: hexEncodedSeed)
    }
    
    private func handleMnemonicChanged() {
        mnemonicLabel.text = mnemonic
    }

    // MARK: Interaction
    @objc private func copyMnemonic() {
        UIPasteboard.general.string = mnemonic
        copyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("Copied ✓", comment: ""))
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func switchMode() {
        switch mode {
        case .register: mode = .restore
        case .restore: mode = .register
        }
    }

    @objc private func registerOrRestore() {
        var seed: Data
        switch mode {
        case .register: seed = self.seed
        case .restore:
            let mnemonic = mnemonicTextField.text!
            do {
                let hexEncodedSeed = try Mnemonic.decode(mnemonic: mnemonic)
                seed = Data(hex: hexEncodedSeed)
            } catch let error {
                let error = error as? Mnemonic.DecodingError ?? Mnemonic.DecodingError.generic
                return errorLabel.text = error.errorDescription
            }
        }
        // Use KVC to access dbConnection even though it's private
        let databaseConnection = OWSIdentityManager.shared().value(forKey: "dbConnection") as! YapDatabaseConnection
        databaseConnection.setObject(seed.toHexString(), forKey: "LKLokiSeed", inCollection: OWSPrimaryStorageIdentityKeyStoreCollection)
        if seed.count == 16 { seed = seed + seed }
        let identityManager = OWSIdentityManager.shared()
        identityManager.generateNewIdentityKeyPair(fromSeed: seed) // This also stores it
        let keyPair = identityManager.identityKeyPair()!
        let hexEncodedPublicKey = keyPair.hexEncodedPublicKey
        let accountManager = TSAccountManager.sharedInstance()
        accountManager.phoneNumberAwaitingVerification = hexEncodedPublicKey
        accountManager.didRegister()
        let onSuccess = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.onboardingController.verificationDidComplete(fromView: strongSelf)
            UserDefaults.standard.set(true, forKey: "didUpdateForMainnet")
        }
        if let userName = userName {
            OWSProfileManager.shared().updateLocalProfileName(userName, avatarImage: nil, success: onSuccess, failure: onSuccess) // Try to save the user name but ignore the result
        } else {
            onSuccess()
        }
    }
}
