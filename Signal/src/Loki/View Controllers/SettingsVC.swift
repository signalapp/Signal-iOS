
final class SettingsVC : UIViewController, AvatarViewHelperDelegate {
    private var profilePictureToBeUploaded: UIImage?
    private var displayNameToBeUploaded: String?
    private var isEditingDisplayName = false { didSet { handleIsEditingDisplayNameChanged() } }
    
    private lazy var userHexEncodedPublicKey: String = {
        if let masterHexEncodedPublicKey = UserDefaults.standard.string(forKey: "masterDeviceHexEncodedPublicKey") {
            return masterHexEncodedPublicKey
        } else {
            return getUserHexEncodedPublicKey()
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
    
    private lazy var profilePictureUtilities: AvatarViewHelper = {
        let result = AvatarViewHelper()
        result.delegate = self
        return result
    }()
    
    private lazy var displayNameLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.lineBreakMode = .byTruncatingTail
        result.textAlignment = .center
        return result
    }()
    
    private lazy var displayNameTextField: TextField = {
        let result = TextField(placeholder: NSLocalizedString("Enter a display name", comment: ""), usesDefaultHeight: false)
        result.textAlignment = .center
        return result
    }()
    
    private lazy var copyButton: Button = {
        let result = Button(style: .prominentOutline, size: .medium)
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
        let backButton = UIBarButtonItem(title: NSLocalizedString("Back", comment: ""), style: .plain, target: nil, action: nil)
        backButton.tintColor = Colors.text
        navigationItem.backBarButtonItem = backButton
        updateNavigationBarButtons()
        // Customize title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Settings", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Set up profile picture view
        let profilePictureTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showEditProfilePictureUI))
        profilePictureView.addGestureRecognizer(profilePictureTapGestureRecognizer)
        profilePictureView.hexEncodedPublicKey = userHexEncodedPublicKey
        profilePictureView.update()
        // Set up display name label
        displayNameLabel.text = OWSProfileManager.shared().profileName(forRecipientId: userHexEncodedPublicKey)
        // Set up display name container
        let displayNameContainer = UIView()
        displayNameContainer.addSubview(displayNameLabel)
        displayNameLabel.pin(to: displayNameContainer)
        displayNameContainer.addSubview(displayNameTextField)
        displayNameTextField.pin(to: displayNameContainer)
        displayNameContainer.set(.height, to: 40)
        displayNameTextField.alpha = 0
        let displayNameContainerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showEditDisplayNameUI))
        displayNameContainer.addGestureRecognizer(displayNameContainerTapGestureRecognizer)
        // Set up header view
        let headerStackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameContainer ])
        headerStackView.axis = .vertical
        headerStackView.spacing = Values.smallSpacing
        headerStackView.alignment = .center
        // Set up separator
        let separator = Separator(title: NSLocalizedString("Your Session ID", comment: ""))
        // Set up public key label
        let publicKeyLabel = UILabel()
        publicKeyLabel.textColor = Colors.text
        publicKeyLabel.font = Fonts.spaceMono(ofSize: isSmallScreen ? Values.mediumFontSize : Values.largeFontSize)
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
        let settingButtonsStackView = UIStackView(arrangedSubviews: getSettingButtons() )
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
    
    private func getSettingButtons() -> [UIView] {
        func getSeparator() -> UIView {
            let result = UIView()
            result.backgroundColor = Colors.separator
            result.set(.height, to: Values.separatorThickness)
            return result
        }
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
            button.setBackgroundImage(getImage(withColor: Colors.buttonBackground), for: UIControl.State.normal)
            button.setBackgroundImage(getImage(withColor: Colors.settingButtonSelected), for: UIControl.State.highlighted)
            button.addTarget(self, action: selector, for: UIControl.Event.touchUpInside)
            button.set(.height, to: Values.settingButtonHeight)
            return button
        }
        var result = [
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("Privacy", comment: ""), color: Colors.text, action: #selector(showPrivacySettings)),
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("Notifications", comment: ""), color: Colors.text, action: #selector(showNotificationSettings))
        ]
        let isMasterDevice = (UserDefaults.standard.string(forKey: "masterDeviceHexEncodedPublicKey") == nil)
        if isMasterDevice {
            result.append(getSeparator())
            result.append(getSettingButton(withTitle: NSLocalizedString("Devices", comment: ""), color: Colors.text, action: #selector(showLinkedDevices)))
            result.append(getSeparator())
            result.append(getSettingButton(withTitle: NSLocalizedString("Recovery Phrase", comment: ""), color: Colors.text, action: #selector(showSeed)))
        }
        result.append(getSeparator())
        result.append(getSettingButton(withTitle: NSLocalizedString("Clear All Data", comment: ""), color: Colors.destructive, action: #selector(clearAllData)))
        result.append(getSeparator())
        return result
    }
    
    // MARK: General
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("Copy", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
    }
    
    func avatarActionSheetTitle() -> String? {
        return NSLocalizedString("Update Profile Picture", comment: "")
    }
    
    func fromViewController() -> UIViewController {
        return self
    }
    
    func hasClearAvatarAction() -> Bool {
        return true
    }
    
    func clearAvatarActionLabel() -> String {
        return NSLocalizedString("Clear", comment: "")
    }
    
    // MARK: Updating
    private func handleIsEditingDisplayNameChanged() {
        updateNavigationBarButtons()
        UIView.animate(withDuration: 0.25) {
            self.displayNameLabel.alpha = self.isEditingDisplayName ? 0 : 1
            self.displayNameTextField.alpha = self.isEditingDisplayName ? 1 : 0
        }
        if isEditingDisplayName {
            displayNameTextField.becomeFirstResponder()
        } else {
            displayNameTextField.resignFirstResponder()
        }
    }
    
    private func updateNavigationBarButtons() {
        if isEditingDisplayName {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(handleCancelDisplayNameEditingButtonTapped))
            cancelButton.tintColor = Colors.text
            navigationItem.leftBarButtonItem = cancelButton
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(handleSaveDisplayNameButtonTapped))
            doneButton.tintColor = Colors.text
            navigationItem.rightBarButtonItem = doneButton
        } else {
            let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
            closeButton.tintColor = Colors.text
            navigationItem.leftBarButtonItem = closeButton
            let qrCodeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "QRCode"), style: .plain, target: self, action: #selector(showQRCode))
            qrCodeButton.tintColor = Colors.text
            navigationItem.rightBarButtonItem = qrCodeButton
        }
    }
    
    func avatarDidChange(_ image: UIImage) {
        let maxSize = Int(kOWSProfileManager_MaxAvatarDiameter)
        profilePictureToBeUploaded = image.resizedImage(toFillPixelSize: CGSize(width: maxSize, height: maxSize))
        updateProfile(isUpdatingDisplayName: false, isUpdatingProfilePicture: true)
    }
    
    func clearAvatar() {
        profilePictureToBeUploaded = nil
        updateProfile(isUpdatingDisplayName: false, isUpdatingProfilePicture: true)
    }
    
    private func updateProfile(isUpdatingDisplayName: Bool, isUpdatingProfilePicture: Bool) {
        let displayName = displayNameToBeUploaded ?? OWSProfileManager.shared().profileName(forRecipientId: userHexEncodedPublicKey)
        let profilePicture = profilePictureToBeUploaded ?? OWSProfileManager.shared().profileAvatar(forRecipientId: userHexEncodedPublicKey)
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self] modalActivityIndicator in
            OWSProfileManager.shared().updateLocalProfileName(displayName, avatarImage: profilePicture, success: {
                DispatchQueue.main.async {
                    modalActivityIndicator.dismiss {
                        guard let self = self else { return }
                        self.profilePictureView.update()
                        self.displayNameLabel.text = displayName
                        self.profilePictureToBeUploaded = nil
                        self.displayNameToBeUploaded = nil
                    }
                }
            }, failure: { error in
                DispatchQueue.main.async {
                    modalActivityIndicator.dismiss {
                        var isMaxFileSizeExceeded = false
                        if let error = error as? LokiDotNetAPI.LokiDotNetAPIError {
                            isMaxFileSizeExceeded = (error == .maxFileSizeExceeded)
                        }
                        let title = isMaxFileSizeExceeded ? "Maximum File Size Exceeded" : NSLocalizedString("Couldn't Update Profile", comment: "")
                        let message = isMaxFileSizeExceeded ? "Please select a smaller photo and try again" : NSLocalizedString("Please check your internet connection and try again", comment: "")
                        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
                        self?.present(alert, animated: true, completion: nil)
                    }
                }
            }, requiresSync: true)
        }
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func showQRCode() {
        let qrCodeVC = QRCodeVC()
        navigationController!.pushViewController(qrCodeVC, animated: true)
    }
    
    @objc private func handleCancelDisplayNameEditingButtonTapped() {
        isEditingDisplayName = false
    }
    
    @objc private func handleSaveDisplayNameButtonTapped() {
        func showError(title: String, message: String = "") {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        }
        let displayName = displayNameTextField.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            return showError(title: NSLocalizedString("Please pick a display name", comment: ""))
        }
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ ")
        let hasInvalidCharacters = !displayName.allSatisfy { $0.unicodeScalars.allSatisfy { allowedCharacters.contains($0) } }
        guard !hasInvalidCharacters else {
            return showError(title: NSLocalizedString("Please pick a display name that consists of only a-z, A-Z, 0-9 and _ characters", comment: ""))
        }
        guard !OWSProfileManager.shared().isProfileNameTooLong(displayName) else {
            return showError(title: NSLocalizedString("Please pick a shorter display name", comment: ""))
        }
        isEditingDisplayName = false
        displayNameToBeUploaded = displayName
        updateProfile(isUpdatingDisplayName: true, isUpdatingProfilePicture: false)
    }
    
    @objc private func showEditProfilePictureUI() {
        profilePictureUtilities.showChangeAvatarUI()
    }
    
    @objc private func showEditDisplayNameUI() {
        isEditingDisplayName = true
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
        seedModal.modalTransitionStyle = .crossDissolve
        present(seedModal, animated: true, completion: nil)
    }
    
    @objc private func clearAllData() {
        let nukeDataModal = NukeDataModal()
        nukeDataModal.modalPresentationStyle = .overFullScreen
        nukeDataModal.modalTransitionStyle = .crossDissolve
        present(nukeDataModal, animated: true, completion: nil)
    }
}
