//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class ProfileSettingsViewController: OWSTableViewController2 {

    private let context: ViewControllerContext = .shared

    private var hasUnsavedChanges = false {
        didSet { updateNavigationItem() }
    }

    private var localAci: ServiceId?

    private var avatarData: Data?
    private var givenName: String?
    private var familyName: String?
    private var username: String?
    private var bio: String?
    private var bioEmoji: String?
    private var allBadges: [OWSUserProfileBadgeInfo] = []
    private var displayBadgesOnProfile: Bool = false

    private var shouldShowUsernameLinkTooltip: Bool = false
    private var currentUsernameLinkTooltip: UsernameLinkTooltipView?

    weak private var usernameSelectionDelegate: UsernameSelectionDelegate?

    init(usernameSelectionDelegate: UsernameSelectionDelegate? = nil) {
        self.usernameSelectionDelegate = usernameSelectionDelegate

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        owsAssertDebug(navigationController != nil)

        title = OWSLocalizedString("PROFILE_VIEW_TITLE", comment: "Title for the profile view.")

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)
        avatarData = snapshot.avatarData
        givenName = snapshot.givenName
        familyName = snapshot.familyName
        bio = snapshot.bio
        bioEmoji = snapshot.bioEmoji
        allBadges = snapshot.profileBadgeInfo ?? []
        displayBadgesOnProfile = subscriptionManager.displayBadgesOnProfile

        databaseStorage.read { tx -> Void in
            guard let localAci = tsAccountManager.localIdentifiers(transaction: tx)?.aci else {
                owsFailBeta("Should never get to profile settings without an ACI!")
                return
            }

            self.localAci = localAci

            username = context.usernameLookupManager
                .fetchUsername(forAci: localAci, transaction: tx.asV2Read)
            shouldShowUsernameLinkTooltip = context.usernameEducationManager
                .shouldShowUsernameLinkTooltip(tx: tx.asV2Read)
        }

        updateTableContents()
    }

    override var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .blur
    }

    override var navbarBackgroundColorOverride: UIColor? {
        return tableBackgroundColor
    }

    private var fullName: String? {
        guard givenName?.isEmpty == false || familyName?.isEmpty == false else { return nil }
        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        nameComponents.familyName = familyName
        return OWSFormat.formatNameComponents(nameComponents)
    }

    func updateTableContents() {
        hideUsernameLinkTooltip(permanently: false)

        let contents = OWSTableContents()

        let avatarSection = OWSTableSection(items: [
            OWSTableItem(customCellBlock: { [weak self] in
                self?.avatarCell() ?? UITableViewCell()
            }, actionBlock: nil),
            OWSTableItem(customCellBlock: { [weak self] in
                self?.createChangeAvatarCell() ?? UITableViewCell()
            }, actionBlock: nil)
        ])
        avatarSection.hasBackground = false
        contents.add(avatarSection)

        let mainSection = OWSTableSection()
        mainSection.footerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString("PROFILE_VIEW_PROFILE_DESCRIPTION",
                              comment: "Description of the user profile."),
            " ",
            CommonStrings.learnMore.styled(
                with: .link(URL(string: "https://support.signal.org/hc/articles/360007459591")!)
            )
        ]).styled(
            with: .font(.dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        mainSection.add(.disclosureItem(
            icon: .profileName,
            name: fullName ?? OWSLocalizedString(
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

        if FeatureFlags.usernames, let localAci {
            if let username {
                // No action block required, as the cell will handle taps itself
                // by presenting a context menu.
                mainSection.add(OWSTableItem(
                    customCellBlock: { [weak self] in
                        guard let self else { return UITableViewCell() }

                        return self.buildUsernameContextMenuCell(
                            username: username,
                            localAci: localAci
                        )
                    }
                ))

                mainSection.add(OWSTableItem(
                    customCellBlock: { [weak self] in
                        guard let self else { return UITableViewCell() }

                        return self.buildUsernameLinkCell()
                    },
                    willDisplayBlock: { [weak self] cell in
                        guard let self else { return }

                        self.willDisplayUsernameLinkCell(cell: cell)
                    },
                    actionBlock: { [weak self] in
                        guard let self else { return }

                        self.selectedUsernameLinkCell(username: username)
                    }
                ))
            } else {
                mainSection.add(OWSTableItem(
                    customCellBlock: { [weak self] in
                        guard let self else { return UITableViewCell() }

                        return self.buildUsernamePlaceholderCell()
                    },
                    actionBlock: { [weak self] in
                        guard let self else { return }

                        self.presentUsernameSelection(localAci: localAci)
                    }
                ))
            }
        }

        mainSection.add(.disclosureItem(
            icon: .profileAbout,
            name: OWSUserProfile.bioForDisplay(bio: bio, bioEmoji: bioEmoji) ?? OWSLocalizedString(
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
        if RemoteConfig.donorBadgeDisplay, !allBadges.isEmpty {
            mainSection.add(.disclosureItem(
                icon: .profileBadges,
                name: OWSLocalizedString(
                    "BADGE_CONFIGURATION_TITLE",
                    comment: "The title for the badge configuration page"
                ),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "badges"),
                actionBlock: { [weak self] in
                    guard let self = self else { return }

                    let avatarImage = self.databaseStorage.read { self.avatarImage(transaction: $0) }

                    let vc = BadgeConfigurationViewController(
                        availableBadges: self.allBadges,
                        shouldDisplayOnProfile: self.displayBadgesOnProfile,
                        avatarImage: avatarImage,
                        delegate: self)
                    self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
            ))
        }
        contents.add(mainSection)

        self.contents = contents
    }

    @objc
    func presentAvatarSettingsView() {
        let currentAvatarImage: UIImage? = {
            guard let avatarData = avatarData else { return nil }
            return UIImage(data: avatarData)
        }()

        let vc = AvatarSettingsViewController(
            context: .profile,
            currentAvatarImage: currentAvatarImage
        ) { [weak self] newAvatarImage in
            self?.setAvatarImage(newAvatarImage)
        }
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    // MARK: - Username

    // MARK: Username cell

    private func buildUsernamePlaceholderCell() -> UITableViewCell {
        return OWSTableItem.buildCell(
            icon: .profileUsername,
            itemName: OWSLocalizedString(
                "PROFILE_SETTINGS_USERNAME_PLACEHOLDER",
                comment: "A placeholder value shown in the profile settings screen on a tappable item leading to a username selection flow, for when the user doesn't have a username."
            ),
            accessoryType: .disclosureIndicator
        )
    }

    private func buildUsernameContextMenuCell(
        username: String,
        localAci: ServiceId
    ) -> UITableViewCell {
        let editUsernameAction = ContextMenuAction(
            title: OWSLocalizedString(
                "PROFILE_SETTINGS_USERNAME_EDIT_USERNAME_ACTION",
                comment: "Title for a menu action allowing users to edit their existing username."
            ),
            image: Theme.iconImage(.contextMenuEdit),
            handler: { [weak self] _ in
                guard let self else { return }

                self.presentUsernameSelection(localAci: localAci)
            }
        )

        let deleteUsernameAction = ContextMenuAction(
            title: CommonStrings.deleteButton,
            image: Theme.iconImage(.contextMenuDelete),
            attributes: .destructive,
            handler: { [weak self] _ in
                guard let self else { return }

                self.offerToDeleteUsername(localAci: localAci)
            }
        )

        let contextMenuButton = ContextMenuButton(
            contextMenu: ContextMenu([
                editUsernameAction,
                deleteUsernameAction
            ]),
            preferredContextMenuPosition: ContextMenuButton.ContextMenuPosition(
                verticalPinnedEdge: .bottom,
                horizontalPinnedEdge: CurrentAppContext().isRTL ? .right : .left,
                alignmentOffset: CGPoint(
                    x: Self.cellHInnerMargin,
                    y: Self.cellVInnerMargin
                )
            )
        )

        contextMenuButton.showsContextMenuAsPrimaryAction = true

        let contextMenuPresentingCell = ContextMenuPresentingTableViewCell(
            contextMenuButton: contextMenuButton
        )

        return OWSTableItem.buildCell(
            baseCell: contextMenuPresentingCell,
            contentWrapperView: contextMenuButton,
            icon: .profileUsername,
            itemName: username,
            accessoryType: .disclosureIndicator
        )
    }

    private func presentUsernameSelection(localAci: ServiceId) {
        let usernameSelectionCoordinator = UsernameSelectionCoordinator(
            localAci: localAci,
            currentUsername: username,
            usernameSelectionDelegate: self,
            context: .init(
                usernameEducationManager: context.usernameEducationManager,
                networkManager: networkManager,
                databaseStorage: databaseStorage,
                usernameLookupManager: context.usernameLookupManager,
                schedulers: context.schedulers,
                storageServiceManager: storageServiceManager
            )
        )

        usernameSelectionCoordinator.present(fromViewController: self)
    }

    private func offerToDeleteUsername(localAci: ServiceId) {
        OWSActionSheets.showConfirmationAlert(
            message: OWSLocalizedString(
                "USERNAME_SELECTION_DELETION_CONFIRMATION_ALERT_TITLE",
                comment: "A message asking the user if they are sure they want to remove their username."
            ),
            proceedTitle: OWSLocalizedString(
                "USERNAME_SELECTION_DELETE_USERNAME_ACTION_TITLE",
                comment: "The title of an action sheet button that will delete a user's username."
            ),
            proceedStyle: .destructive
        ) { [weak self] _ in
            guard let self else { return }

            self.deleteUsernameBehindModalActivityIndicator(localAci: localAci)
        }
    }

    private func deleteUsernameBehindModalActivityIndicator(localAci: ServiceId) {
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false
        ) { modal in
            firstly {
                Usernames.API(
                    networkManager: self.networkManager,
                    schedulers: self.context.schedulers
                ).attemptToDeleteCurrentUsername()
            }.done(on: DispatchQueue.main) { [weak self] in
                defer { modal.dismiss() }

                guard let self else { return }

                self.databaseStorage.write { transaction in
                    self.context.usernameLookupManager.saveUsername(
                        nil,
                        forAci: localAci,
                        transaction: transaction.asV2Write
                    )
                }

                self.usernameDidChange(to: nil)
            }.catch(on: DispatchQueue.main) { error in
                modal.dismiss {
                    OWSActionSheets.showErrorAlert(
                        message: CommonStrings.somethingWentWrongTryAgainLaterError
                    )
                }
            }
        }
    }

    // MARK: Username Link cell

    private func buildUsernameLinkCell() -> UITableViewCell {
        return OWSTableItem.buildCell(
            icon: .qrCode,
            itemName: OWSLocalizedString(
                "PROFILE_SETTINGS_USERNAME_LINK_CELL_TITLE",
                comment: "Title for a table cell that lets the user manage their username link and QR code."
            ),
            accessoryType: .disclosureIndicator
        )
    }

    private func willDisplayUsernameLinkCell(cell: UITableViewCell) {
        hideUsernameLinkTooltip(permanently: false)

        if shouldShowUsernameLinkTooltip {
            currentUsernameLinkTooltip = UsernameLinkTooltipView(
                fromView: view,
                referenceView: cell,
                hInsetFromReferenceView: cellPillFrame(view: cell).x + 16,
                onDismiss: { [weak self] in
                    self?.hideUsernameLinkTooltip(permanently: true)
                }
            )
        }
    }

    private func selectedUsernameLinkCell(username: String) {
        presentFormSheet(
            OWSNavigationController(
                rootViewController: UsernameLinkQRCodeContentController(
                    db: DependenciesBridge.shared.db,
                    kvStoreFactory: DependenciesBridge.shared.keyValueStoreFactory,
                    usernameLink: Usernames.UsernameLink(username: username),
                    scanDelegate: self
                )
            ),
            animated: true
        ) {
            self.hideUsernameLinkTooltip(permanently: true)
        }
    }

    private func hideUsernameLinkTooltip(permanently: Bool) {
        if let currentUsernameLinkTooltip {
            currentUsernameLinkTooltip.removeFromSuperview()
            self.currentUsernameLinkTooltip = nil
        }

        if permanently {
            shouldShowUsernameLinkTooltip = false

            databaseStorage.write { tx in
                context.usernameEducationManager
                    .setShouldShowUsernameLinkTooltip(false, tx: tx.asV2Write)
            }
        }
    }

    // MARK: - Event Handling

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
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
    private func updateProfile() {

        let normalizedGivenName = self.normalizedGivenName
        let normalizedFamilyName = self.normalizedFamilyName
        let normalizedBio = self.normalizedBio
        let normalizedBioEmoji = self.normalizedBioEmoji
        let visibleBadgeIds = displayBadgesOnProfile ? self.allBadges.map { $0.badgeId } : []
        let displayBadgesOnProfile = displayBadgesOnProfile

        if !self.reachabilityManager.isReachable {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("PROFILE_VIEW_NO_CONNECTION",
                                                                      comment: "Error shown when the user tries to update their profile when the app is not connected to the internet."))
            return
        }

        // Show an activity indicator to block the UI during the profile upload.
        let avatarData = self.avatarData
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modalActivityIndicator in
            firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
                OWSProfileManager.updateLocalProfilePromise(
                    profileGivenName: normalizedGivenName,
                    profileFamilyName: normalizedFamilyName,
                    profileBio: normalizedBio,
                    profileBioEmoji: normalizedBioEmoji,
                    profileAvatarData: avatarData,
                    visibleBadgeIds: visibleBadgeIds,
                    userProfileWriter: .localUser
                )
            }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
                Self.databaseStorage.writePromise { transaction in
                    Self.subscriptionManager.setDisplayBadgesOnProfile(
                        displayBadgesOnProfile,
                        updateStorageService: true,
                        transaction: transaction
                    )
                }.asVoid()
            }.done(on: DispatchQueue.main) { _ in
                modalActivityIndicator.dismiss { [weak self] in
                    AssertIsOnMainThread()
                    self?.profileCompleted()
                }
            }.catch(on: DispatchQueue.main) { error in
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

    private let avatarSizeClass: ConversationAvatarView.Configuration.SizeClass = .eightyEight

    private func avatarImage(transaction: SDSAnyReadTransaction) -> UIImage? {
        if let avatarData = avatarData {
            return UIImage(data: avatarData)
        } else {
            return avatarBuilder.defaultAvatarImageForLocalUser(
                diameterPoints: avatarSizeClass.diameter,
                transaction: transaction)
        }
    }

    private func avatarCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        cell.selectionStyle = .none

        let sizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight
        let badgedAvatarView = ConversationAvatarView(sizeClass: sizeClass, localUserDisplayMode: .asUser)
        databaseStorage.read { readTx in
            let primaryBadge = allBadges.first
            let badgeAssets = primaryBadge?.badge?.assets
            let badgeImage = badgeAssets.flatMap { sizeClass.fetchImageFromBadgeAssets($0) }

            badgedAvatarView.update(readTx) { config in
                config.dataSource = .asset(
                    avatar: self.avatarImage(transaction: readTx),
                    badge: self.displayBadgesOnProfile ? badgeImage : nil
                )
            }
        }

        cell.contentView.addSubview(badgedAvatarView)
        badgedAvatarView.autoPinHeightToSuperviewMargins()
        badgedAvatarView.autoHCenterInSuperview()
        return cell
    }

    private func createChangeAvatarCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none

        let changeButton = UIButton(type: .custom)

        changeButton.setTitle(OWSLocalizedString("CHANGE_AVATAR_BUTTON_LABEL", comment: "Button label to allow user to change avatar"), for: .normal)
        changeButton.titleLabel?.font = .dynamicTypeBody2.semibold()
        changeButton.contentEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 6)
        changeButton.layer.cornerRadius = 16

        changeButton.setTitleColor(Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray95, for: .normal)
        changeButton.backgroundColor = self.cellBackgroundColor

        cell.contentView.addSubview(changeButton)
        changeButton.autoPinHeightToSuperviewMargins()
        changeButton.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
        changeButton.autoCenterInSuperview()
        changeButton.setContentHuggingHigh()

        changeButton.addTarget(self, action: #selector(presentAvatarSettingsView), for: .touchUpInside)
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

extension ProfileSettingsViewController {

    override public var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set { /* noop superclass requirement */ }
    }

    public var shouldCancelNavigationBack: Bool {
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

extension ProfileSettingsViewController: BadgeConfigurationDelegate {
    func badgeConfiguration(_ vc: BadgeConfigurationViewController, didCompleteWithBadgeSetting setting: BadgeConfiguration) {
        switch setting {
        case .doNotDisplayPublicly:
            if displayBadgesOnProfile {
                Logger.info("Configured to disable public badge visibility")
                hasUnsavedChanges = true
                displayBadgesOnProfile = false
                updateTableContents()
            }
        case .display(featuredBadge: let newFeaturedBadge):
            guard allBadges.contains(where: { $0.badgeId == newFeaturedBadge.badgeId }) else {
                owsFailDebug("Invalid badge")
                return
            }

            if !displayBadgesOnProfile || newFeaturedBadge.badgeId != allBadges.first?.badgeId {
                Logger.info("Configured to show badges publicly featuring: \(newFeaturedBadge.badgeId)")
                hasUnsavedChanges = true
                displayBadgesOnProfile = true

                let nonPrimaryBadges = allBadges.filter { $0.badgeId != newFeaturedBadge.badgeId }
                allBadges = [newFeaturedBadge] + nonPrimaryBadges
                updateTableContents()
            }
        }

        vc.dismiss(animated: true)
    }

    func badgeConfirmationDidCancel(_ vc: BadgeConfigurationViewController) {
        vc.dismiss(animated: true)
    }
}

extension ProfileSettingsViewController: UsernameSelectionDelegate {
    /// Update ourselves, and also tell our delegate.
    func usernameDidChange(to newValue: String?) {
        username = newValue
        updateTableContents()

        usernameSelectionDelegate?.usernameDidChange(to: newValue)
    }
}

extension ProfileSettingsViewController: UsernameLinkScanDelegate {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink) {
        guard let presentingViewController else {
            return
        }

        presentingViewController.dismiss(animated: true) {
            UsernameLinkOpener(link: usernameLink)
                .open(fromViewController: presentingViewController)
        }
    }
}
