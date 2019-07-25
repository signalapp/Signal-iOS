
@objc(LKNewConversationViewController)
final class NewConversationViewController : OWSViewController {

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
        // Button
        let buttonFont = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
        let buttonHeight = buttonFont.pointSize * 48 / 17
        let startNewConversationButton = OWSFlatButton.button(title: NSLocalizedString("Next", comment: ""), font: buttonFont, titleColor: .white, backgroundColor: .lokiGreen(), target: self, selector: #selector(startNewConversationIfPossible))
        startNewConversationButton.autoSetDimension(.height, toSize: buttonHeight)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [
            publicKeyTextField,
            UIView.spacer(withHeight: 8),
            separator,
            UIView.spacer(withHeight: 8),
            explanationLabel,
            UIView.vStretchingSpacer(),
            startNewConversationButton
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
    
    @objc private func startNewConversationIfPossible() {
        let hexEncodedPublicKey = publicKeyTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        if !ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) {
            let alert = UIAlertController(title: NSLocalizedString("Invalid Public Key", comment: ""), message: NSLocalizedString("Please check the public key you entered and try again.", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        } else {
            let thread = TSContactThread.getOrCreateThread(contactId: hexEncodedPublicKey)
            SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
            presentingViewController!.dismiss(animated: true, completion: nil)
        }
    }
}
