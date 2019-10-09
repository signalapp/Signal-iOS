
@objc(LKNewPublicChatVC)
final class NewPublicChatVC : OWSViewController {

    // MARK: Components
    private lazy var serverUrlTextField: UITextField = {
        let result = UITextField()
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeBodyClamped
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Enter a Server URL", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Theme.placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = UIColor.lokiGreen()
        result.keyboardAppearance = .dark
        return result
    }()
    
    private lazy var addButton: OWSFlatButton = {
        let addButtonFont = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
        let addButtonHeight = addButtonFont.pointSize * 48 / 17
        let addButton = OWSFlatButton.button(title: NSLocalizedString("Add", comment: ""), font: addButtonFont, titleColor: .white, backgroundColor: .lokiGreen(), target: self, selector: #selector(handleNextButtonTapped))
        addButton.autoSetDimension(.height, toSize: addButtonHeight)
        return addButton
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Background color & margins
        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero
        // Navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(close))
        title = NSLocalizedString("Add Public Chat Server", comment: "")
        // Separator
        let separator = UIView()
        separator.autoSetDimension(.height, toSize: 1 / UIScreen.main.scale)
        separator.backgroundColor = Theme.hairlineColor
        
        updateButton(enabled: true)
       
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [
            serverUrlTextField,
            UIView.vStretchingSpacer(),
            addButton
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
        serverUrlTextField.becomeFirstResponder()
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func handleNextButtonTapped() {
        let serverURL = (serverUrlTextField.text?.trimmingCharacters(in: .whitespaces) ?? "").lowercased().replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: serverURL), let scheme = url.scheme, scheme == "https", let _ = url.host else {
            showAlert(title: NSLocalizedString("Invalid server URL provided", comment: ""), message: NSLocalizedString("Please make sure you have provided the full url", comment: ""))
            return
        }
        
        updateButton(enabled: false)
        
        // TODO: Upon adding we should fetch previous messages
        LokiPublicChatManager.shared.addChat(server: serverURL, channel: 1)
        .done(on: .main) { _ in
            self.presentingViewController!.dismiss(animated: true, completion: nil)
        }
        .catch(on: .main) { e in
            self.updateButton(enabled: true)
            self.showAlert(title: NSLocalizedString("Failed to connect to server", comment: ""))
        }
    }
    
    private func showAlert(title: String, message: String = "") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
        presentAlert(alert)
    }
    
    private func updateButton(enabled: Bool) {
        addButton.setEnabled(enabled)
        addButton.setTitle(enabled ? NSLocalizedString("Add", comment: "") : NSLocalizedString("Connecting to server", comment: ""))
    }
}
