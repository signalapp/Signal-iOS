
@objc(LKNewConversationVCV2)
final class NewConversationVCV2 : OWSViewController, OWSQRScannerDelegate {
    
    private lazy var userHexEncodedPublicKey: String = {
        let userDefaults = UserDefaults.standard
        if let masterHexEncodedPublicKey = userDefaults.string(forKey: "masterDeviceHexEncodedPublicKey") {
            return masterHexEncodedPublicKey
        } else {
            return OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        }
    }()
    
    // MARK: Components
    private lazy var publicKeyTextField = TextField(placeholder: NSLocalizedString("Enter public key of recipient", comment: ""))
    
    private lazy var userPublicKeyLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = Fonts.spaceMono(ofSize: Values.mediumFontSize)
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byCharWrapping
        return result
    }()
    
    private lazy var copyButton: Button = {
        let result = Button(style: .unimportant)
        result.setTitle(NSLocalizedString("Copy", comment: ""), for: UIControl.State.normal)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Set navigation bar background color
        if let navigationBar = navigationController?.navigationBar {
            navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
            navigationBar.shadowImage = UIImage()
            navigationBar.isTranslucent = false
            navigationBar.barTintColor = Colors.navigationBarBackground
        }
        // Set up the navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        // Customize title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("New Conversation", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = UIFont.boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("Users can share their public key by going into their account settings and tapping \"Share Public Key\", or by sharing their QR code.", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up separator
        let separator = Separator(title: NSLocalizedString("Your Public Key", comment: ""))
        separator.set(.height, to: 25)
        // Set up user public key label
        userPublicKeyLabel.text = userHexEncodedPublicKey
        // Set up share button
        let shareButton = Button(style: .unimportant)
        shareButton.setTitle(NSLocalizedString("Share", comment: ""), for: UIControl.State.normal)
        // Set up button container
        let buttonContainer = UIStackView(arrangedSubviews: [ copyButton, shareButton ])
        buttonContainer.axis = .horizontal
        buttonContainer.spacing = Values.mediumSpacing
        buttonContainer.distribution = .fillEqually
        // Next button
        let nextButton = Button(style: .prominent)
        nextButton.setTitle(NSLocalizedString("Next", comment: ""), for: UIControl.State.normal)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ publicKeyTextField, UIView.spacer(withHeight: Values.smallSpacing), explanationLabel, UIView.spacer(withHeight: Values.veryLargeSpacing), separator, UIView.spacer(withHeight: Values.veryLargeSpacing), userPublicKeyLabel, UIView.spacer(withHeight: Values.veryLargeSpacing), buttonContainer, UIView.spacer(withHeight: Values.veryLargeSpacing), nextButton, UIView.vStretchingSpacer() ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: Values.mediumSpacing, left: Values.largeSpacing, bottom: Values.mediumSpacing, right: Values.largeSpacing)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.pin(to: view)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        publicKeyTextField.becomeFirstResponder()
    }
    
    // MARK: General
    @objc private func enableCopyButton() {
//        copyButton.isUserInteractionEnabled = true
//        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
//            self.copyButton.setTitle(NSLocalizedString("Copy", comment: ""))
//        }, completion: nil)
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func copyPublicKey() {
//        UIPasteboard.general.string = userHexEncodedPublicKey
//        copyButton.isUserInteractionEnabled = false
//        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
//            self.copyButton.setTitle(NSLocalizedString("Copied ✓", comment: ""))
//        }, completion: nil)
//        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func sharePublicKey() {
        let shareVC = UIActivityViewController(activityItems: [ userHexEncodedPublicKey ], applicationActivities: nil)
        present(shareVC, animated: true, completion: nil)
//        NSString *hexEncodedPublicKey;
//        NSString *masterDeviceHexEncodedPublicKey = [NSUserDefaults.standardUserDefaults stringForKey:@"masterDeviceHexEncodedPublicKey"];
//        if (masterDeviceHexEncodedPublicKey != nil) {
//            hexEncodedPublicKey = masterDeviceHexEncodedPublicKey;
//        } else {
//            hexEncodedPublicKey = OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
//        }
//        UIActivityViewController *shareVC = [[UIActivityViewController alloc] initWithActivityItems:@[ hexEncodedPublicKey ] applicationActivities:nil];
//        [self presentViewController:shareVC animated:YES completion:nil];
//        [LKAnalytics.shared track:@"Public Key Shared"];
    }
    
//    @objc private func scanQRCode() {
//        ows_ask(forCameraPermissions: { [weak self] hasCameraAccess in
//            if hasCameraAccess {
//                let message = NSLocalizedString("Scan the QR code of the person you'd like to securely message. They can find their QR code by going into Loki Messenger's in-app settings and clicking \"Show QR Code\".", comment: "")
//                let scanQRCodeWrapperVC = ScanQRCodeWrapperVC(message: message)
//                scanQRCodeWrapperVC.delegate = self
//                self?.navigationController!.pushViewController(scanQRCodeWrapperVC, animated: true)
//            } else {
//                // Do nothing
//            }
//        })
//    }
//
//    func controller(_ controller: OWSQRCodeScanningViewController, didDetectQRCodeWith string: String) {
//        Analytics.shared.track("QR Code Scanned")
//        let hexEncodedPublicKey = string
//        startNewConversationIfPossible(with: hexEncodedPublicKey)
//    }
    
    @objc private func handleNextButtonTapped() {
        let hexEncodedPublicKey = publicKeyTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        startNewConversationIfPossible(with: hexEncodedPublicKey)
    }
    
    private func startNewConversationIfPossible(with hexEncodedPublicKey: String) {
        if !ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) {
            let alert = UIAlertController(title: NSLocalizedString("Invalid Public Key", comment: ""), message: NSLocalizedString("Please check the public key you entered and try again.", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        } else {
            let thread = TSContactThread.getOrCreateThread(contactId: hexEncodedPublicKey)
            Analytics.shared.track("New Conversation Started")
            SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
            presentingViewController!.dismiss(animated: true, completion: nil)
        }
    }
}
