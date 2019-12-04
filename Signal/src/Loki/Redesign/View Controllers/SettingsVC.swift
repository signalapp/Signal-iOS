
final class SettingsVC : UIViewController {
    
    private lazy var settings: [Setting] = {
        return [
            Setting(title: NSLocalizedString("Privacy", comment: ""), color: Colors.text) { [weak self] in self?.showPrivacySettings() },
            Setting(title: NSLocalizedString("Notifications", comment: ""), color: Colors.text) { [weak self] in self?.showNotificationSettings() },
            Setting(title: NSLocalizedString("Linked Devices", comment: ""), color: Colors.text) { [weak self] in self?.showLinkedDevices() },
            Setting(title: NSLocalizedString("Show Seed", comment: ""), color: Colors.text) { [weak self] in self?.showSeed() },
            Setting(title: NSLocalizedString("Clear All Data", comment: ""), color: Colors.destructive) { [weak self] in self?.clearAllData() }
        ]
    }()
    
    private lazy var userHexEncodedPublicKey: String = {
        let userDefaults = UserDefaults.standard
        if let masterHexEncodedPublicKey = userDefaults.string(forKey: "masterDeviceHexEncodedPublicKey") {
            return masterHexEncodedPublicKey
        } else {
            return OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        }
    }()
    
    // MARK: Settings
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    // MARK: Components
    private lazy var copyButton: Button = {
        let result = Button(style: .prominent)
        result.setTitle(NSLocalizedString("Copy", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    // MARK: Types
    private struct Setting {
        let title: String
        let color: UIColor
        let onTap: () -> Void
    }
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Set navigation bar background color
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        let qrCodeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "QRCodeFilled"), style: .plain, target: self, action: #selector(showQRCode))
        qrCodeButton.tintColor = Colors.text
        navigationItem.rightBarButtonItem = qrCodeButton
        // Customize title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Settings", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = UIFont.boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Set up profile picture view
        let profilePictureView = ProfilePictureView()
        profilePictureView.hexEncodedPublicKey = userHexEncodedPublicKey
        let profilePictureSize = Values.largeProfilePictureSize
        profilePictureView.size = profilePictureSize
        profilePictureView.set(.width, to: profilePictureSize)
        profilePictureView.set(.height, to: profilePictureSize)
        profilePictureView.update()
        // Set up display name label
        let displayNameLabel = UILabel()
        displayNameLabel.textColor = Colors.text
        displayNameLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        displayNameLabel.text = OWSProfileManager.shared().profileName(forRecipientId: userHexEncodedPublicKey)
        displayNameLabel.lineBreakMode = .byTruncatingTail
        // Set up header view
        let headerStackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameLabel ])
        headerStackView.axis = .vertical
        headerStackView.spacing = Values.smallSpacing
        headerStackView.alignment = .center
        // Set up separator
        let separator = Separator(title: NSLocalizedString("Your Public Key", comment: ""))
        // Set up public key label
        let publicKeyLabel = UILabel()
        publicKeyLabel.textColor = Colors.text
        publicKeyLabel.font = Fonts.spaceMono(ofSize: Values.largeFontSize)
        publicKeyLabel.numberOfLines = 0
        publicKeyLabel.textAlignment = .center
        publicKeyLabel.lineBreakMode = .byCharWrapping
        publicKeyLabel.text = userHexEncodedPublicKey
        // Set up share button
        let shareButton = Button(style: .regular)
        shareButton.setTitle(NSLocalizedString("Share", comment: ""), for: UIControl.State.normal)
        shareButton.addTarget(self, action: #selector(sharePublicKey), for: UIControl.Event.touchUpInside)
        // Set up button container
        let buttonContainer = UIStackView(arrangedSubviews: [ copyButton, shareButton ])
        buttonContainer.axis = .horizontal
        buttonContainer.spacing = Values.mediumSpacing
        buttonContainer.distribution = .fillEqually
        // Set up settings stack view
        let settingViews: [UIButton] = settings.map { setting in
            let button = UIButton()
            button.setTitle(setting.title, for: UIControl.State.normal)
            button.setTitleColor(setting.color, for: UIControl.State.normal)
            button.titleLabel!.textAlignment = .center
            button.set(.height, to: 75)
            return button
        }
        let settingsStackView = UIStackView(arrangedSubviews: settingViews)
        settingsStackView.axis = .vertical
        settingsStackView.alignment = .fill
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ headerStackView, separator, publicKeyLabel, buttonContainer, settingsStackView, UIView.vStretchingSpacer() ])
        stackView.axis = .vertical
        stackView.spacing = Values.largeSpacing
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: Values.mediumSpacing, left: Values.largeSpacing, bottom: Values.mediumSpacing, right: Values.largeSpacing)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.pin(to: view)
    }
    
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("Copy", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func showQRCode() {
        // TODO: Implement
    }
    
    @objc private func copyPublicKey() {
        UIPasteboard.general.string = userHexEncodedPublicKey
        copyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("Copied", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func sharePublicKey() {
        let shareVC = UIActivityViewController(activityItems: [ userHexEncodedPublicKey ], applicationActivities: nil)
        navigationController!.present(shareVC, animated: true, completion: nil)
    }
    
    private func showPrivacySettings() {
        
    }
    
    private func showNotificationSettings() {
        
    }
    
    private func showLinkedDevices() {
        
    }
    
    private func showSeed() {
        
    }
    
    private func clearAllData() {
        
    }
}
