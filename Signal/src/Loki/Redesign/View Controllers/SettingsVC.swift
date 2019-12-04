
final class SettingsVC : UIViewController {
    
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
    private lazy var profilePictureView: ProfilePictureView = {
        let result = ProfilePictureView()
        let size = Values.largeProfilePictureSize
        result.size = size
        result.set(.width, to: size)
        result.set(.height, to: size)
        return result
    }()
    
    private lazy var displayNameLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.largeFontSize)
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    private lazy var copyButton: Button = {
        let result = Button(style: .prominent, size: .medium)
        result.setTitle(NSLocalizedString("Copy", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: UIControl.Event.touchUpInside)
        return result
    }()
    
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
        profilePictureView.hexEncodedPublicKey = userHexEncodedPublicKey
        profilePictureView.update()
        // Set up display name label
        displayNameLabel.text = OWSProfileManager.shared().profileName(forRecipientId: userHexEncodedPublicKey)
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
        let shareButton = Button(style: .regular, size: .medium)
        shareButton.setTitle(NSLocalizedString("Share", comment: ""), for: UIControl.State.normal)
        shareButton.addTarget(self, action: #selector(sharePublicKey), for: UIControl.Event.touchUpInside)
        // Set up button container
        let buttonContainer = UIStackView(arrangedSubviews: [ copyButton, shareButton ])
        buttonContainer.axis = .horizontal
        buttonContainer.spacing = Values.mediumSpacing
        buttonContainer.distribution = .fillEqually
        // Set up top stack view
        let topStackView = UIStackView(arrangedSubviews: [ headerStackView, separator, publicKeyLabel, buttonContainer ])
        topStackView.axis = .vertical
        topStackView.spacing = Values.largeSpacing
        topStackView.alignment = .fill
        topStackView.layoutMargins = UIEdgeInsets(top: 0, left: Values.largeSpacing, bottom: 0, right: Values.largeSpacing)
        topStackView.isLayoutMarginsRelativeArrangement = true
        // Set up setting buttons stack view
        let settingButtonsStackView = UIStackView(arrangedSubviews: getSettingButtons())
        settingButtonsStackView.axis = .vertical
        settingButtonsStackView.alignment = .fill
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ topStackView, settingButtonsStackView ])
        stackView.axis = .vertical
        stackView.spacing = Values.largeSpacing
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: Values.mediumSpacing, left: 0, bottom: Values.mediumSpacing, right: 0)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.set(.width, to: UIScreen.main.bounds.width)
        // Set up scroll view
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(stackView)
        stackView.pin(to: scrollView)
        view.addSubview(scrollView)
        scrollView.pin(to: view)
    }
    
    private func getSettingButtons() -> [UIButton] {
        func getSettingButton(withTitle title: String, color: UIColor, action selector: Selector) -> UIButton {
            let button = UIButton()
            button.setTitle(title, for: UIControl.State.normal)
            button.setTitleColor(color, for: UIControl.State.normal)
            button.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
            button.titleLabel!.textAlignment = .center
            func getImage(withColor color: UIColor) -> UIImage {
                let rect = CGRect(origin: CGPoint.zero, size: CGSize(width: 1, height: 1))
                UIGraphicsBeginImageContext(rect.size)
                let context = UIGraphicsGetCurrentContext()!
                context.setFillColor(color.cgColor)
                context.fill(rect)
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return image!
            }
            button.setBackgroundImage(getImage(withColor: Colors.settingButtonBackground), for: UIControl.State.normal)
            button.setBackgroundImage(getImage(withColor: Colors.settingButtonSelected), for: UIControl.State.highlighted)
            button.addTarget(self, action: selector, for: UIControl.Event.touchUpInside)
            button.set(.height, to: Values.settingsButtonHeight)
            return button
        }
        return [
            getSettingButton(withTitle: NSLocalizedString("Privacy", comment: ""), color: Colors.text, action: #selector(showPrivacySettings)),
            getSettingButton(withTitle: NSLocalizedString("Notifications", comment: ""), color: Colors.text, action: #selector(showNotificationSettings)),
            getSettingButton(withTitle: NSLocalizedString("Linked Devices", comment: ""), color: Colors.text, action: #selector(showLinkedDevices)),
            getSettingButton(withTitle: NSLocalizedString("Show Seed", comment: ""), color: Colors.text, action: #selector(showSeed)),
            getSettingButton(withTitle: NSLocalizedString("Clear All Data", comment: ""), color: Colors.destructive, action: #selector(clearAllData))
        ]
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        profilePictureView.update()
        displayNameLabel.text = OWSProfileManager.shared().profileName(forRecipientId: userHexEncodedPublicKey)
    }
    
    // MARK: General
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
        let qrCodeModal = QRCodeModal()
        qrCodeModal.modalPresentationStyle = .overFullScreen
        present(qrCodeModal, animated: true, completion: nil)
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
    
    @objc private func showPrivacySettings() {
        let privacySettingsVC = PrivacySettingsTableViewController()
        navigationController!.pushViewController(privacySettingsVC, animated: true)
    }
    
    @objc private func showNotificationSettings() {
        let notificationSettingsVC = NotificationSettingsViewController()
        navigationController!.pushViewController(notificationSettingsVC, animated: true)
    }
    
    @objc private func showLinkedDevices() {
        let deviceLinksVC = DeviceLinksVC()
        navigationController!.pushViewController(deviceLinksVC, animated: true)
    }
    
    @objc private func showSeed() {
        let seedModal = SeedModal()
        seedModal.modalPresentationStyle = .overFullScreen
        present(seedModal, animated: true, completion: nil)
    }
    
    @objc private func clearAllData() {
        let nukeDataModal = NukeDataModal()
        nukeDataModal.modalPresentationStyle = .overFullScreen
        present(nukeDataModal, animated: true, completion: nil)
    }
}
