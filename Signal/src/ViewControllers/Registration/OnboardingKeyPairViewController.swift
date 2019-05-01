
final class OnboardingKeyPairViewController : OnboardingBaseViewController {
    private var mode: Mode = .register { didSet { if mode != oldValue { handleModeChanged() } } }
    private var keyPair: ECKeyPair! { didSet { updateMnemonic() } }
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
        return result
    }()
    
    private lazy var restoreButton: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Restore Using Mnemonic", comment: ""), selector: #selector(switchMode))
        result.accessibilityIdentifier = "onboarding.keyPairStep.restoreButton"
        return result
    }()
    
    private lazy var restoreStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ mnemonicTextField, UIView.spacer(withHeight: 24), registerButton ])
        result.accessibilityIdentifier = "onboarding.keyPairStep.restoreStackView"
        result.axis = .vertical
        return result
    }()
    
    private lazy var mnemonicTextField: UITextField = {
        let result = UITextField(frame: CGRect.zero)
        result.accessibilityIdentifier = "onboarding.keyPairStep.mnemonicTextField"
        result.textAlignment = .center
        result.placeholder = NSLocalizedString("Enter Your Mnemonic", comment: "")
        return result
    }()
    
    private lazy var registerButton: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Register a New Account", comment: ""), selector: #selector(switchMode))
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerButton"
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
    
    override public func viewDidLoad() {
        super.loadView()
        setUpViewHierarchy()
        handleModeChanged() // Perform initial update
        updateKeyPair()
        // Test
        // ================
        let _ = ServiceNode.retrieveAllMessages().done { result in
            print(result.task.originalRequest!)
            print(result.task.response!)
        }
        let _ = ServiceNode.sendTestMessage().done { result in
            print(result.task.originalRequest!)
            print(result.task.response!)
        }
        // ================
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
        copyButton.setTitle(NSLocalizedString("Copy", comment: ""))
    }
    
    // MARK: Updating
    private func handleModeChanged() {
        let registerOrRestoreButtonTitle: String = {
            switch mode {
            case .register: return NSLocalizedString("Register", comment: "")
            case .restore: return NSLocalizedString("Restore", comment: "")
            }
        }()
        UIView.animate(withDuration: 0.25) {
            self.registerStackView.alpha = (self.mode == .register ? 1 : 0)
            self.restoreStackView.alpha = (self.mode == .restore ? 1 : 0)
        }
        self.registerOrRestoreButton.setTitle(registerOrRestoreButtonTitle)
    }
    
    private func updateKeyPair() {
        let identityManager = OWSIdentityManager.shared()
        identityManager.generateNewIdentityKey() // Generate and store a new identity key pair
        keyPair = identityManager.identityKeyPair()!
    }
    
    private func updateMnemonic() {
        mnemonic = Mnemonic.encode(hexEncodedString: keyPair.hexEncodedPrivateKey)
    }
    
    private func handleMnemonicChanged() {
        mnemonicLabel.text = mnemonic
    }

    // MARK: Interaction
    @objc private func copyMnemonic() {
        UIPasteboard.general.string = mnemonic
        copyButton.isUserInteractionEnabled = false
        copyButton.setTitle(NSLocalizedString("Copied ✓", comment: ""))
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func switchMode() {
        switch mode {
        case .register: mode = .restore
        case .restore: mode = .register
        }
    }

    @objc private func registerOrRestore() {
        let hexEncodedPublicKey: String
        switch mode {
        case .register: hexEncodedPublicKey = keyPair.hexEncodedPublicKey
        case .restore:
            let mnemonic = mnemonicTextField.text!
            do {
                let hexEncodedPrivateKey = try Mnemonic.decode(mnemonic: mnemonic)
                let keyPair = ECKeyPair.generate(withHexEncodedPrivateKey: hexEncodedPrivateKey)
                // TODO: Store key pair
                hexEncodedPublicKey = keyPair.hexEncodedPublicKey
            } catch let error {
                fatalError(error.localizedDescription) // TODO: Handle
            }
        }
        let accountManager = TSAccountManager.sharedInstance()
        accountManager.phoneNumberAwaitingVerification = hexEncodedPublicKey
        accountManager.didRegister()
        let onSuccess = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.onboardingController.verificationDidComplete(fromView: strongSelf)
        }
        if let userName = userName {
            OWSProfileManager.shared().updateLocalProfileName(userName, avatarImage: nil, success: onSuccess, failure: onSuccess) // Try to save the user name but ignore the result
        } else {
            onSuccess()
        }
    }
}
