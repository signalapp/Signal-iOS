//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalMessaging
import SignalServiceKit
import SignalUI

class ProfileSettingsViewController: OWSTableViewController2 {

    private let context: ViewControllerContext = .shared

    private var hasUnsavedChanges: Bool { profileValues.hasUnsavedChanges }

    private struct ChangeableValue<T: Equatable> {
        var oldValue: T
        var changedValue: OptionalChange<T>

        var currentValue: T { changedValue.orExistingValue(oldValue) }

        var hasUnsavedChanges: Bool { currentValue != oldValue }
    }

    private struct ProfileValues {
        var givenName: ChangeableValue<String?>
        var familyName: ChangeableValue<String?>
        var bio: ChangeableValue<String?>
        var bioEmoji: ChangeableValue<String?>
        var avatarData: ChangeableValue<Data?>
        var visibleBadgeIds: ChangeableValue<[String]>

        var hasUnsavedChanges: Bool {
            givenName.hasUnsavedChanges
            || familyName.hasUnsavedChanges
            || bio.hasUnsavedChanges
            || bioEmoji.hasUnsavedChanges
            || avatarData.hasUnsavedChanges
            || visibleBadgeIds.hasUnsavedChanges
        }
    }

    private var profileValues: ProfileValues!
    private var localUsernameState: Usernames.LocalUsernameState?
    private var allBadges: [OWSUserProfileBadgeInfo] = []
    private var displayBadgesOnProfile: Bool = false

    private var shouldShowUsernameLinkTooltip: Bool = false
    private var currentUsernameLinkTooltip: UsernameLinkTooltipView?

    weak private var usernameChangeDelegate: UsernameChangeDelegate?
    weak private var usernameLinkScanDelegate: UsernameLinkScanDelegate?

    init(
        usernameChangeDelegate: UsernameChangeDelegate,
        usernameLinkScanDelegate: UsernameLinkScanDelegate
    ) {
        self.usernameChangeDelegate = usernameChangeDelegate
        self.usernameLinkScanDelegate = usernameLinkScanDelegate

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        owsAssertDebug(navigationController != nil)

        title = OWSLocalizedString("PROFILE_VIEW_TITLE", comment: "Title for the profile view.")

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)
        allBadges = snapshot.profileBadgeInfo ?? []
        displayBadgesOnProfile = subscriptionManager.displayBadgesOnProfile
        // TODO: Use `visibleBadges` when `localProfileSnapshot` is removed.
        let visibleBadgeIds = allBadges.filter { $0.isVisible ?? true }.map { $0.badgeId }
        profileValues = ProfileValues(
            givenName: .init(oldValue: snapshot.givenName, changedValue: .noChange),
            familyName: .init(oldValue: snapshot.familyName, changedValue: .noChange),
            bio: .init(oldValue: snapshot.bio, changedValue: .noChange),
            bioEmoji: .init(oldValue: snapshot.bioEmoji, changedValue: .noChange),
            avatarData: .init(oldValue: snapshot.avatarData, changedValue: .noChange),
            visibleBadgeIds: .init(oldValue: visibleBadgeIds, changedValue: .noChange)
        )

        databaseStorage.read { tx -> Void in
            localUsernameState = context.localUsernameManager
                .usernameState(tx: tx.asV2Read)
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
        let givenName = profileValues.givenName.currentValue
        let familyName = profileValues.familyName.currentValue
        guard givenName != nil || familyName != nil else {
            return nil
        }
        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        nameComponents.familyName = familyName
        return OWSFormat.formatNameComponents(nameComponents)
    }

    func updateTableContents() {
        hideUsernameLinkTooltip(permanently: false, animated: false)

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
                let vc = ProfileNameViewController(
                    givenName: self.profileValues.givenName.currentValue,
                    familyName: self.profileValues.familyName.currentValue,
                    profileDelegate: self
                )
                self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))

        if FeatureFlags.usernames, let localUsernameState {
            switch localUsernameState {
            case .unset:
                mainSection.add(usernameUnsetTableItem())
            case let .available(username, usernameLink):
                mainSection.add(usernameAvailableTableItem(username: username))
                mainSection.add(usernameLinkAvailableTableItem(
                    username: username,
                    usernameLink: usernameLink
                ))
            case let .linkCorrupted(username):
                mainSection.add(usernameAvailableTableItem(username: username))
                mainSection.add(usernameLinkCorruptedTableItem())
            case .usernameAndLinkCorrupted:
                mainSection.add(usernameCorruptedTableItem())
            }
        }

        mainSection.add(.disclosureItem(
            icon: .profileAbout,
            name: OWSUserProfile.bioForDisplay(
                bio: profileValues.bio.currentValue,
                bioEmoji: profileValues.bioEmoji.currentValue
            ) ?? OWSLocalizedString(
                "PROFILE_SETTINGS_BIO_PLACEHOLDER",
                comment: "Placeholder when the user doesn't have an 'about' for profile settings screen."
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "about"),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let vc = ProfileBioViewController(
                    bio: self.profileValues.bio.currentValue,
                    bioEmoji: self.profileValues.bioEmoji.currentValue,
                    profileDelegate: self
                )
                self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        if !allBadges.isEmpty {
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
            guard let avatarData = profileValues.avatarData.currentValue else { return nil }
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

    /// A table item for if there is no username set.
    private func usernameUnsetTableItem() -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: {
                return OWSTableItem.buildCell(
                    icon: .profileUsername,
                    itemName: OWSLocalizedString(
                        "PROFILE_SETTINGS_USERNAME_PLACEHOLDER",
                        comment: "A placeholder value shown in the profile settings screen on a tappable item leading to a username selection flow, for when the user doesn't have a username."
                    ),
                    accessoryType: .disclosureIndicator
                )
            },
            actionBlock: { [weak self] in
                guard let self else { return }
                self.presentUsernameSelection(currentUsername: nil)
            }
        )
    }

    /// A table item for an available username.
    private func usernameAvailableTableItem(username: String) -> OWSTableItem {
        // No action block required, as the cell will handle taps itself
        // by presenting a context menu.
        return OWSTableItem(
            customCellBlock: { [weak self] in
                let editUsernameAction = ContextMenuAction(
                    title: OWSLocalizedString(
                        "PROFILE_SETTINGS_USERNAME_EDIT_USERNAME_ACTION",
                        comment: "Title for a menu action allowing users to edit their existing username."
                    ),
                    image: Theme.iconImage(.contextMenuEdit),
                    handler: { [weak self] _ in
                        self?.presentUsernameSelection(currentUsername: username)
                    }
                )

                let deleteUsernameAction = ContextMenuAction(
                    title: CommonStrings.deleteButton,
                    image: Theme.iconImage(.contextMenuDelete),
                    attributes: .destructive,
                    handler: { [weak self] _ in
                        self?.offerToDeleteUsername(currentUsername: username)
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
        )
    }

    /// A table item for an available username and username link.
    private func usernameLinkAvailableTableItem(
        username: String,
        usernameLink: Usernames.UsernameLink
    ) -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: {
                return OWSTableItem.buildCell(
                    icon: .qrCodeLight,
                    itemName: OWSLocalizedString(
                        "PROFILE_SETTINGS_USERNAME_LINK_CELL_TITLE",
                        comment: "Title for a table cell that lets the user manage their username link and QR code."
                    ),
                    accessoryType: .disclosureIndicator
                )
            },
            willDisplayBlock: { [weak self] cell in
                guard let self else { return }

                if self.shouldShowUsernameLinkTooltip {
                    self.currentUsernameLinkTooltip = UsernameLinkTooltipView(
                        fromView: self.view,
                        referenceView: cell,
                        hInsetFromReferenceView: self.cellPillFrame(view: cell).x + 16,
                        onDismiss: { [weak self] in
                            self?.hideUsernameLinkTooltip(
                                permanently: true,
                                animated: true
                            )
                        }
                    )
                } else {
                    self.hideUsernameLinkTooltip(
                        permanently: false,
                        animated: true
                    )
                }
            },
            actionBlock: { [weak self] in
                self?.presentUsernameLink(
                    username: username,
                    usernameLink: usernameLink
                )
            }
        )
    }

    /// A table item for if the username is corrupted.
    private func usernameCorruptedTableItem() -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: { [weak self] in
                return OWSTableItem.buildCell(
                    icon: .profileUsername,
                    itemName: OWSLocalizedString(
                        "PROFILE_SETTINGS_USERNAME_PLACEHOLDER",
                        comment: "A placeholder value shown in the profile settings screen on a tappable item leading to a username selection flow, for when the user doesn't have a username."
                    ),
                    accessoryType: .disclosureIndicator,
                    accessoryContentView: self?.buildUsernameErrorIconView()
                )
            },
            actionBlock: { [weak self] in
                self?.presentUsernameCorruptedResolution()
            }
        )
    }

    private func usernameLinkCorruptedTableItem() -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: { [weak self] in
                return OWSTableItem.buildCell(
                    icon: .qrCodeLight,
                    itemName: OWSLocalizedString(
                        "PROFILE_SETTINGS_USERNAME_LINK_CELL_TITLE",
                        comment: "Title for a table cell that lets the user manage their username link and QR code."
                    ),
                    accessoryType: .disclosureIndicator,
                    accessoryContentView: self?.buildUsernameErrorIconView()
                )
            },
            actionBlock: { [weak self] in
                self?.presentUsernameLinkCorruptedResolution()
            }
        )
    }

    private func buildUsernameErrorIconView() -> UIView {
        let imageView = UIImageView.withTemplateImageName(
            "error-circle",
            tintColor: .ows_accentRed
        )

        imageView.autoPinToSquareAspectRatio()

        return imageView
    }

    // MARK: Username actions

    public func presentUsernameCorruptedResolution() {
        guard let localUsernameState else {
            return
        }

        switch localUsernameState {
        case .usernameAndLinkCorrupted:
            break
        case .unset, .available, .linkCorrupted:
            owsFailDebug("Attempted to present username corrupted resolution, but username is not corrupted!")
            return
        }

        let actionSheet = ActionSheetController(message: OWSLocalizedString(
            "PROFILE_SETTINGS_USERNAME_CORRUPTED_RESOLUTION_CONFIRMATION_ALERT_MESSAGE",
            comment: "A message explaining that something is wrong with the username, on a sheet allowing the user to resolve the issue."
        ))

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "PROFILE_SETTINGS_USERNAME_CORRUPTED_RESOLUTION_CREATE_NEW_USERNAME_ACTION_TITLE",
                comment: "Title for an action sheet button allowing users to create a new username when their current one is corrupted."
            ),
            handler: { [weak self] _ in
                self?.presentUsernameSelection(currentUsername: nil)
            }
        ))

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "PROFILE_SETTINGS_USERNAME_CORRUPTED_RESOLUTION_DELETE_USERNAME_ACTION_TITLE",
                comment: "Title for an action sheet button allowing users to delete their corrupted username."
            ),
            style: .destructive,
            handler: { [weak self] _ in
                self?.deleteUsernameBehindModalActivityIndicator()
            }
        ))

        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    public func presentUsernameLinkCorruptedResolution() {
        guard let localUsernameState else {
            return
        }

        switch localUsernameState {
        case let .linkCorrupted(username):
            presentUsernameLink(username: username, usernameLink: nil)
        case .unset, .available, .usernameAndLinkCorrupted:
            owsFailDebug("Attempted to present username link corrupted resolution, but username link is not corrupted!")
        }
    }

    private func presentUsernameSelection(currentUsername: String?) {
        let usernameSelectionCoordinator = UsernameSelectionCoordinator(
            currentUsername: currentUsername,
            usernameChangeDelegate: self,
            context: .init(
                databaseStorage: databaseStorage,
                networkManager: networkManager,
                schedulers: context.schedulers,
                storageServiceManager: storageServiceManager,
                usernameEducationManager: context.usernameEducationManager,
                localUsernameManager: context.localUsernameManager
            )
        )

        usernameSelectionCoordinator.present(fromViewController: self)
    }

    private func offerToDeleteUsername(currentUsername: String) {
        OWSActionSheets.showConfirmationAlert(
            message: String(
                format: OWSLocalizedString(
                    "PROFILE_SETTINGS_USERNAME_DELETION_CONFIRMATION_ALERT_MESSAGE_FORMAT",
                    comment: "A message asking the user if they are sure they want to remove their username and explaining what will happen. Embeds {{ the user's current username }}."
                ),
                currentUsername
            ),
            proceedTitle: OWSLocalizedString(
                "PROFILE_SETTINGS_USERNAME_DELETION_USERNAME_ACTION_TITLE",
                comment: "The title of an action sheet button that will delete a user's username."
            ),
            proceedStyle: .destructive
        ) { [weak self] _ in
            guard let self else { return }

            self.deleteUsernameBehindModalActivityIndicator()
        }
    }

    private func deleteUsernameBehindModalActivityIndicator() {
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false
        ) { modal in
            firstly(on: self.context.schedulers.global()) { () -> Promise<Void> in
                self.context.db.write { tx in
                    return self.context.localUsernameManager
                        .deleteUsername(tx: tx)
                }
            }
            .ensure(on: self.context.schedulers.main) {
                let newState = self.context.db.read { tx in
                    return self.context.localUsernameManager.usernameState(tx: tx)
                }

                // State may have changed with either success or failure.
                self.usernameStateDidChange(newState: newState)
            }
            .done(on: self.context.schedulers.main) {
                modal.dismiss()
            }
            .catch(on: self.context.schedulers.main) { error in
                modal.dismiss {
                    OWSActionSheets.showErrorAlert(
                        message: CommonStrings.somethingWentWrongTryAgainLaterError
                    )
                }
            }
        }
    }

    private func presentUsernameLink(
        username: String,
        usernameLink: Usernames.UsernameLink?
    ) {
        presentFormSheet(
            OWSNavigationController(
                rootViewController: UsernameLinkQRCodeContentController(
                    db: DependenciesBridge.shared.db,
                    localUsernameManager: DependenciesBridge.shared.localUsernameManager,
                    schedulers: DependenciesBridge.shared.schedulers,
                    username: username,
                    usernameLink: usernameLink,
                    changeDelegate: self,
                    scanDelegate: self
                )
            ),
            animated: true
        ) {
            self.hideUsernameLinkTooltip(permanently: true, animated: false)
        }
    }

    private func hideUsernameLinkTooltip(
        permanently: Bool,
        animated: Bool
    ) {
        if let currentUsernameLinkTooltip {
            if animated {
                currentUsernameLinkTooltip.dismissWithAnimation()
            } else {
                currentUsernameLinkTooltip.removeFromSuperview()
            }
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

        // Copy this on the main thread before the asynchronous update.
        let profileValues: ProfileValues = self.profileValues
        let displayBadgesOnProfile = self.displayBadgesOnProfile

        guard reachabilityManager.isReachable else {
            OWSActionSheets.showErrorAlert(
                message: OWSLocalizedString(
                    "PROFILE_VIEW_NO_CONNECTION",
                    comment: "Error shown when the user tries to update their profile when the app is not connected to the internet."
                )
            )
            return
        }

        // Show an activity indicator to block the UI during the profile upload.
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalActivityIndicator in
            Self.databaseStorage.write(.promise) { tx in
                Self.profileManager.updateLocalProfile(
                    profileGivenName: profileValues.givenName.changedValue,
                    profileFamilyName: profileValues.familyName.changedValue,
                    profileBio: profileValues.bio.changedValue,
                    profileBioEmoji: profileValues.bioEmoji.changedValue,
                    profileAvatarData: profileValues.avatarData.changedValue,
                    visibleBadgeIds: profileValues.visibleBadgeIds.changedValue,
                    unsavedRotatedProfileKey: nil,
                    userProfileWriter: .localUser,
                    authedAccount: .implicit(),
                    tx: tx
                )
            }.then(on: SyncScheduler()) { (updatePromise: Promise<Void>) in
                // Run the Promise returned from databaseStorage.write(...).
                updatePromise
            }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
                Self.databaseStorage.write(.promise) { transaction in
                    Self.subscriptionManager.setDisplayBadgesOnProfile(
                        displayBadgesOnProfile,
                        updateStorageService: true,
                        transaction: transaction
                    )
                }
            }.done(on: DispatchQueue.main) {
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

    private func profileCompleted() {
        AssertIsOnMainThread()
        Logger.verbose("")

        navigationController?.popViewController(animated: true)
    }

    // MARK: - Avatar

    private let avatarSizeClass: ConversationAvatarView.Configuration.SizeClass = .eightyEight

    private func avatarImage(transaction tx: SDSAnyReadTransaction) -> UIImage? {
        if let avatarData = profileValues.avatarData.currentValue {
            return UIImage(data: avatarData)
        } else {
            return avatarBuilder.defaultAvatarImageForLocalUser(diameterPoints: avatarSizeClass.diameter, transaction: tx)
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
        profileValues.avatarData.changedValue = .setTo(avatarImage.map(OWSProfileManager.avatarData(forAvatarImage:)))
        updateTableContents()
        updateNavigationItem()
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
        profileValues.bio.changedValue = .setTo(bio?.strippedOrNil)
        profileValues.bioEmoji.changedValue = .setTo(bioEmoji?.strippedOrNil)
        updateTableContents()
        updateNavigationItem()
    }
}

extension ProfileSettingsViewController: ProfileNameViewControllerDelegate {
    func profileNameViewDidComplete(givenName: String?, familyName: String?) {
        profileValues.givenName.changedValue = .setTo(givenName?.strippedOrNil)
        profileValues.familyName.changedValue = .setTo(familyName?.strippedOrNil)
        updateTableContents()
        updateNavigationItem()
    }
}

extension ProfileSettingsViewController: BadgeConfigurationDelegate {
    func badgeConfiguration(_ vc: BadgeConfigurationViewController, didCompleteWithBadgeSetting setting: BadgeConfiguration) {
        let visibleBadgeIds: [String]
        switch setting {
        case .doNotDisplayPublicly:
            displayBadgesOnProfile = false
            visibleBadgeIds = []
        case .display(featuredBadge: let featuredBadge):
            guard allBadges.contains(where: { $0.badgeId == featuredBadge.badgeId }) else {
                owsFailDebug("Invalid badge")
                return
            }
            let nonPrimaryBadges = allBadges.filter { $0.badgeId != featuredBadge.badgeId }
            allBadges = [featuredBadge] + nonPrimaryBadges
            displayBadgesOnProfile = true
            visibleBadgeIds = allBadges.map { $0.badgeId }
        }

        profileValues.visibleBadgeIds.changedValue = .setTo(visibleBadgeIds)
        updateTableContents()
        updateNavigationItem()

        vc.dismiss(animated: true)
    }

    func badgeConfirmationDidCancel(_ vc: BadgeConfigurationViewController) {
        vc.dismiss(animated: true)
    }
}

extension ProfileSettingsViewController: UsernameChangeDelegate {
    func usernameStateDidChange(newState: Usernames.LocalUsernameState) {
        localUsernameState = newState

        updateTableContents()

        usernameChangeDelegate?.usernameStateDidChange(newState: newState)
    }
}

extension ProfileSettingsViewController: UsernameLinkScanDelegate {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink) {
        usernameLinkScanDelegate?.usernameLinkScanned(usernameLink)
    }
}
