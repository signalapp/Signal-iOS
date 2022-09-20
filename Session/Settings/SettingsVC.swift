// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit
import SessionMessagingKit
import SignalUtilitiesKit

final class SettingsVC: BaseVC, AvatarViewHelperDelegate {
    private var displayNameToBeUploaded: String?
    private var isEditingDisplayName = false { didSet { handleIsEditingDisplayNameChanged() } }
    
    // MARK: - Components
    
    private lazy var profilePictureView: ProfilePictureView = {
        let result = ProfilePictureView()
        let size = Values.largeProfilePictureSize
        result.size = size
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.accessibilityLabel = "Edit profile picture button"
        result.isAccessibilityElement = true
        
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
        let result = TextField(placeholder: NSLocalizedString("vc_settings_display_name_text_field_hint", comment: ""), usesDefaultHeight: false)
        result.textAlignment = .center
        result.accessibilityLabel = "Edit display name text field"
        
        return result
    }()
    
    private lazy var publicKeyLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = Fonts.spaceMono(ofSize: isIPhone5OrSmaller ? Values.mediumFontSize : Values.largeFontSize)
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byCharWrapping
        result.text = getUserHexEncodedPublicKey()
        
        return result
    }()
    
    private lazy var copyButton: Button = {
        let result = Button(style: .prominentOutline, size: .medium)
        result.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: UIControl.Event.touchUpInside)
        
        return result
    }()

    private lazy var settingButtonsStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.alignment = .fill
        
        return result
    }()
    
    private lazy var inviteButton: UIButton = {
        let result = UIButton()
        result.setTitle(NSLocalizedString("vc_settings_invite_a_friend_button_title", comment: ""), for: UIControl.State.normal)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.titleLabel!.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.addTarget(self, action: #selector(sendInvitation), for: UIControl.Event.touchUpInside)
        
        return result
    }()
    
    private lazy var faqButton: UIButton = {
        let result = UIButton()
        result.setTitle(NSLocalizedString("vc_settings_faq_button_title", comment: ""), for: UIControl.State.normal)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.titleLabel!.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.addTarget(self, action: #selector(openFAQ), for: UIControl.Event.touchUpInside)
        
        return result
    }()
    
    private lazy var surveyButton: UIButton = {
        let result = UIButton()
        result.setTitle(NSLocalizedString("vc_settings_survey_button_title", comment: ""), for: UIControl.State.normal)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.titleLabel?.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.addTarget(self, action: #selector(openSurvey), for: UIControl.Event.touchUpInside)
        
        return result
    }()
    
    private lazy var supportButton: UIButton = {
        let result = UIButton()
        result.setTitle(NSLocalizedString("vc_settings_support_button_title", comment: ""), for: UIControl.State.normal)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.titleLabel!.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.addTarget(self, action: #selector(shareLogs), for: UIControl.Event.touchUpInside)
        
        return result
    }()
    
    private lazy var helpTranslateButton: UIButton = {
        let result = UIButton()
        result.setTitle(NSLocalizedString("vc_settings_help_us_translate_button_title", comment: ""), for: UIControl.State.normal)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.titleLabel!.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.addTarget(self, action: #selector(helpTranslate), for: UIControl.Event.touchUpInside)
        
        return result
    }()
    
    private lazy var logoImageView: UIImageView = {
        let result = UIImageView()
        result.set(.height, to: 24)
        result.contentMode = .scaleAspectFit
        
        return result
    }()
    
    private lazy var versionLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        result.font = .systemFont(ofSize: Values.verySmallFontSize)
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byCharWrapping
        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"]!
        let buildNumber = Bundle.main.infoDictionary!["CFBundleVersion"]!
        result.text = "Version \(version) (\(buildNumber))"
        
        return result
    }()
    
    // MARK: - Settings
    
    private static let buttonHeight = isIPhone5OrSmaller ? CGFloat(52) : CGFloat(75)
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("vc_settings_title", comment: ""))
        
        // Navigation bar buttons
        updateNavigationBarButtons()
        
        // Profile picture view
        let profile: Profile = Profile.fetchOrCreateCurrentUser()
        let profilePictureTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showEditProfilePictureUI))
        profilePictureView.addGestureRecognizer(profilePictureTapGestureRecognizer)
        profilePictureView
            .update(
                publicKey: profile.id,
                profile: profile,
                threadVariant: .contact
            )
        // Display name label
        displayNameLabel.text = profile.name
        
        // Display name container
        let displayNameContainer = UIView()
        displayNameContainer.accessibilityLabel = "Edit display name text field"
        displayNameContainer.isAccessibilityElement = true
        displayNameContainer.addSubview(displayNameLabel)
        displayNameLabel.pin(to: displayNameContainer)
        displayNameContainer.addSubview(displayNameTextField)
        displayNameTextField.pin(to: displayNameContainer)
        displayNameContainer.set(.height, to: 40)
        displayNameTextField.alpha = 0
        let displayNameContainerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showEditDisplayNameUI))
        displayNameContainer.addGestureRecognizer(displayNameContainerTapGestureRecognizer)
        
        // Header view
        let headerStackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameContainer ])
        headerStackView.axis = .vertical
        headerStackView.spacing = Values.smallSpacing
        headerStackView.alignment = .center
        
        // Separator
        let separator = Separator(title: NSLocalizedString("your_session_id", comment: ""))
        
        // Share button
        let shareButton = Button(style: .regular, size: .medium)
        shareButton.setTitle(NSLocalizedString("share", comment: ""), for: UIControl.State.normal)
        shareButton.addTarget(self, action: #selector(sharePublicKey), for: UIControl.Event.touchUpInside)
        
        // Button container
        let buttonContainer = UIStackView(arrangedSubviews: [ copyButton, shareButton ])
        buttonContainer.axis = .horizontal
        buttonContainer.spacing = UIDevice.current.isIPad ? Values.iPadButtonSpacing : Values.mediumSpacing
        buttonContainer.distribution = .fillEqually
        
        if (UIDevice.current.isIPad) {
            buttonContainer.layoutMargins = UIEdgeInsets(top: 0, left: Values.iPadButtonContainerMargin, bottom: 0, right: Values.iPadButtonContainerMargin)
            buttonContainer.isLayoutMarginsRelativeArrangement = true
        }
        // User session id container
        let userPublicKeyContainer = UIView(wrapping: publicKeyLabel, withInsets: .zero, shouldAdaptForIPadWithWidth: Values.iPadUserSessionIdContainerWidth)
        
        // Top stack view
        let topStackView = UIStackView(arrangedSubviews: [ headerStackView, separator, userPublicKeyContainer, buttonContainer ])
        topStackView.axis = .vertical
        topStackView.spacing = Values.largeSpacing
        topStackView.alignment = .fill
        topStackView.layoutMargins = UIEdgeInsets(top: 0, left: Values.largeSpacing, bottom: 0, right: Values.largeSpacing)
        topStackView.isLayoutMarginsRelativeArrangement = true
        
        // Setting buttons stack view
        getSettingButtons().forEach { settingButtonOrSeparator in
            settingButtonsStackView.addArrangedSubview(settingButtonOrSeparator)
        }
        
        // Oxen logo
        updateLogo()
        let logoContainer = UIView()
        logoContainer.addSubview(logoImageView)
        logoImageView.pin(.top, to: .top, of: logoContainer)
        logoContainer.pin(.bottom, to: .bottom, of: logoImageView)
        logoImageView.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor, constant: -2).isActive = true
        
        // Main stack view
        let stackView = UIStackView(arrangedSubviews: [ topStackView, settingButtonsStackView, inviteButton, faqButton, surveyButton, supportButton, helpTranslateButton, logoContainer, versionLabel ])
        stackView.axis = .vertical
        stackView.spacing = Values.largeSpacing
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: Values.mediumSpacing, left: 0, bottom: Values.mediumSpacing, right: 0)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.set(.width, to: UIScreen.main.bounds.width)
        
        // Scroll view
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
            
            let backgroundColor = isLightMode ? UIColor(hex: 0xF9F9F9) : UIColor(hex: 0x1B1B1B)
            button.setBackgroundImage(getImage(withColor: backgroundColor), for: UIControl.State.normal)
            
            let selectedColor = isLightMode ? UIColor(hex: 0xDFDFDF) : UIColor(hex: 0x0C0C0C)
            button.setBackgroundImage(getImage(withColor: selectedColor), for: UIControl.State.highlighted)
            button.addTarget(self, action: selector, for: UIControl.Event.touchUpInside)
            button.set(.height, to: SettingsVC.buttonHeight)
            
            return button
        }
        
        let pathButton = getSettingButton(withTitle: NSLocalizedString("vc_path_title", comment: ""), color: Colors.text, action: #selector(showPath))
        let pathStatusView = PathStatusView()
        pathStatusView.set(.width, to: PathStatusView.size)
        pathStatusView.set(.height, to: PathStatusView.size)
        
        pathButton.addSubview(pathStatusView)
        pathStatusView.pin(.leading, to: .trailing, of: pathButton.titleLabel!, withInset: Values.smallSpacing)
        pathStatusView.autoVCenterInSuperview()
        
        return [
            getSeparator(),
            pathButton,
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("vc_settings_privacy_button_title", comment: ""), color: Colors.text, action: #selector(showPrivacySettings)),
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("vc_settings_notifications_button_title", comment: ""), color: Colors.text, action: #selector(showNotificationSettings)),
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("MESSAGE_REQUESTS_TITLE", comment: ""), color: Colors.text, action: #selector(showMessageRequests)),
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("CHATS_TITLE", comment: ""), color: Colors.text, action: #selector(showChatSettings)),
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("vc_settings_recovery_phrase_button_title", comment: ""), color: Colors.text, action: #selector(showSeed)),
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("vc_settings_clear_all_data_button_title", comment: ""), color: Colors.destructive, action: #selector(clearAllData)),
            getSeparator()
        ]
    }
    
    // MARK: - General
    
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        
        UIView.transition(
            with: copyButton,
            duration: 0.25,
            options: .transitionCrossDissolve,
            animations: {
                self.copyButton.setTitle("copy".localized(), for: .normal)
            },
            completion: nil
        )
    }
    
    func avatarActionSheetTitle() -> String? { return "Update Profile Picture" }
    func fromViewController() -> UIViewController { return self }
    func hasClearAvatarAction() -> Bool { return false }
    func clearAvatarActionLabel() -> String { return "Clear" }
    
    // MARK: - Updating
    
    private func handleIsEditingDisplayNameChanged() {
        updateNavigationBarButtons()
        
        UIView.animate(withDuration: 0.25) {
            self.displayNameLabel.alpha = self.isEditingDisplayName ? 0 : 1
            self.displayNameTextField.alpha = self.isEditingDisplayName ? 1 : 0
        }
        
        if isEditingDisplayName {
            displayNameTextField.becomeFirstResponder()
        }
        else {
            displayNameTextField.resignFirstResponder()
        }
    }
    
    private func updateNavigationBarButtons() {
        if isEditingDisplayName {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(handleCancelDisplayNameEditingButtonTapped))
            cancelButton.tintColor = Colors.text
            cancelButton.accessibilityLabel = "Cancel button"
            cancelButton.isAccessibilityElement = true
            navigationItem.leftBarButtonItem = cancelButton
            
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(handleSaveDisplayNameButtonTapped))
            doneButton.tintColor = Colors.text
            doneButton.accessibilityLabel = "Done button"
            doneButton.isAccessibilityElement = true
            navigationItem.rightBarButtonItem = doneButton
        }
        else {
            let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
            closeButton.tintColor = Colors.text
            closeButton.accessibilityLabel = "Close button"
            closeButton.isAccessibilityElement = true
            navigationItem.leftBarButtonItem = closeButton
            
            let appModeIcon: UIImage
            if isSystemDefault {
                appModeIcon = isDarkMode ? #imageLiteral(resourceName: "ic_theme_auto").withTintColor(.white) : #imageLiteral(resourceName: "ic_theme_auto").withTintColor(.black)
            }
            else {
                appModeIcon = isDarkMode ? #imageLiteral(resourceName: "ic_dark_theme_on").withTintColor(.white) : #imageLiteral(resourceName: "ic_dark_theme_off").withTintColor(.black)
            }
            
            let appModeButton = UIButton()
            appModeButton.setImage(appModeIcon, for: UIControl.State.normal)
            appModeButton.tintColor = Colors.text
            appModeButton.addTarget(self, action: #selector(switchAppMode), for: UIControl.Event.touchUpInside)
            appModeButton.accessibilityLabel = "Switch app mode button"
            
            let qrCodeIcon = isDarkMode ? #imageLiteral(resourceName: "QRCode").withTintColor(.white) : #imageLiteral(resourceName: "QRCode").withTintColor(.black)
            let qrCodeButton = UIButton()
            qrCodeButton.setImage(qrCodeIcon, for: UIControl.State.normal)
            qrCodeButton.tintColor = Colors.text
            qrCodeButton.addTarget(self, action: #selector(showQRCode), for: UIControl.Event.touchUpInside)
            qrCodeButton.accessibilityLabel = "Show QR code button"
            
            let stackView = UIStackView(arrangedSubviews: [ appModeButton, qrCodeButton ])
            stackView.axis = .horizontal
            stackView.spacing = Values.mediumSpacing
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: stackView)
        }
    }
    
    func avatarDidChange(_ image: UIImage?, filePath: String?) {
        updateProfile(
            profilePicture: image,
            profilePictureFilePath: filePath,
            isUpdatingDisplayName: false,
            isUpdatingProfilePicture: true
        )
    }
    
    func clearAvatar() {
        updateProfile(
            profilePicture: nil,
            profilePictureFilePath: nil,
            isUpdatingDisplayName: false,
            isUpdatingProfilePicture: true
        )
    }
    
    private func updateProfile(
        profilePicture: UIImage?,
        profilePictureFilePath: String?,
        isUpdatingDisplayName: Bool,
        isUpdatingProfilePicture: Bool
    ) {
        let userDefaults = UserDefaults.standard
        let name: String? = (displayNameToBeUploaded ?? Profile.fetchOrCreateCurrentUser().name)
        let imageFilePath: String? = (profilePictureFilePath ?? ProfileManager.profileAvatarFilepath(id: getUserHexEncodedPublicKey()))
        
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self, displayNameToBeUploaded] modalActivityIndicator in
            ProfileManager.updateLocal(
                queue: DispatchQueue.global(qos: .default),
                profileName: (name ?? ""),
                image: profilePicture,
                imageFilePath: imageFilePath,
                requiredSync: true,
                success: { db, updatedProfile in
                    if displayNameToBeUploaded != nil {
                        userDefaults[.lastDisplayNameUpdate] = Date()
                    }
                    
                    if isUpdatingProfilePicture {
                        userDefaults[.lastProfilePictureUpdate] = Date()
                    }
                    
                    try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                    
                    // Wait for the database transaction to complete before updating the UI
                    db.afterNextTransactionCommit { _ in
                        DispatchQueue.main.async {
                            modalActivityIndicator.dismiss {
                                self?.profilePictureView.update(
                                    publicKey: updatedProfile.id,
                                    profile: updatedProfile,
                                    threadVariant: .contact
                                )
                                self?.displayNameLabel.text = name
                                self?.displayNameToBeUploaded = nil
                            }
                        }
                    }
                },
                failure: { error in
                    DispatchQueue.main.async {
                        modalActivityIndicator.dismiss {
                            let isMaxFileSizeExceeded = (error == .avatarUploadMaxFileSizeExceeded)
                            let title = isMaxFileSizeExceeded ? "Maximum File Size Exceeded" : "Couldn't Update Profile"
                            let message = isMaxFileSizeExceeded ? "Please select a smaller photo and try again" : "Please check your internet connection and try again"
                            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
                            self?.present(alert, animated: true, completion: nil)
                        }
                    }
                }
            )
        }
    }

    @objc override internal func handleAppModeChangedNotification(_ notification: Notification) {
        super.handleAppModeChangedNotification(notification)
        
        updateNavigationBarButtons()
        settingButtonsStackView.arrangedSubviews.forEach { settingButton in
            settingButtonsStackView.removeArrangedSubview(settingButton)
            settingButton.removeFromSuperview()
        }
        getSettingButtons().forEach { settingButtonOrSeparator in
            settingButtonsStackView.addArrangedSubview(settingButtonOrSeparator) // Re-do the setting buttons
        }
        updateLogo()
    }
    
    private func updateLogo() {
        let logoName = isLightMode ? "OxenLightMode" : "OxenDarkMode"
        logoImageView.image = UIImage(named: logoName)!
    }
    
    // MARK: - Interaction
    
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func switchAppMode() {
        let alertVC = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        let systemModeAction = UIAlertAction.init(title: NSLocalizedString("system_mode_theme", comment: ""), style: .default) { _ in
            AppModeManager.shared.setAppModeToSystemDefault()
        }
        alertVC.addAction(systemModeAction)
        
        let darkModeAction = UIAlertAction.init(title: NSLocalizedString("dark_mode_theme", comment: ""), style: .default) { _ in
            AppModeManager.shared.setCurrentAppMode(to: .dark)
        }
        alertVC.addAction(darkModeAction)
        
        let lightModeAction = UIAlertAction.init(title: NSLocalizedString("light_mode_theme", comment: ""), style: .default) { _ in
            AppModeManager.shared.setCurrentAppMode(to: .light)
        }
        alertVC.addAction(lightModeAction)
        
        let cancelAction = UIAlertAction.init(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""), style: .cancel) {_ in }
        alertVC.addAction(cancelAction)
        
        self.presentAlert(alertVC)
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
            alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        }
        let displayName = displayNameTextField.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            return showError(title: NSLocalizedString("vc_settings_display_name_missing_error", comment: ""))
        }
        guard !ProfileManager.isToLong(profileName: displayName) else {
            return showError(title: NSLocalizedString("vc_settings_display_name_too_long_error", comment: ""))
        }
        isEditingDisplayName = false
        displayNameToBeUploaded = displayName
        updateProfile(
            profilePicture: nil,
            profilePictureFilePath: nil,
            isUpdatingDisplayName: true,
            isUpdatingProfilePicture: false
        )
    }
    
    @objc private func showEditProfilePictureUI() {
        profilePictureUtilities.showChangeAvatarUI()
    }
    
    @objc private func showEditDisplayNameUI() {
        isEditingDisplayName = true
    }
    
    @objc private func copyPublicKey() {
        UIPasteboard.general.string = getUserHexEncodedPublicKey()
        copyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("copied", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func sharePublicKey() {
        let shareVC = UIActivityViewController(activityItems: [ getUserHexEncodedPublicKey() ], applicationActivities: nil)
        if UIDevice.current.isIPad {
            shareVC.excludedActivityTypes = []
            shareVC.popoverPresentationController?.permittedArrowDirections = []
            shareVC.popoverPresentationController?.sourceView = self.view
            shareVC.popoverPresentationController?.sourceRect = self.view.bounds
        }
        navigationController!.present(shareVC, animated: true, completion: nil)
    }
    
    @objc private func showPath() {
        let pathVC = PathVC()
        navigationController!.pushViewController(pathVC, animated: true)
    }
    
    @objc private func showPrivacySettings() {
        let privacySettingsVC = PrivacySettingsTableViewController()
        navigationController!.pushViewController(privacySettingsVC, animated: true)
    }
    
    @objc private func showNotificationSettings() {
        let notificationSettingsVC = NotificationSettingsViewController()
        navigationController!.pushViewController(notificationSettingsVC, animated: true)
    }
    
    @objc private func showMessageRequests() {
        let viewController: MessageRequestsViewController = MessageRequestsViewController()
        self.navigationController?.pushViewController(viewController, animated: true)
    }
    
    @objc private func showChatSettings() {
        let chatSettingsVC = ChatSettingsViewController()
        navigationController!.pushViewController(chatSettingsVC, animated: true)
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
    
    @objc private func sendInvitation() {
        let invitation = "Hey, I've been using Session to chat with complete privacy and security. Come join me! Download it at https://getsession.org/. My Session ID is \(getUserHexEncodedPublicKey()) !"
        let shareVC = UIActivityViewController(activityItems: [ invitation ], applicationActivities: nil)
        if UIDevice.current.isIPad {
            shareVC.excludedActivityTypes = []
            shareVC.popoverPresentationController?.permittedArrowDirections = []
            shareVC.popoverPresentationController?.sourceView = self.view
            shareVC.popoverPresentationController?.sourceRect = self.view.bounds
        }
        navigationController!.present(shareVC, animated: true, completion: nil)
    }
    
    @objc private func openFAQ() {
        let url = URL(string: "https://getsession.org/faq")!
        UIApplication.shared.open(url)
    }
    
    @objc private func openSurvey() {
        let url = URL(string: "https://getsession.org/survey")!
        UIApplication.shared.open(url)
    }
    
    @objc private func shareLogs() {
        let shareLogsModal = ShareLogsModal()
        shareLogsModal.modalPresentationStyle = .overFullScreen
        shareLogsModal.modalTransitionStyle = .crossDissolve
        present(shareLogsModal, animated: true, completion: nil)
    }
    
    @objc private func helpTranslate() {
        let url = URL(string: "https://crowdin.com/project/session-ios")!
        UIApplication.shared.open(url)
    }
}
