
// TODO: Split this into multiple VCs

final class SeedVC : OnboardingBaseViewController, DeviceLinkingModalDelegate {
    private var mode: Mode = .register { didSet { if mode != oldValue { handleModeChanged() } } }
    private var seed: Data! { didSet { updateMnemonic() } }
    private var mnemonic: String! { didSet { handleMnemonicChanged() } }
    
    // MARK: Components
    private lazy var registerStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ explanationLabel1, UIView.spacer(withHeight: 32), mnemonicLabel, UIView.spacer(withHeight: 24), copyButton, UIView.spacer(withHeight: 8), restoreButton1, linkButton1 ])
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerStackView"
        result.axis = .vertical
        return result
    }()
    
    private lazy var explanationLabel1: UILabel = {
        let result = createExplanationLabel(text: NSLocalizedString("Please save the seed below in a safe location. It can be used to restore your account if you lose access, or to migrate to a new device.", comment: ""))
        result.accessibilityIdentifier = "onboarding.keyPairStep.explanationLabel1"
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
    
    private lazy var restoreButton1: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Restore Using Seed", comment: ""), selector: #selector(handleSwitchModeButton1Tapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.restoreButton1"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var linkButton1: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Link Device", comment: ""), selector: #selector(handleSwitchModeButton2Tapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.linkButton1"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var restoreStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ explanationLabel2, UIView.spacer(withHeight: 32), errorLabel1, errorLabel1Spacer, mnemonicTextField, UIView.spacer(withHeight: 24), registerButton1, linkButton2 ])
        result.accessibilityIdentifier = "onboarding.keyPairStep.restoreStackView"
        result.axis = .vertical
        return result
    }()
    
    private lazy var explanationLabel2: UILabel = {
        let result = createExplanationLabel(text: NSLocalizedString("Restore your account by entering your seed below.", comment: ""))
        result.accessibilityIdentifier = "onboarding.keyPairStep.explanationLabel2"
        result.textColor = Theme.primaryColor
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitBold)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: result.font.pointSize)
        return result
    }()
    
    private lazy var errorLabel1: UILabel = {
        let result = createExplanationLabel(text: "")
        result.accessibilityIdentifier = "onboarding.keyPairStep.errorLabel1"
        result.textColor = UIColor.red
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitBold)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: 12)
        return result
    }()
    
    private lazy var errorLabel1Spacer: UIView = {
        let result = UIView.spacer(withHeight: 32)
        result.isHidden = true
        return result
    }()
    
    private lazy var mnemonicTextField: UITextField = {
        let result = UITextField(frame: CGRect.zero)
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeBodyClamped
        result.textAlignment = .center
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Enter Your Seed", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Theme.placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = UIColor.lokiGreen()
        result.accessibilityIdentifier = "onboarding.keyPairStep.mnemonicTextField"
        result.keyboardAppearance = .dark
        return result
    }()
    
    private lazy var registerButton1: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Register a New Account", comment: ""), selector: #selector(handleSwitchModeButton1Tapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerButton1"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var linkButton2: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Link Device", comment: ""), selector: #selector(handleSwitchModeButton2Tapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.linkButton2"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var linkStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ explanationLabel3, UIView.spacer(withHeight: 32), errorLabel2, errorLabel2Spacer, masterHexEncodedPublicKeyTextField, UIView.spacer(withHeight: 24), registerButton2, restoreButton2 ])
        result.accessibilityIdentifier = "onboarding.keyPairStep.linkStackView"
        result.axis = .vertical
        return result
    }()
    
    private lazy var explanationLabel3: UILabel = {
        let result = createExplanationLabel(text: NSLocalizedString("Link to an existing device by going into Loki Messenger's in-app settings and clicking \"Link Device\".", comment: ""))
        result.accessibilityIdentifier = "onboarding.keyPairStep.explanationLabel3"
        result.textColor = Theme.primaryColor
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitBold)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: result.font.pointSize)
        return result
    }()
    
    private lazy var errorLabel2: UILabel = {
        let result = createExplanationLabel(text: "")
        result.accessibilityIdentifier = "onboarding.keyPairStep.errorLabel2"
        result.textColor = UIColor.red
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitBold)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: 12)
        return result
    }()
    
    private lazy var errorLabel2Spacer: UIView = {
        let result = UIView.spacer(withHeight: 32)
        result.isHidden = true
        return result
    }()
    
    private lazy var masterHexEncodedPublicKeyTextField: UITextField = {
        let result = UITextField(frame: CGRect.zero)
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeBodyClamped
        result.textAlignment = .center
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Enter Your Primary Account's Public Key", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Theme.placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = UIColor.lokiGreen()
        result.accessibilityIdentifier = "onboarding.keyPairStep.masterHexEncodedPublicKeyTextField"
        result.keyboardAppearance = .dark
        return result
    }()
    
    private lazy var registerButton2: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Register a New Account", comment: ""), selector: #selector(handleSwitchModeButton1Tapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerButton2"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var restoreButton2: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Restore Using Seed", comment: ""), selector: #selector(handleSwitchModeButton2Tapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.restoreButton2"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    // Shared
    private lazy var mainButton: OWSFlatButton = {
        let result = createButton(title: "", selector: #selector(handleMainButtonTapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.mainButton"
        return result
    }()
    
    // MARK: Types
    enum Mode { case register, restore, link }
    
    // MARK: Lifecycle
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
        mainView.addSubview(linkStackView)
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabel, mainView, mainButton ])
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
        linkStackView.autoPinWidthToSuperview()
        linkStackView.autoVCenterInSuperview()
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
        let (activeStackView, otherStackViews) = { () -> (UIStackView, [UIStackView]) in
            switch mode {
            case .register: return (registerStackView, [ restoreStackView, linkStackView ])
            case .restore: return (restoreStackView, [ registerStackView, linkStackView ])
            case .link: return (linkStackView, [ registerStackView, restoreStackView ])
            }
        }()
        UIView.animate(withDuration: 0.25) {
            activeStackView.alpha = 1
            otherStackViews.forEach { $0.alpha = 0 }
        }
        let mainButtonTitle: String = {
            switch mode {
            case .register: return NSLocalizedString("Register", comment: "")
            case .restore: return NSLocalizedString("Restore", comment: "")
            case .link: return NSLocalizedString("Link", comment: "")
            }
        }()
        UIView.transition(with: mainButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.mainButton.setTitle(mainButtonTitle)
        }, completion: nil)
        if mode != .restore { mnemonicTextField.resignFirstResponder() }
        if mode != .link { masterHexEncodedPublicKeyTextField.resignFirstResponder() }
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
    
    @objc private func handleSwitchModeButton1Tapped() {
        switch mode {
        case .register: mode = .restore
        case .restore: mode = .register
        case .link: mode = .register
        }
    }
    
    @objc private func handleSwitchModeButton2Tapped() {
        switch mode {
        case .register: mode = .link
        case .restore: mode = .link
        case .link: mode = .restore
        }
    }

    @objc private func handleMainButtonTapped() {
        var seed: Data
        let mode = self.mode
        switch mode {
        case .register: seed = self.seed
        case .restore:
            let mnemonic = mnemonicTextField.text!
            do {
                let hexEncodedSeed = try Mnemonic.decode(mnemonic: mnemonic)
                seed = Data(hex: hexEncodedSeed)
            } catch let error {
                let error = error as? Mnemonic.DecodingError ?? Mnemonic.DecodingError.generic
                errorLabel1Spacer.isHidden = false
                return errorLabel1.text = error.errorDescription
            }
        case .link:
            seed = self.seed
            let masterHexEncodedPublicKey = masterHexEncodedPublicKeyTextField.text!.trimmingCharacters(in: CharacterSet.whitespaces)
            if !ECKeyPair.isValidHexEncodedPublicKey(candidate: masterHexEncodedPublicKey) {
                errorLabel2Spacer.isHidden = false
                return errorLabel2.text = NSLocalizedString("Invalid public key", comment: "")
            }
        }
        // Use KVC to access dbConnection even though it's private
        let identityManager = OWSIdentityManager.shared()
        let databaseConnection = identityManager.value(forKey: "dbConnection") as! YapDatabaseConnection
        databaseConnection.setObject(seed.toHexString(), forKey: "LKLokiSeed", inCollection: OWSPrimaryStorageIdentityKeyStoreCollection)
        if seed.count == 16 { seed = seed + seed }
        identityManager.generateNewIdentityKeyPair(fromSeed: seed) // This also stores it
        let keyPair = identityManager.identityKeyPair()!
        let hexEncodedPublicKey = keyPair.hexEncodedPublicKey
        let accountManager = TSAccountManager.sharedInstance()
        accountManager.phoneNumberAwaitingVerification = hexEncodedPublicKey
        switch mode {
        case .register: Analytics.shared.track("Seed Created")
        case .restore: Analytics.shared.track("Seed Restored")
        case .link: Analytics.shared.track("Device Linked")
        }
        if mode == .link {
            let masterHexEncodedPublicKey = masterHexEncodedPublicKeyTextField.text!.trimmingCharacters(in: CharacterSet.whitespaces)
            let deviceLinkingModal = DeviceLinkingModal(mode: .slave, delegate: self)
            deviceLinkingModal.modalPresentationStyle = .overFullScreen
            present(deviceLinkingModal, animated: true, completion: nil)
            let thread = TSContactThread.getOrCreateThread(contactId: masterHexEncodedPublicKey)
            ThreadUtil.enqueueDeviceLinkingMessage(in: thread)
        } else {
            onboardingController.pushDisplayNameVC(from: self)
        }
    }
    
    func handleDeviceLinkingRequestAuthorized() {
        TSAccountManager.sharedInstance().didRegister()
        UserDefaults.standard.set(true, forKey: "didUpdateForMainnet")
        onboardingController.verificationDidComplete(fromView: self)
    }
}
