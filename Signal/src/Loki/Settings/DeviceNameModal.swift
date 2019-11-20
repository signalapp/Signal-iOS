
@objc(LKDeviceNameModal)
final class DeviceNameModal : Modal {
    @objc public var device: DeviceLink.Device!
    @objc public var delegate: DeviceNameModalDelegate?
    
    // MARK: Components
    private lazy var nameTextView: UITextField = {
        let result = UITextField()
        result.textColor = Theme.primaryColor
        result.font = .ows_dynamicTypeBodyClamped
        result.textAlignment = .center
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Enter a Name", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: UIColor.white.withAlphaComponent(0.5), range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = .lokiGreen()
        result.keyboardAppearance = .dark
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardWillChangeFrameNotification(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }
    
    override func populateContentView() {
        // Label
        let titleLabel = UILabel()
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeHeadlineClamped
        titleLabel.text = NSLocalizedString("Change Device Name", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        explanationLabel.text = NSLocalizedString("Enter the new display name for your device below", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textColor = UIColor.ows_white
        // Button stack view
        let okButton = OWSFlatButton.button(title: NSLocalizedString("OK", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .white, backgroundColor: .clear, target: self, selector: #selector(changeName))
        okButton.setBackgroundColors(upColor: .clear, downColor: .clear)
        let buttonStackView = UIStackView(arrangedSubviews: [ okButton, cancelButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
        let buttonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        okButton.set(.height, to: buttonHeight)
        cancelButton.set(.height, to: buttonHeight)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ UIView.spacer(withHeight: 2), titleLabel, explanationLabel, nameTextView, buttonStackView ])
        stackView.axis = .vertical
        stackView.spacing = 16
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
        stackView.pin(.top, to: .top, of: contentView, withInset: 16)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 16)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Updating
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        verticalCenteringConstraint.constant = -(newHeight / 2)
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: Interaction
    @objc private func changeName() {
        let name = nameTextView.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "\(device.hexEncodedPublicKey)_display_name")
            delegate?.handleDeviceNameChanged(to: name, for: device)
        } else {
            let alert = UIAlertController(title: NSLocalizedString("Error", comment: ""), message: NSLocalizedString("Please pick a name", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), accessibilityIdentifier: nil, style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
}
