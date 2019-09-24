
@objc(LKNewConversationVC)
final class NewConversationVC : OWSViewController, OWSQRScannerDelegate {

    // MARK: Components
    private lazy var publicKeyTextField: UITextField = {
        let result = UITextField()
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeBodyClamped
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Enter a Public Key", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Theme.placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = UIColor.lokiGreen()
        result.keyboardAppearance = .dark
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Background color & margins
        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero
        // Navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(close))
        title = NSLocalizedString("New Conversation", comment: "")
        // Separator
        let separator = UIView()
        separator.autoSetDimension(.height, toSize: 1 / UIScreen.main.scale)
        separator.backgroundColor = Theme.hairlineColor
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.primaryColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.text = NSLocalizedString("Enter the public key of the person you'd like to securely message. They can share their public key with you by going into Loki Messenger's in-app settings and clicking \"Share Public Key\".", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // QR code button
        let qrCodeButtonFont = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
        let qrCodeButtonHeight = qrCodeButtonFont.pointSize * 48 / 17
        let qrCodeButton = OWSFlatButton.button(title: NSLocalizedString("Scan a QR Code Instead", comment: ""), font: qrCodeButtonFont, titleColor: .lokiGreen(), backgroundColor: .clear, target: self, selector: #selector(scanQRCode))
        qrCodeButton.setBackgroundColors(upColor: .clear, downColor: .clear)
        qrCodeButton.autoSetDimension(.height, toSize: qrCodeButtonHeight)
        qrCodeButton.button.contentHorizontalAlignment = .left
        // Next button
        let nextButtonFont = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
        let nextButtonHeight = nextButtonFont.pointSize * 48 / 17
        let nextButton = OWSFlatButton.button(title: NSLocalizedString("Next", comment: ""), font: nextButtonFont, titleColor: .white, backgroundColor: .lokiGreen(), target: self, selector: #selector(handleNextButtonTapped))
        nextButton.autoSetDimension(.height, toSize: nextButtonHeight)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [
            publicKeyTextField,
            UIView.spacer(withHeight: 8),
            separator,
            UIView.spacer(withHeight: 24),
            explanationLabel,
            UIView.spacer(withHeight: 8),
            qrCodeButton,
            UIView.vStretchingSpacer(),
            nextButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        publicKeyTextField.becomeFirstResponder()
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func scanQRCode() {
        ows_ask(forCameraPermissions: { [weak self] hasCameraAccess in
            if hasCameraAccess {
                let scanQRCodeVC = ScanQRCodeViewController()
                scanQRCodeVC.delegate = self
                self?.navigationController!.pushViewController(scanQRCodeVC, animated: true)
            } else {
                // Do nothing
            }
        })
    }
    
    func controller(_ controller: OWSQRCodeScanningViewController, didDetectQRCodeWith string: String) {
        Analytics.shared.track("QR Code Scanned")
        let hexEncodedPublicKey = string
        startNewConversationIfPossible(with: hexEncodedPublicKey)
    }
    
    @objc private func handleNextButtonTapped() {
        let hexEncodedPublicKey = publicKeyTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        startNewConversationIfPossible(with: hexEncodedPublicKey)
    }
    
    private func startNewConversationIfPossible(with hexEncodedPublicKey: String) {
        if !ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) {
            let alert = UIAlertController(title: NSLocalizedString("Invalid Public Key", comment: ""), message: NSLocalizedString("Please check the public key you entered and try again.", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        } else if OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey == hexEncodedPublicKey {
            let alert = UIAlertController(title: NSLocalizedString("Can't Start Conversation", comment: ""), message: NSLocalizedString("Please enter the public key of the person you'd like to message.", comment: ""), preferredStyle: .alert)
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
