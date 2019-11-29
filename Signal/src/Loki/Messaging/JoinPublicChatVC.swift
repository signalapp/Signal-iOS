
@objc(LKJoinPublicChatVC)
final class JoinPublicChatVC : OWSViewController {

    // MARK: Components
    private lazy var urlTextField: UITextField = {
        let result = UITextField()
        result.textColor = Theme.primaryColor
        result.font = .ows_dynamicTypeBodyClamped
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Enter a URL", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Theme.placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = .lokiGreen()
        result.keyboardAppearance = .dark
        result.keyboardType = .URL
        result.autocapitalizationType = .none
        return result
    }()
    
    private lazy var addButton = OWSFlatButton.button(title: NSLocalizedString("Add", comment: ""), font: UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight(), titleColor: .white, backgroundColor: .lokiGreen(), target: self, selector: #selector(handleAddButtonTapped))
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Background color & margins
        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero
        // Navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(close))
        title = NSLocalizedString("Add Public Chat", comment: "")
        // Separator
        let separator = UIView()
        separator.autoSetDimension(.height, toSize: 1 / UIScreen.main.scale)
        separator.backgroundColor = Theme.hairlineColor
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.primaryColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.text = NSLocalizedString("Enter the URL of the public chat you'd like to join. The Loki Public Chat URL is https://chat.lokinet.org.", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Add button
        let addButtonHeight = addButton.button.titleLabel!.font.pointSize * 48 / 17
        addButton.autoSetDimension(.height, toSize: addButtonHeight)
        updateAddButton(isConnecting: false)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ urlTextField, UIView.spacer(withHeight: 8), separator, UIView.spacer(withHeight: 24), explanationLabel, UIView.vStretchingSpacer(), addButton ])
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
        urlTextField.becomeFirstResponder()
    }
    
    // MARK: Updating
    private func updateAddButton(isConnecting: Bool) {
        addButton.setEnabled(!isConnecting)
        addButton.setTitle(isConnecting ? NSLocalizedString("Connecting...", comment: "") : NSLocalizedString("Add", comment: ""))
    }
    
    // MARK: General
    private func showError(title: String, message: String = "") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
        presentAlert(alert)
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func handleAddButtonTapped() {
        let uncheckedURL = (urlTextField.text?.trimmingCharacters(in: .whitespaces) ?? "").lowercased().replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: uncheckedURL), let scheme = url.scheme, scheme == "https", url.host != nil else {
            return showError(title: NSLocalizedString("Invalid URL", comment: ""), message: NSLocalizedString("Please check the URL you entered and try again.", comment: ""))
        }
        updateAddButton(isConnecting: true)
        let channelID: UInt64 = 1
        let urlAsString = url.absoluteString
        let displayName = OWSProfileManager.shared().localProfileName()
        LokiPublicChatManager.shared.addChat(server: urlAsString, channel: channelID)
        .done(on: .main) { [weak self] _ in
            let _ = LokiPublicChatAPI.getMessages(for: channelID, on: urlAsString)
            let _ = LokiPublicChatAPI.setDisplayName(to: displayName, on: urlAsString)
            self?.presentingViewController!.dismiss(animated: true, completion: nil)
        }
        .catch(on: .main) { [weak self] _ in
            self?.updateAddButton(isConnecting: false)
            self?.showError(title: NSLocalizedString("Couldn't Connect", comment: ""))
        }
    }
}
