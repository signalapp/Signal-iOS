
final class SeedVC : OnboardingBaseViewController, DeviceLinkingModalDelegate, OWSQRScannerDelegate {
    private var mode: Mode = .register { didSet { if mode != oldValue { handleModeChanged() } } }
    private var seed: Data! { didSet { updateMnemonic() } }
    private var mnemonic: String! { didSet { handleMnemonicChanged() } }

    // MARK: Components
    private lazy var registerStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ explanationLabel1, UIView.spacer(withHeight: 32), mnemonicLabel, UIView.spacer(withHeight: 24), copyButton, restoreButton, linkButton1 ])
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerStackView"
        result.axis = .vertical
        return result
    }()
    
    private lazy var explanationLabel1: UILabel = {
        let result = createExplanationLabel(text: NSLocalizedString("Please save the seed below in a safe location. It can be used to restore your account if you lose access, or to migrate your account to a new device.", comment: ""))
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
    
    private lazy var restoreButton: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Restore Using Seed", comment: ""), selector: #selector(handleSwitchModeButton1Tapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.restoreButton"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var linkButton1: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Link Device", comment: ""), selector: #selector(handleLinkButtonTapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.linkButton1"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var restoreStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ explanationLabel2, UIView.spacer(withHeight: 32), errorLabel, errorLabelSpacer, mnemonicTextField, UIView.spacer(withHeight: 24), registerButton, linkButton2 ])
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
    
    private lazy var errorLabel: UILabel = {
        let result = createExplanationLabel(text: "")
        result.accessibilityIdentifier = "onboarding.keyPairStep.errorLabel"
        result.textColor = UIColor.red
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitBold)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: 12)
        return result
    }()
    
    private lazy var errorLabelSpacer: UIView = {
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
    
    private lazy var registerButton: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Register a New Account", comment: ""), selector: #selector(handleSwitchModeButton1Tapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.registerButton"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var linkButton2: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Link Device", comment: ""), selector: #selector(handleLinkButtonTapped))
        result.accessibilityIdentifier = "onboarding.keyPairStep.linkButton2"
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    private lazy var mainButton: OWSFlatButton = {
        let result = createButton(title: "", selector: #selector(objc_proceed))
        result.accessibilityIdentifier = "onboarding.keyPairStep.mainButton"
        return result
    }()
    
    // MARK: Types
    enum Mode { case register, restore }
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.loadView()
        setUpViewHierarchy()
        handleModeChanged() // Perform initial update
        updateSeed()
        Analytics.shared.track("Seed Screen Viewed")
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
            case .register: return (registerStackView, [ restoreStackView ])
            case .restore: return (restoreStackView, [ registerStackView ])
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
            }
        }()
        UIView.transition(with: mainButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.mainButton.setTitle(mainButtonTitle)
        }, completion: nil)
        if mode != .restore { mnemonicTextField.resignFirstResponder() }
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
        }
    }
    
    @objc private func handleLinkButtonTapped() {
        ows_ask(forCameraPermissions: { [weak self] hasCameraAccess in
            guard let self = self else { return }
            if hasCameraAccess {
                let message = NSLocalizedString("Link to an existing device by going into its in-app settings and clicking \"Link Device\".", comment: "")
                let scanQRCodeWrapperVC = ScanQRCodeWrapperVC(message: message)
                scanQRCodeWrapperVC.delegate = self
                scanQRCodeWrapperVC.isPresentedModally = true
                let navigationVC = OWSNavigationController(rootViewController: scanQRCodeWrapperVC)
                self.present(navigationVC, animated: true, completion: nil)
            } else {
                // Do nothing
            }
        })
    }
    
    func controller(_ controller: OWSQRCodeScanningViewController, didDetectQRCodeWith string: String) {
        dismiss(animated: true, completion: nil)
        DispatchQueue.main.async { [weak self] in
            self?.proceed(with: string)
        }
    }

    @objc private func objc_proceed() {
        proceed()
    }
    
    private func proceed(with masterHexEncodedPublicKey: String? = nil) {
        var seed: Data
        if let masterHexEncodedPublicKey = masterHexEncodedPublicKey {
            seed = self.seed
            if !ECKeyPair.isValidHexEncodedPublicKey(candidate: masterHexEncodedPublicKey) {
                let alert = UIAlertController(title: NSLocalizedString("Invalid QR Code", comment: ""), message: NSLocalizedString("Please make sure the QR code you scanned is correct and try again.", comment: ""), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), accessibilityIdentifier: nil, style: .default, handler: nil))
                return present(alert, animated: true, completion: nil)
            }
            Analytics.shared.track("Device Linking Attempted")
        } else {
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
                    errorLabelSpacer.isHidden = false
                    return errorLabel.text = error.errorDescription
                }
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
        }
        if let masterHexEncodedPublicKey = masterHexEncodedPublicKey {
            TSAccountManager.sharedInstance().didRegister()
            setUserInteractionEnabled(false)
            let _ = LokiStorageAPI.getDeviceLinks(associatedWith: masterHexEncodedPublicKey).done(on: DispatchQueue.main) { [weak self] deviceLinks in
                guard let self = self else { return }
                defer { self.setUserInteractionEnabled(true) }
                guard deviceLinks.count < 2 else {
                    let alert = UIAlertController(title: "Multi Device Limit Reached", message: "It's currently not allowed to link more than one device.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", accessibilityIdentifier: nil, style: .default, handler: nil))
                    return self.present(alert, animated: true, completion: nil)
                }
                let appDelegate = UIApplication.shared.delegate as! AppDelegate
                appDelegate.startLongPollerIfNeeded()
                let deviceLinkingModal = DeviceLinkingModal(mode: .slave, delegate: self)
                deviceLinkingModal.modalPresentationStyle = .overFullScreen
                self.present(deviceLinkingModal, animated: true, completion: nil)
                let linkingRequestMessage = DeviceLinkingUtilities.getLinkingRequestMessage(for: masterHexEncodedPublicKey)
                ThreadUtil.enqueue(linkingRequestMessage)
            }.catch(on: DispatchQueue.main) { [weak self] _ in
                TSAccountManager.sharedInstance().resetForReregistration()
                guard let self = self else { return }
                let alert = UIAlertController(title: NSLocalizedString("Couldn't Link Device", comment: ""), message: NSLocalizedString("Please check your connection and try again.", comment: ""), preferredStyle: .alert)
                self.present(alert, animated: true, completion: nil)
                self.setUserInteractionEnabled(true)
            }
        } else {
            onboardingController.pushDisplayNameVC(from: self)
        }
    }
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(true, forKey: "didUpdateForMainnet")
        userDefaults.set(deviceLink.master.hexEncodedPublicKey, forKey: "masterDeviceHexEncodedPublicKey")
        onboardingController.verificationDidComplete(fromView: self)
        Analytics.shared.track("Device Linked Successfully")
    }
    
    func handleDeviceLinkingModalDismissed() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.stopLongPollerIfNeeded()
        TSAccountManager.sharedInstance().resetForReregistration()
    }
    
    // MARK: Convenience
    private func setUserInteractionEnabled(_ isEnabled: Bool) {
        [ copyButton, restoreButton, linkButton1, registerButton, linkButton2, mainButton ].forEach {
            $0.isUserInteractionEnabled = isEnabled
        }
    }
}
