//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
class ProfileSettingsViewController: OWSTableViewController2 {

    private var hasUnsavedChanges = false {
        didSet { updateNavigationItem() }
    }

    private var avatarData: Data?
    private var givenName: String?
    private var familyName: String?
    private var username: String?
    private var bio: String?
    private var bioEmoji: String?

    private let avatarViewHelper = AvatarViewHelper()

    override func viewDidLoad() {
        super.viewDidLoad()

        owsAssertDebug(navigationController != nil)

        title = NSLocalizedString("PROFILE_VIEW_TITLE", comment: "Title for the profile view.")

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        avatarViewHelper.delegate = self

        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)
        avatarData = snapshot.avatarData
        givenName = snapshot.givenName
        familyName = snapshot.familyName
        username = snapshot.username
        bio = snapshot.bio
        bioEmoji = snapshot.bioEmoji

        updateTableContents()
    }

    private var fullName: String? {
        guard givenName?.isEmpty == false || familyName?.isEmpty == false else { return nil }
        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        nameComponents.familyName = familyName
        let formatter = PersonNameComponentsFormatter()
        return formatter.string(from: nameComponents)
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let avatarSection = OWSTableSection()
        avatarSection.hasBackground = false
        avatarSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            return self.avatarCell()
        },
            actionBlock: { [weak self] in
                self?.avatarViewHelper.showChangeAvatarUI()
            }
        ))
        contents.addSection(avatarSection)

        let mainSection = OWSTableSection()
        mainSection.footerAttributedTitle = NSAttributedString.composed(of: [
            NSLocalizedString("PROFILE_VIEW_PROFILE_DESCRIPTION",
                              comment: "Description of the user profile."),
            " ",
            CommonStrings.learnMore.styled(
                with: .link(URL(string: "https://support.signal.org/hc/articles/360007459591")!)
            )
        ]).styled(
            with: .font(.ows_dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        mainSection.add(.disclosureItem(
            icon: .settingsProfile,
            name: fullName ?? NSLocalizedString(
                "PROFILE_SETTINGS_NAME_PLACEHOLDER",
                comment: "Placeholder when the user doesn't have a 'name' defined for profile settings screen."
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "name"),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let vc = ProfileNameViewController(givenName: self.givenName, familyName: self.familyName, profileDelegate: self)
                self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        if RemoteConfig.usernames {
            mainSection.add(.disclosureItem(
                icon: .settingsMention,
                name: username ?? NSLocalizedString(
                    "PROFILE_SETTINGS_USERNAME_PLACEHOLDER",
                    comment: "Placeholder when the user doesn't have a 'username' defined for profile settings screen."
                ),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "username"),
                actionBlock: { [weak self] in
                    let vc = UsernameViewController(username: self?.username)
                    self?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
            ))
        }
        mainSection.add(.disclosureItem(
            icon: .settingsAbout,
            name: OWSUserProfile.bioForDisplay(bio: bio, bioEmoji: bioEmoji) ?? NSLocalizedString(
                "PROFILE_SETTINGS_BIO_PLACEHOLDER",
                comment: "Placeholder when the user doesn't have an 'about' for profile settings screen."
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "about"),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let vc = ProfileBioViewController(bio: self.bio, bioEmoji: self.bioEmoji, profileDelegate: self)
                self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        contents.addSection(mainSection)

        self.contents = contents
    }

    // MARK: - Event Handling

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    private func leaveViewCheckingForUnsavedChanges() {
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
        if hasUnsavedChanges {
            // If we have a unsaved changes, right item should be a "save" button.
            let saveButton = UIBarButtonItem(
                barButtonSystemItem: .save,
                target: self,
                action: #selector(updateProfile),
                accessibilityIdentifier: "save_button"
            )
            navigationItem.rightBarButtonItem = saveButton
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc
    func updateProfile() {

        let normalizedGivenName = self.normalizedGivenName
        let normalizedFamilyName = self.normalizedFamilyName
        let normalizedBio = self.normalizedBio
        let normalizedBioEmoji = self.normalizedBioEmoji

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
                                                            profileBio: normalizedBio,
                                                            profileBioEmoji: normalizedBioEmoji,
                                                            profileAvatarData: avatarData,
                                                            userProfileWriter: .localUser)
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
        (givenName ?? "").ows_stripped()
    }

    private var normalizedFamilyName: String {
        (familyName ?? "").ows_stripped()
    }

    private var normalizedBio: String? {
        bio?.ows_stripped()
    }

    private var normalizedBioEmoji: String? {
        bioEmoji?.ows_stripped()
    }

    private func profileCompleted() {
        AssertIsOnMainThread()
        Logger.verbose("")

        navigationController?.popViewController(animated: true)
    }

    // MARK: - Avatar

    private func avatarCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        cell.selectionStyle = .none

        let avatarDiameter: UInt = 88
        let avatarImageView = AvatarImageView()
        avatarImageView.contentMode = .scaleAspectFit
        if let avatarData = avatarData {
            avatarImageView.image = UIImage(data: avatarData)
        } else {
            let localAddress = tsAccountManager.localAddress!
            let avatar = Self.avatarBuilder.avatarImageForContactDefault(address: localAddress,
                                                                         diameterPoints: avatarDiameter)
            avatarImageView.image = avatar
        }
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = CGFloat(avatarDiameter) / 2
        avatarImageView.autoSetDimensions(to: CGSize(square: CGFloat(avatarDiameter)))

        cell.contentView.addSubview(avatarImageView)
        avatarImageView.autoPinHeightToSuperviewMargins()
        avatarImageView.autoHCenterInSuperview()

        let cameraImageContainer = UIView()
        cameraImageContainer.autoSetDimensions(to: CGSize.square(32))
        cameraImageContainer.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray15 : UIColor(rgbHex: 0xf8f9f9)
        cameraImageContainer.layer.cornerRadius = 16

        cameraImageContainer.layer.shadowColor = UIColor.black.cgColor
        cameraImageContainer.layer.shadowOpacity = 0.2
        cameraImageContainer.layer.shadowRadius = 4
        cameraImageContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        cameraImageContainer.layer.shadowPath = UIBezierPath(
            ovalIn: CGRect(origin: .zero, size: .square(32))
        ).cgPath

        cell.contentView.addSubview(cameraImageContainer)
        cameraImageContainer.autoPinTrailing(toEdgeOf: avatarImageView)
        cameraImageContainer.autoPinEdge(.bottom, to: .bottom, of: avatarImageView)

        let secondaryShadowView = UIView()
        secondaryShadowView.layer.shadowColor = UIColor.black.cgColor
        secondaryShadowView.layer.shadowOpacity = 0.12
        secondaryShadowView.layer.shadowRadius = 16
        secondaryShadowView.layer.shadowOffset = CGSize(width: 0, height: 4)
        secondaryShadowView.layer.shadowPath = UIBezierPath(
            ovalIn: CGRect(origin: .zero, size: .square(32))
        ).cgPath

        cameraImageContainer.addSubview(secondaryShadowView)
        secondaryShadowView.autoPinEdgesToSuperviewEdges()

        let cameraImageView = UIImageView.withTemplateImageName("camera-outline-32", tintColor: Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_black)
        cameraImageView.autoSetDimensions(to: CGSize.square(20))
        cameraImageView.contentMode = .scaleAspectFit

        cameraImageContainer.addSubview(cameraImageView)
        cameraImageView.autoCenterInSuperview()

        return cell
    }

    private func setAvatarImage(_ avatarImage: UIImage?) {
        AssertIsOnMainThread()

        var avatarData: Data?
        if let avatarImage = avatarImage {
            avatarData = OWSProfileManager.avatarData(forAvatarImage: avatarImage)
        }
        hasUnsavedChanges = hasUnsavedChanges || avatarData != self.avatarData
        self.avatarData = avatarData

        updateTableContents()
    }
}

extension ProfileSettingsViewController: AvatarViewHelperDelegate {
    public func avatarActionSheetTitle() -> String? {
        NSLocalizedString("PROFILE_VIEW_AVATAR_ACTIONSHEET_TITLE",
                          comment: "Action Sheet title prompting the user for a profile avatar")
    }

    public func avatarDidChange(_ image: UIImage) {
        AssertIsOnMainThread()

        setAvatarImage(image.resizedImage(toFillPixelSize: .square(CGFloat(kOWSProfileManager_MaxAvatarDiameterPixels))))
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
        return NSLocalizedString("PROFILE_VIEW_CLEAR_AVATAR",
                                 comment: "Label for action that clear's the user's profile avatar")
    }
}

extension ProfileSettingsViewController: OWSNavigationView {

    @available(iOS 13, *)
    override public var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set { /* noop superclass requirement */ }
    }

    public func shouldCancelNavigationBack() -> Bool {
        let result = hasUnsavedChanges
        if result {
            leaveViewCheckingForUnsavedChanges()
        }
        return result
    }
}

extension ProfileSettingsViewController: ProfileBioViewControllerDelegate {

    public func profileBioViewDidComplete(bio: String?, bioEmoji: String?) {
        hasUnsavedChanges = hasUnsavedChanges || bio != self.bio || bioEmoji != self.bioEmoji

        self.bio = bio
        self.bioEmoji = bioEmoji

        updateTableContents()
    }
}

extension ProfileSettingsViewController: ProfileNameViewControllerDelegate {
    func profileNameViewDidComplete(givenName: String?, familyName: String?) {
        hasUnsavedChanges = hasUnsavedChanges || givenName != self.givenName || familyName != self.familyName

        self.givenName = givenName
        self.familyName = familyName

        updateTableContents()
    }
}
