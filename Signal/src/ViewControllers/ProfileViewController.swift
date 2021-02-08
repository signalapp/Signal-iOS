//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SafariServices
import PromiseKit

@objc
public enum ProfileViewMode: UInt {
    case appSettings
    case registration

    fileprivate var isFullScreenStyle: Bool {
        switch self {
        case .appSettings:
            return false
        case .registration:
            return true
        }
    }

    fileprivate var hasBio: Bool {
        switch self {
        case .appSettings:
            return true
        case .registration:
            return false
        }
    }
}

// MARK: -

@objc
public class ProfileViewController: OWSTableViewController {
    static private let standardMargin: CGFloat = UIDevice.current.isIPhone5OrShorter ? 16 : 32

    private let avatarViewHelper = AvatarViewHelper()

    private lazy var givenNameTextField = OWSTextField()
    private lazy var familyNameTextField = OWSTextField()
    private lazy var nameFieldStrokes: [UIView] = [givenNameTextField, familyNameTextField].map {
        $0.addBottomStroke(color: Theme.cellSeparatorColor, strokeWidth: CGHairlineWidth())
    }

    private let usernameLabel = UILabel()

    private let avatarView = AvatarImageView()

    private let cameraImageView: UIImageView = {
        let viewSize = CGSize(square: 32)

        let cameraImageView = UIImageView.withTemplateImageName("camera-outline-24", tintColor: Theme.secondaryTextAndIconColor)
        cameraImageView.autoSetDimensions(to: viewSize)
        cameraImageView.contentMode = .center
        cameraImageView.backgroundColor = Theme.backgroundColor
        cameraImageView.layer.cornerRadius = viewSize.largerAxis / 2

        // Setup shadows
        let finerShadowLayer = cameraImageView.layer
        let broaderShadowLayer = CALayer()
        finerShadowLayer.addSublayer(broaderShadowLayer)

        let shadowColor = (Theme.isDarkThemeEnabled ? Theme.darkThemeWashColor : UIColor.ows_black).cgColor
        let shadowPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: viewSize)).cgPath
        [finerShadowLayer, broaderShadowLayer].forEach {
            $0.shadowColor = shadowColor
            $0.shadowPath = shadowPath
        }
        finerShadowLayer.shadowRadius = 4
        finerShadowLayer.shadowOffset = CGSize(width: 0, height: 2)
        finerShadowLayer.shadowOpacity = 0.2
        broaderShadowLayer.shadowRadius = 16
        broaderShadowLayer.shadowOffset = CGSize(width: 0, height: 4)
        broaderShadowLayer.shadowOpacity = 0.12
        return cameraImageView
    }()

    private let saveButtonBackdrop = UIView()
    private let saveButtonGradient = GradientView(colors: [])
    private var saveButton: OWSFlatButton = {
        let button = OWSFlatButton.button(
            title: NSLocalizedString(
                "PROFILE_VIEW_SAVE_BUTTON",
                comment: "Button to save the profile view in the profile view."),
            font: UIFont.ows_dynamicTypeBody.ows_semibold,
            titleColor: .ows_white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(updateProfile))

        button.accessibilityIdentifier = "save_button"
        button.enableMultilineLabel()
        button.button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 14)
        return button
    }()

    private var username: String?
    private var profileBio: String?
    private var profileBioEmoji: String?
    private var avatarData: Data?

    private var hasUnsavedChanges = false {
        didSet {
            updateNavigationItem()
            saveButton.setEnabled(hasUnsavedChanges)
        }
    }

    private let mode: ProfileViewMode

    private let completionHandler: (ProfileViewController) -> Void

    @objc
    public required init(mode: ProfileViewMode,
                         completionHandler: @escaping (ProfileViewController) -> Void) {

        self.mode = mode
        self.completionHandler = completionHandler

        super.init()

        self.shouldAvoidKeyboard = true
        self.layoutMarginsRelativeTableContent = true
    }

    // MARK: - Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.isIPad {
            return .all
        }
        return (mode == .registration ? .portrait : .allButUpsideDown)
    }

    // MARK: -

    public override func loadView() {
        super.loadView()
        view.layoutMargins = UIEdgeInsets(hMargin: Self.standardMargin, vMargin: 0)
        view.insetsLayoutMarginsFromSafeArea = false

        self.title = NSLocalizedString("PROFILE_VIEW_TITLE", comment: "Title for the profile view.")

        avatarViewHelper.delegate = self

        let profileSnapshot = profileManager.localProfileSnapshot(shouldIncludeAvatar: true)
        givenNameTextField.text = profileSnapshot.givenName
        familyNameTextField.text = profileSnapshot.familyName
        self.profileBio = profileSnapshot.bio
        self.profileBioEmoji = profileSnapshot.bioEmoji
        self.username = profileSnapshot.username
        self.avatarData = profileSnapshot.avatarData

        configureViews()
        updateNavigationItem()

        if mode == .registration {
            // mark as dirty if re-registration has content
            if let familyName = familyNameTextField.text,
               !familyName.isEmpty {
                hasUnsavedChanges = true
            } else if let givenName = givenNameTextField.text,
                      !givenName.isEmpty {
                hasUnsavedChanges = true
            } else if avatarData != nil {
                hasUnsavedChanges = true
            }
        }
        updateTableContents()
        tableView.alwaysBounceVertical = false

        if mode.isFullScreenStyle {
            saveButton.setEnabled(hasUnsavedChanges)
            view.addSubview(saveButtonGradient)
            view.addSubview(saveButtonBackdrop)
            saveButtonGradient.isUserInteractionEnabled = false

            saveButtonBackdrop.addSubview(saveButton)
            saveButtonBackdrop.preservesSuperviewLayoutMargins = true
            saveButtonBackdrop.layoutMargins = UIEdgeInsets(top: 8, leading: 0, bottom: Self.standardMargin, trailing: 0)
            saveButton.autoPinEdgesToSuperviewMargins()

            saveButtonGradient.autoPinWidthToSuperview()
            saveButtonBackdrop.autoPinWidthToSuperview()

            saveButtonGradient.autoSetDimension(.height, toSize: 30)
            saveButtonGradient.autoPinEdge(.bottom, to: .top, of: saveButtonBackdrop)

            // tableView will automatically avoid the keyboard
            saveButtonBackdrop.autoPinEdge(.bottom, to: .bottom, of: tableView)
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateNavigationItem()

        switch mode {
        case .appSettings:
            break
        case .registration:
            givenNameTextField.becomeFirstResponder()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNavigationItem()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bottomInsetHeight = saveButtonBackdrop.height + (saveButtonGradient.height / 4)
        if tableView.contentInset.bottom < bottomInsetHeight {
            tableView.contentInset.bottom = bottomInsetHeight
        }
    }

    public override func applyTheme() {
        super.applyTheme()

        [givenNameTextField, familyNameTextField].forEach { $0.textColor = Theme.primaryTextColor }

        cameraImageView.tintColor = Theme.secondaryTextAndIconColor
        cameraImageView.backgroundColor = Theme.backgroundColor

        nameFieldStrokes.forEach { $0.backgroundColor = Theme.cellSeparatorColor }

        let backgroundColor = view.backgroundColor ?? Theme.backgroundColor
        saveButtonBackdrop.backgroundColor = backgroundColor
        saveButtonGradient.colors = [(backgroundColor.withAlphaComponent(0), 0.0), (backgroundColor, 1.0)]

        updateTableContents()
    }

    private func configureViews() {
        avatarView.autoSetDimensions(to: CGSize.square(avatarSize))
        avatarView.accessibilityIdentifier = "avatar_view"
        let avatarTapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapAvatar))
        avatarView.addGestureRecognizer(avatarTapGesture)
        avatarView.isUserInteractionEnabled = true

        [givenNameTextField, familyNameTextField].forEach {
            $0.font = .ows_dynamicTypeBodyClamped
            $0.delegate = self
            $0.textAlignment = .natural
            $0.autocorrectionType = .no
            $0.spellCheckingType = .no
            $0.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

            $0.autoSetDimension(.height, toSize: 50, relation: .greaterThanOrEqual)
        }
        firstTextField.returnKeyType = .next
        secondTextField.returnKeyType = .done

        givenNameTextField.accessibilityIdentifier = "given_name_textfield"
        givenNameTextField.placeholder = NSLocalizedString(
            "PROFILE_VIEW_GIVEN_NAME_DEFAULT_TEXT",
            comment: "Default text for the given name field of the profile view.")
        familyNameTextField.accessibilityIdentifier = "family_name_textfield"
        familyNameTextField.placeholder = NSLocalizedString(
            "PROFILE_VIEW_FAMILY_NAME_DEFAULT_TEXT",
            comment: "Default text for the family name field of the profile view.")

        usernameLabel.numberOfLines = 0
        usernameLabel.font = .ows_dynamicTypeBody
        usernameLabel.textAlignment = .natural
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let mode = self.mode
        let firstTextField = self.firstTextField
        let secondTextField = self.secondTextField
        let avatarView = self.avatarView
        let cameraImageView = self.cameraImageView

        updateAvatarView()

        if mode.isFullScreenStyle {
            contents.addSection(OWSTableSection(header: { () -> UIView? in
                let label = UILabel()
                label.font = UIFont.ows_dynamicTypeTitle1.ows_semibold
                label.textAlignment = .center
                label.text = "Your Profile"
                label.numberOfLines = 0

                let view = UIView()
                view.layoutMargins = UIEdgeInsets(hMargin: 0, vMargin: Self.standardMargin)
                view.preservesSuperviewLayoutMargins = true
                view.addSubview(label)
                label.autoPinEdgesToSuperviewMargins()
                return view
            }, items: []))
        }

        contents.addSection(OWSTableSection(header: { () -> UIView? in
            let view = UIView()
            view.preservesSuperviewLayoutMargins = true
            // Setup stack views. For CJKV locales, display family name field first.
            let vStack = UIStackView(arrangedSubviews: [firstTextField, secondTextField])
            let hStack = UIStackView(arrangedSubviews: [avatarView, vStack])
            vStack.axis = .vertical
            vStack.spacing = 0
            vStack.alignment = .fill
            vStack.distribution = .equalSpacing
            hStack.axis = .horizontal
            hStack.spacing = 24
            hStack.alignment = .center
            vStack.distribution = .fill

            view.addSubview(hStack)
            view.addSubview(cameraImageView)
            cameraImageView.autoPinEdge(.bottom, to: .bottom, of: avatarView)
            cameraImageView.autoPinEdge(.trailing, to: .trailing, of: avatarView)
            hStack.autoPinEdgesToSuperviewMargins()
            return view
        }))

        if mode.hasBio {
            let profileBio = self.normalizedProfileBio
            let profileBioEmoji = self.normalizedProfileBioEmoji

            contents.addSection(
                OWSTableSection(
                    title: NSLocalizedString(
                        "PROFILE_VIEW_BIO_SECTION_HEADER",
                        comment: "Header for the 'bio' section of the profile view."),

                    items: [OWSTableItem(customCellBlock: { () -> UITableViewCell in
                        let cell = OWSTableItem.newCell()
                        cell.preservesSuperviewLayoutMargins = true
                        cell.contentView.preservesSuperviewLayoutMargins = true

                        let label = UILabel()

                        if let bioForDisplay = OWSUserProfile.bioForDisplay(bio: profileBio, bioEmoji: profileBioEmoji) {
                            label.textColor = Theme.primaryTextColor
                            label.text = bioForDisplay
                        } else {
                            label.textColor = Theme.accentBlueColor
                            label.text = NSLocalizedString(
                                "PROFILE_VIEW_ADD_BIO_TO_PROFILE",
                                comment: "Button to add a 'bio' to the user's profile in the profile view.")
                        }

                        label.font = UIFont.ows_dynamicTypeBody
                        label.numberOfLines = 0
                        label.lineBreakMode = .byWordWrapping
                        cell.contentView.addSubview(label)
                        label.autoPinEdgesToSuperviewMargins()

                        cell.accessoryType = .disclosureIndicator
                        cell.accessibilityIdentifier = "profile_bio"
                        return cell
                    }, actionBlock: { [weak self] in
                        self?.didTapBio()
                    })
                ])
            )
        }

        if shouldShowUsernameRow {
            let username = self.username
            let usernameLabel = self.usernameLabel

            contents.addSection(OWSTableSection(
                title: "Username",
                items: [OWSTableItem(customCellBlock: { () -> UITableViewCell in
                    let cell = OWSTableItem.newCell()
                    cell.preservesSuperviewLayoutMargins = true
                    cell.contentView.preservesSuperviewLayoutMargins = true

                    if let username = username {
                        usernameLabel.textColor = Theme.primaryTextColor
                        usernameLabel.text = CommonFormats.formatUsername(username)
                    } else {
                        usernameLabel.textColor = Theme.accentBlueColor
                        usernameLabel.text = NSLocalizedString(
                            "PROFILE_VIEW_CREATE_USERNAME",
                            comment: "A string indicating that the user can create a username on the profile view.")
                    }

                    cell.contentView.addSubview(usernameLabel)
                    usernameLabel.autoPinEdgesToSuperviewMargins()
                    cell.accessoryType = .disclosureIndicator
                    cell.accessibilityIdentifier = "username"
                    return cell

                }, actionBlock: { [weak self] in
                    self?.didTapUsername()
                })]
            ))
        }

        // Information Footer
        let infoGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapInfo))
        contents.sections.last?.customFooterView = { () -> UIView in
            let label = UILabel()
            label.textColor = Theme.secondaryTextAndIconColor
            label.font = .ows_dynamicTypeCaption1
            let attributedText = NSMutableAttributedString()
            attributedText.append(NSLocalizedString("PROFILE_VIEW_PROFILE_DESCRIPTION",
                                                    comment: "Description of the user profile."))
            attributedText.append(" ")
            attributedText.append(NSAttributedString(string: CommonStrings.learnMore,
                                                     attributes: [
                                                        NSAttributedString.Key.foregroundColor: Theme.accentBlueColor,
                                                        NSAttributedString.Key.underlineStyle: 0
                                                     ]))
            label.attributedText = attributedText
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.backgroundColor = tableView.backgroundColor

            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(infoGestureRecognizer)

            let footer = UIView()
            footer.preservesSuperviewLayoutMargins = true
            footer.layoutMargins = UIEdgeInsets(hMargin: 0, vMargin: 12)
            footer.addSubview(label)
            label.autoPinEdgesToSuperviewMargins()

            return footer
        }()

        self.contents = contents
    }

    // MARK: - Event Handling

    private func leaveViewCheckingForUnsavedChanges() {
        familyNameTextField.resignFirstResponder()
        givenNameTextField.resignFirstResponder()

        if !hasUnsavedChanges {
            // If user made no changes, return to conversation settings view.
            profileCompleted()
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.profileCompleted()
        })
    }

    private func updateNavigationItem() {
        if mode.isFullScreenStyle {
            navigationController?.isNavigationBarHidden = true
            navigationItem.hidesBackButton = true
            navigationItem.rightBarButtonItem = nil

        } else if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .save,
                target: self,
                action: #selector(updateProfile),
                accessibilityIdentifier: "save_button")

        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc
    func updateProfile() {

        let normalizedGivenName = self.normalizedGivenName
        let normalizedFamilyName = self.normalizedFamilyName
        let normalizedProfileBio = self.normalizedProfileBio
        let normalizedProfileBioEmoji = self.normalizedProfileBioEmoji

        if normalizedGivenName.isEmpty {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_GIVEN_NAME_REQUIRED",
                                                                      comment: "Error message shown when user tries to update profile without a given name"))
            return
        }

        if profileManager.isProfileNameTooLong(normalizedGivenName) {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_GIVEN_NAME_TOO_LONG",
                                                                      comment: "Error message shown when user tries to update profile with a given name that is too long."))
            return
        }

        if profileManager.isProfileNameTooLong(normalizedFamilyName) {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_FAMILY_NAME_TOO_LONG",
                                                                      comment: "Error message shown when user tries to update profile with a family name that is too long."))
            return
        }

        if !self.reachabilityManager.isReachable {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_NO_CONNECTION",
                                                                      comment: "Error shown when the user tries to update their profile when the app is not connected to the internet."))
            return
        }

        // Show an activity indicator to block the UI during the profile upload.
        let avatarData = self.avatarData
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modalActivityIndicator in
            firstly(on: .global()) { () -> Promise<Void> in
                OWSProfileManager.updateLocalProfilePromise(profileGivenName: normalizedGivenName,
                                                            profileFamilyName: normalizedFamilyName,
                                                            profileBio: normalizedProfileBio,
                                                            profileBioEmoji: normalizedProfileBioEmoji,
                                                            profileAvatarData: avatarData)
            }.done { _ in
                modalActivityIndicator.dismiss { [weak self] in
                    AssertIsOnMainThread()
                    self?.profileCompleted()
                }
            }.catch { error in
                owsFailDebug("Error: \(error)")
                modalActivityIndicator.dismiss { [weak self] in
                    AssertIsOnMainThread()
                    self?.profileCompleted()
                }
            }
        }
    }

    private var normalizedGivenName: String {
        (givenNameTextField.text ?? "").ows_stripped()
    }

    private var normalizedFamilyName: String {
        (familyNameTextField.text ?? "").ows_stripped()
    }

    private var normalizedProfileBio: String? {
        profileBio?.ows_stripped()
    }

    private var normalizedProfileBioEmoji: String? {
        profileBioEmoji?.ows_stripped()
    }

    private func profileCompleted() {
        AssertIsOnMainThread()
        Logger.verbose("")

        completionHandler(self)
    }

    // MARK: - Avatar

    private func setAvatarImage(_ avatarImage: UIImage?) {
        AssertIsOnMainThread()

        var avatarData: Data?
        if let avatarImage = avatarImage {
            avatarData = OWSProfileManager.avatarData(forAvatarImage: avatarImage)
        }
        hasUnsavedChanges = hasUnsavedChanges || avatarData != self.avatarData
        self.avatarData = avatarData

        updateAvatarView()
    }

    private let avatarSize: CGFloat = 80.0

    private func updateAvatarView() {
        if let avatarData = avatarData {
            avatarView.image = UIImage(data: avatarData)
        } else {
            avatarView.image = OWSContactAvatarBuilder(forLocalUserWithDiameter: UInt(avatarSize)).buildDefaultImage()
        }
    }

    private func didTapUsername() {
        let usernameVC = UsernameViewController()
        if mode == .registration {
            usernameVC.modalPresentation = true
            presentFormSheet(OWSNavigationController(rootViewController: usernameVC), animated: true)
        } else {
            navigationController?.pushViewController(usernameVC, animated: true)
        }
    }

    private func didTapBio() {
        let view = ProfileBioViewController(bio: profileBio, bioEmoji:
                                                profileBioEmoji,
                                            mode: mode,
                                            profileDelegate: self)
        navigationController?.pushViewController(view, animated: true)
    }

    private var shouldShowUsernameRow: Bool {
        switch mode {
        case .registration:
            return false
        case .appSettings:
            return RemoteConfig.usernames
        }
    }

    @objc
    private func didTapAvatar() {
        avatarViewHelper.showChangeAvatarUI()
    }

    @objc
    private func didTapInfo() {
        let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/articles/360007459591")!)
        present(vc, animated: true, completion: nil)
    }
}

// MARK: -

extension ProfileViewController: AvatarViewHelperDelegate {

    public func avatarActionSheetTitle() -> String? {
        NSLocalizedString("PROFILE_VIEW_AVATAR_ACTIONSHEET_TITLE", comment: "Action Sheet title prompting the user for a profile avatar")
    }

    public func avatarDidChange(_ image: UIImage) {
        AssertIsOnMainThread()

        setAvatarImage(image.resizedImage(toFillPixelSize: .square(CGFloat(kOWSProfileManager_MaxAvatarDiameter))))
    }

    public func fromViewController() -> UIViewController {
        self
    }

    public func hasClearAvatarAction() -> Bool {
        avatarData != nil
    }

    public func clearAvatar() {
        setAvatarImage(nil)
    }

    public func clearAvatarActionLabel() -> String {
        return NSLocalizedString("PROFILE_VIEW_CLEAR_AVATAR", comment: "Label for action that clear's the user's profile avatar")
    }
}

// MARK: -

extension ProfileViewController: UITextFieldDelegate {

    private var firstTextField: UITextField {
        NSLocale.current.isCJKV ? familyNameTextField : givenNameTextField
    }

    private var secondTextField: UITextField {
        NSLocale.current.isCJKV ? givenNameTextField : familyNameTextField
    }

    public func textField(_ textField: UITextField,
                          shouldChangeCharactersIn range: NSRange,
                          replacementString string: String) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string.withoutBidiControlCharacters,
            maxByteCount: OWSUserProfile.maxNameLengthBytes,
            maxGlyphCount: OWSUserProfile.maxNameLengthGlyphs
        )
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == firstTextField {
            secondTextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return false
    }

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        hasUnsavedChanges = true
        // TODO: Update length warning.
    }
}

// MARK: -

extension ProfileViewController: OWSNavigationView {

    public func shouldCancelNavigationBack() -> Bool {
        let result = hasUnsavedChanges
        if result {
            leaveViewCheckingForUnsavedChanges()
        }
        return result
    }
}

// MARK: -

extension ProfileViewController: ProfileBioViewControllerDelegate {

    public func profileBioViewDidComplete(bio: String?,
                                          bioEmoji: String?) {
        profileBio = bio
        profileBioEmoji = bioEmoji
        hasUnsavedChanges = true
        updateTableContents()
    }
}
