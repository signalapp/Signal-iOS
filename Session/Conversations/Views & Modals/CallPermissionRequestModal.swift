// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

@objc
final class CallPermissionRequestModal : Modal {

    // MARK: Lifecycle
    @objc
    init() {
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(onCallEnabled:) instead.")
    }

    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(onCallEnabled:) instead.")
    }

    override func populateContentView() {
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = NSLocalizedString("modal_call_permission_request_title", comment: "")
        titleLabel.textAlignment = .center
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = NSLocalizedString("modal_call_permission_request_explanation", comment: "")
        messageLabel.text = message
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        // Enable button
        let goToSettingsButton = UIButton()
        goToSettingsButton.set(.height, to: Values.mediumButtonHeight)
        goToSettingsButton.layer.cornerRadius = Modal.buttonCornerRadius
        goToSettingsButton.backgroundColor = Colors.buttonBackground
        goToSettingsButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        goToSettingsButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        goToSettingsButton.setTitle(NSLocalizedString("vc_settings_title", comment: ""), for: UIControl.State.normal)
        goToSettingsButton.addTarget(self, action: #selector(goToSettings), for: UIControl.Event.touchUpInside)
        // Content stack view
        let contentStackView = UIStackView(arrangedSubviews: [ titleLabel, messageLabel ])
        contentStackView.axis = .vertical
        contentStackView.spacing = Values.largeSpacing
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, goToSettingsButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
        // Main stack view
        let spacing = Values.largeSpacing - Values.smallFontSize / 2
        let mainStackView = UIStackView(arrangedSubviews: [ contentStackView, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = spacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: spacing)
    }

    // MARK: Interaction
    @objc func goToSettings(_ sender: Any) {
        dismiss(animated: true, completion: {
            if let vc = CurrentAppContext().frontmostViewController() {
                let privacySettingsVC = PrivacySettingsTableViewController()
                privacySettingsVC.shouldShowCloseButton = true
                let nav = OWSNavigationController(rootViewController: privacySettingsVC)
                nav.modalPresentationStyle = .fullScreen
                vc.present(nav, animated: true, completion: nil)
            }
        })
    }
}
