
@objc(LKDeviceNameModal)
final class DeviceNameModal : Modal {
    @objc public var device: DeviceLink.Device!
    @objc public var delegate: DeviceNameModalDelegate?
    
    // MARK: Components
    private lazy var nameTextField: UITextField = {
        let result = UITextField()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.textAlignment = .center
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Enter a Name", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Colors.text.withAlphaComponent(Values.unimportantElementOpacity), range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = Colors.accent
        result.keyboardAppearance = .dark
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillChangeFrameNotification(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillHideNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    override func populateContentView() {
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = NSLocalizedString("Change Device Name", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("Enter the new display name for your device below", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up OK button
        let okButton = UIButton()
        okButton.set(.height, to: Values.mediumButtonHeight)
        okButton.layer.cornerRadius = Values.modalButtonCornerRadius
        okButton.backgroundColor = Colors.accent
        okButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        okButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        okButton.setTitle(NSLocalizedString("OK", comment: ""), for: UIControl.State.normal)
        okButton.addTarget(self, action: #selector(changeName), for: UIControl.Event.touchUpInside)
        // Set up button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, okButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        // Set up main stack view
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, nameTextField, buttonStackView ])
        stackView.axis = .vertical
        stackView.spacing = Values.largeSpacing
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.largeSpacing)
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
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        verticalCenteringConstraint.constant = 0
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: Interaction
    @objc private func changeName() {
        let name = nameTextField.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !name.isEmpty {
            UserDefaults.standard[.slaveDeviceName(device.publicKey)] = name
            delegate?.handleDeviceNameChanged(to: name, for: device)
        } else {
            let alert = UIAlertController(title: NSLocalizedString("Error", comment: ""), message: NSLocalizedString("Please pick a name", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), accessibilityIdentifier: nil, style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
}
