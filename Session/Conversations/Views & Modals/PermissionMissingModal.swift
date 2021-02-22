
final class PermissionMissingModal : Modal {
    private let permission: String
    private let onCancel: () -> Void

    // MARK: Lifecycle
    init(permission: String, onCancel: @escaping () -> Void) {
        self.permission = permission
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(permission:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(permission:) instead.")
    }

    override func populateContentView() {
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        titleLabel.text = "Session"
        titleLabel.textAlignment = .center
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = "Session needs \(permission) access to continue. You can enable access in the iOS settings."
        let attributedMessage = NSMutableAttributedString(string: message)
        attributedMessage.addAttributes([ .font : UIFont.boldSystemFont(ofSize: Values.smallFontSize) ], range: (message as NSString).range(of: permission))
        messageLabel.attributedText = attributedMessage
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        // Settings button
        let settingsButton = UIButton()
        settingsButton.set(.height, to: Values.mediumButtonHeight)
        settingsButton.layer.cornerRadius = Modal.buttonCornerRadius
        settingsButton.backgroundColor = Colors.buttonBackground
        settingsButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        settingsButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        settingsButton.setTitle("Settings", for: UIControl.State.normal)
        settingsButton.addTarget(self, action: #selector(goToSettings), for: UIControl.Event.touchUpInside)
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, settingsButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabel, messageLabel, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = Values.largeSpacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }

    // MARK: Interaction
    @objc private func goToSettings() {
        presentingViewController?.dismiss(animated: true, completion: {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        })
    }

    override func close() {
        super.close()
        onCancel()
    }
}
