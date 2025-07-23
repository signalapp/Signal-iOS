//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AppSettingsViewController: OWSTableViewController2 {

    private let appReadiness: AppReadinessSetter

    init(appReadiness: AppReadinessSetter) {
        self.appReadiness = appReadiness
        super.init()
    }

    class func inModalNavigationController(appReadiness: AppReadinessSetter) -> OWSNavigationController {
        OWSNavigationController(rootViewController: AppSettingsViewController(appReadiness: appReadiness))
    }

    private var localUsernameState: Usernames.LocalUsernameState!
    private var localUserProfile: OWSUserProfile?

    override func viewDidLoad() {
        super.viewDidLoad()

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            updateLocalUserProfile(tx: tx)
            localUsernameState = DependenciesBridge.shared.localUsernameManager
                .usernameState(tx: tx)
        }

        title = OWSLocalizedString("SETTINGS_NAV_BAR_TITLE", comment: "Title for settings activity")
        navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        updateHasExpiredGiftBadge()
        updateTableContents()

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        if let localAci = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci {
            Task {
                let profileFetcher = SSKEnvironment.shared.profileFetcherRef
                _ = try? await profileFetcher.fetchProfile(for: localAci, context: .init(isOpportunistic: true))
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localProfileDidChange),
            name: UserProfileNotifications.localProfileDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localNumberDidChange),
            name: .localNumberDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subscriptionStateDidChange),
            name: DonationReceiptCredentialRedemptionJob.didSucceedNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hasExpiredGiftBadgeDidChange),
            name: .hasExpiredGiftBadgeDidChangeNotification,
            object: nil
        )
    }

    private func updateLocalUserProfile(tx: DBReadTransaction) {
        let profileManager = SSKEnvironment.shared.profileManagerRef
        self.localUserProfile = profileManager.localUserProfile(tx: tx)
    }

    @objc
    private func localProfileDidChange() {
        AssertIsOnMainThread()

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        databaseStorage.read(block: updateLocalUserProfile(tx:))
        updateTableContents()
    }

    @objc
    private func localNumberDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    @objc
    private func subscriptionStateDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    private var hasExpiredGiftBadge: Bool = false

    private func updateHasExpiredGiftBadge() {
        self.hasExpiredGiftBadge = DonationSettingsViewController.shouldShowExpiredGiftBadgeSheetWithSneakyTransaction()
    }

    @objc
    private func hasExpiredGiftBadgeDidChange() {
        AssertIsOnMainThread()

        let oldValue = self.hasExpiredGiftBadge
        self.updateHasExpiredGiftBadge()
        if oldValue != self.hasExpiredGiftBadge {
            self.updateTableContents()
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    func updateTableContents() {
        let isPrimaryDevice = DependenciesBridge.shared.db.read { tx in
            return DependenciesBridge.shared.tsAccountManager
                .registrationState(tx: tx)
                .isPrimaryDevice == true
        }

        let contents = OWSTableContents()

        let profileSection = OWSTableSection(items: [
            OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    return self.profileCell()
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    let vc = ProfileSettingsViewController(
                        usernameChangeDelegate: self,
                        usernameLinkScanDelegate: self
                    )
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            )
        ])
        contents.add(profileSection)

        let section1 = OWSTableSection()
        section1.add(.disclosureItem(
            icon: .settingsAccount,
            withText: OWSLocalizedString("SETTINGS_ACCOUNT", comment: "Title for the 'account' link in settings."),
            actionBlock: { [weak self, appReadiness] in
                let vc = AccountSettingsViewController(appReadiness: appReadiness)
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        if isPrimaryDevice {
            section1.add(.disclosureItem(
                icon: .settingsLinkedDevices,
                withText: OWSLocalizedString("LINKED_DEVICES_TITLE", comment: "Menu item and navbar title for the device manager"),
                actionBlock: { [weak self] in
                    self?.navigationController?.pushViewController(
                        LinkedDevicesHostingController(),
                        animated: true
                    )
                }
            ))
        }
        section1.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let accessoryContentView: UIView?
            if self.hasExpiredGiftBadge {
                let imageView = UIImageView(image: UIImage(imageLiteralResourceName: "info-fill"))
                imageView.tintColor = Theme.accentBlueColor
                imageView.autoSetDimensions(to: CGSize(square: 24))
                accessoryContentView = imageView
            } else {
                accessoryContentView = nil
            }
            return OWSTableItem.buildCell(
                icon: .settingsDonate,
                itemName: OWSLocalizedString("SETTINGS_DONATE", comment: "Title for the 'donate to signal' link in settings."),
                accessoryType: .disclosureIndicator,
                accessoryContentView: accessoryContentView,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donate")
            )
        }, actionBlock: { [weak self] in
            self?.didTapDonate()
        }))
        contents.add(section1)

        let section2 = OWSTableSection()
        section2.add(.disclosureItem(
            icon: .settingsAppearance,
            withText: OWSLocalizedString("SETTINGS_APPEARANCE_TITLE", comment: "The title for the appearance settings."),
            actionBlock: { [weak self] in
                let vc = AppearanceSettingsTableViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsChats,
            withText: OWSLocalizedString("SETTINGS_CHATS", comment: "Title for the 'chats' link in settings."),
            actionBlock: { [weak self] in
                let vc = ChatsSettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsStories,
            withText: OWSLocalizedString(
                "STORY_SETTINGS_TITLE",
                comment: "Label for the stories section of the settings view"
            ),
            actionBlock: { [weak self] in
                let vc = StoryPrivacySettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsNotifications,
            withText: OWSLocalizedString("SETTINGS_NOTIFICATIONS", comment: "The title for the notification settings."),
            actionBlock: { [weak self] in
                let vc = NotificationSettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsPrivacy,
            withText: OWSLocalizedString("SETTINGS_PRIVACY_TITLE", comment: "The title for the privacy settings."),
            actionBlock: { [weak self] in
                let vc = PrivacySettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        if
            isPrimaryDevice,
            RemoteConfig.current.allowBackupSettings
        {
            section2.add(.disclosureItem(
                icon: .backup,
                withText: OWSLocalizedString(
                    "SETTINGS_BACKUPS",
                    comment: "Label for the 'backups' section of app settings."
                ),
                actionBlock: { [weak self] in
                    guard let self else { return }

                    let backupSettingsStore = BackupSettingsStore()
                    let db = DependenciesBridge.shared.db

                    let haveBackupsEverBeenEnabled = db.read { tx in
                        backupSettingsStore.haveBackupsEverBeenEnabled(tx: tx)
                    }

                    if haveBackupsEverBeenEnabled {
                        let vc = BackupSettingsViewController(onLoadAction: .none)
                        navigationController?.pushViewController(vc, animated: true)
                    } else {
                        BackupOnboardingCoordinator().present(fromViewController: self)
                    }
                }
            ))
        }
        section2.add(.disclosureItem(
            icon: .settingsDataUsage,
            withText: OWSLocalizedString("SETTINGS_DATA", comment: "Label for the 'data' section of the app settings."),
            actionBlock: { [weak self] in
                let vc = DataSettingsTableViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.add(section2)

        if SUIEnvironment.shared.paymentsRef.shouldShowPaymentsUI {
            let paymentsSection = OWSTableSection()
            paymentsSection.add(.init(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.preservesSuperviewLayoutMargins = true
                    cell.contentView.preservesSuperviewLayoutMargins = true

                    var subviews = [UIView]()

                    let iconView = OWSTableItem.imageView(forIcon: .settingsPayments,
                                                          tintColor: nil,
                                                          iconSize: OWSTableItem.iconSize)
                    iconView.setCompressionResistanceHorizontalHigh()
                    subviews.append(iconView)
                    subviews.append(UIView.spacer(withWidth: OWSTableItem.iconSpacing))

                    let nameLabel = UILabel()
                    nameLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_TITLE",
                                                       comment: "Label for the 'payments' section of the app settings.")
                    nameLabel.textColor = Theme.primaryTextColor
                    nameLabel.font = OWSTableItem.primaryLabelFont
                    nameLabel.adjustsFontForContentSizeCategory = true
                    nameLabel.numberOfLines = 0
                    nameLabel.lineBreakMode = .byWordWrapping
                    nameLabel.setContentHuggingLow()
                    nameLabel.setCompressionResistanceHigh()
                    subviews.append(nameLabel)

                    subviews.append(UIView.hStretchingSpacer())

                    let unreadPaymentsCount = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                        PaymentFinder.unreadCount(transaction: transaction)
                    }
                    if unreadPaymentsCount > 0 {
                        let unreadLabel = UILabel()
                        unreadLabel.text = OWSFormat.formatUInt(min(9, unreadPaymentsCount))
                        unreadLabel.font = .dynamicTypeBody2Clamped
                        unreadLabel.textColor = .ows_white

                        let unreadBadge = OWSLayerView.circleView()
                        unreadBadge.backgroundColor = .ows_accentBlue
                        unreadBadge.addSubview(unreadLabel)
                        unreadLabel.autoCenterInSuperview()
                        unreadLabel.autoPinEdge(toSuperviewEdge: .top, withInset: 3)
                        unreadLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
                        unreadBadge.autoPinToSquareAspectRatio()
                        unreadBadge.setContentHuggingHorizontalHigh()
                        unreadBadge.setCompressionResistanceHorizontalHigh()
                        subviews.append(unreadBadge)
                    }

                    let contentRow = UIStackView(arrangedSubviews: subviews)
                    contentRow.alignment = .center
                    cell.contentView.addSubview(contentRow)

                    contentRow.setContentHuggingHigh()
                    contentRow.autoPinEdgesToSuperviewMargins()
                    contentRow.autoSetDimension(.height, toSize: OWSTableItem.iconSize, relation: .greaterThanOrEqual)

                    cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "payments")
                    cell.accessoryType = .disclosureIndicator

                    return cell
                },
                actionBlock: { [weak self, appReadiness] in
                    let vc = PaymentsSettingsViewController(mode: .inAppSettings, appReadiness: appReadiness)
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
            contents.add(paymentsSection)
        }

        let section3 = OWSTableSection()
        section3.add(.disclosureItem(
            icon: .settingsHelp,
            withText: CommonStrings.help,
            actionBlock: { [weak self] in
                let vc = HelpViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section3.add(.item(
            icon: .settingsInvite,
            name: OWSLocalizedString("SETTINGS_INVITE_TITLE", comment: "Settings table view cell label"),
            actionBlock: { [weak self] in
                self?.showInviteFlow()
            }
        ))
        contents.add(section3)

        if DebugFlags.internalSettings {
            let internalSection = OWSTableSection()
            internalSection.add(.disclosureItem(
                icon: .settingsAdvanced,
                withText: "Internal",
                actionBlock: { [weak self, appReadiness] in
                    let vc = InternalSettingsViewController(appReadiness: appReadiness)
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
            contents.add(internalSection)
        }

        self.contents = contents
    }

    private func showInviteFlow() {
        let inviteFlow = InviteFlow(presentingViewController: self)
        inviteFlow.present(isAnimated: true, completion: nil)
    }

    private func profileCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let avatarImageView = profileCellAvatarImageView()
        let infoStack = profileCellProfileInfoStack()

        cell.contentView.addSubview(avatarImageView)
        cell.contentView.addSubview(infoStack)

        avatarImageView.autoPinLeadingToSuperviewMargin()
        avatarImageView.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        avatarImageView.autoVCenterInSuperview()

        avatarImageView.autoPinTrailing(toLeadingEdgeOf: infoStack, offset: 12)

        infoStack.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        infoStack.autoVCenterInSuperview()
        infoStack.autoPinTrailingToSuperviewMargin()

        if let usernameLinkButton = profileCellUsernameLinkButton() {
            cell.accessoryView = usernameLinkButton
        } else {
            cell.accessoryType = .disclosureIndicator
        }

        return cell
    }

    private func profileCellAvatarImageView() -> UIView {
        let avatarImageView = ConversationAvatarView(
            sizeClass: .customDiameter(72),
            localUserDisplayMode: .asUser
        )

        if let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress {
            avatarImageView.updateWithSneakyTransactionIfNecessary { config in
                config.dataSource = .address(localAddress)
            }
        }

        return avatarImageView
    }

    /// A view presenting quick info about the user's profile.
    private func profileCellProfileInfoStack() -> UIView {
        let profileInfoStack = UIStackView()
        profileInfoStack.axis = .vertical
        profileInfoStack.spacing = 0

        let nameLabel = UILabel()
        profileInfoStack.addArrangedSubview(nameLabel)
        nameLabel.font = UIFont.dynamicTypeTitle2Clamped.medium()
        if let fullName = localUserProfile?.filteredFullName?.nilIfEmpty {
            nameLabel.text = fullName
            nameLabel.textColor = Theme.primaryTextColor
        } else {
            nameLabel.text = OWSLocalizedString(
                "APP_SETTINGS_EDIT_PROFILE_NAME_PROMPT",
                comment: "Text prompting user to edit their profile name."
            )
            nameLabel.textColor = Theme.accentBlueColor
        }

        @discardableResult
        func addSubtitleLabel(
            text: String,
            textColor: UIColor
        ) -> UIView? {
            guard !text.isEmpty else { return nil }

            let label = UILabel()
            label.font = .dynamicTypeFootnoteClamped
            label.text = text
            label.textColor = textColor

            let containerView = UIView()
            containerView.layoutMargins = UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
            containerView.addSubview(label)
            label.autoPinEdgesToSuperviewMargins()

            profileInfoStack.addArrangedSubview(containerView)
            return containerView
        }

        if let phoneNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber {
            addSubtitleLabel(
                text: PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(phoneNumber),
                textColor: Theme.primaryTextColor
            )
        } else {
            owsFailDebug("Missing local number")
        }

        if let localUsernameState {
            switch localUsernameState {
            case let .available(username, _):
                addSubtitleLabel(
                    text: username,
                    textColor: Theme.primaryTextColor
                )
            case .unset, .usernameAndLinkCorrupted, .linkCorrupted:
                break
            }
        }

        if let bioText = localUserProfile?.bioForDisplay {
            let bioLabel = addSubtitleLabel(
                text: bioText,
                textColor: Theme.secondaryTextAndIconColor
            )
            bioLabel?.layoutMargins.top = 8
        }

        profileInfoStack.arrangedSubviews.last?.layoutMargins.bottom = 2

        return profileInfoStack
    }

    /// If we have a username, produces a button that takes the user to their
    /// username link QR code.
    ///
    /// Note that this button does not use autolayout, so as to play nice with
    /// ``UITableViewCell``'s accessory view.
    private func profileCellUsernameLinkButton() -> UIButton? {
        let localUsername: String
        let localUsernameLink: Usernames.UsernameLink

        switch localUsernameState {
        case nil, .unset, .usernameAndLinkCorrupted, .linkCorrupted:
            return nil
        case let .available(username, usernameLink):
            localUsername = username
            localUsernameLink = usernameLink
        }

        let usernameLinkButton = OWSRoundedButton { [weak self] in
            guard let self else { return }

            let usernameLinkController = UsernameLinkQRCodeContentController(
                db: DependenciesBridge.shared.db,
                localUsernameManager: DependenciesBridge.shared.localUsernameManager,
                username: localUsername,
                usernameLink: localUsernameLink,
                changeDelegate: self,
                scanDelegate: self
            )

            let navController = OWSNavigationController(rootViewController: usernameLinkController)
            self.present(navController, animated: true)
        }

        if Theme.isDarkThemeEnabled {
            usernameLinkButton.backgroundColor = .ows_gray65
            usernameLinkButton.setTemplateImage(Theme.iconImage(.qrCode), tintColor: .ows_gray15)
        } else {
            usernameLinkButton.backgroundColor = .ows_gray05
            usernameLinkButton.setImage(Theme.iconImage(.qrCode), for: .normal)
        }

        usernameLinkButton.bounds = CGRect(origin: .zero, size: .square(36))
        usernameLinkButton.imageView?.autoSetDimensions(to: .square(20))

        return usernameLinkButton
    }

    private func didTapDonate() {
        navigationController?.pushViewController(
            DonationSettingsViewController(),
            animated: true
        )
    }
}

extension AppSettingsViewController: UsernameChangeDelegate {
    func usernameStateDidChange(newState: Usernames.LocalUsernameState) {
        localUsernameState = newState
        updateTableContents()
    }
}

extension AppSettingsViewController: UsernameLinkScanDelegate {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink) {
        guard let presentingViewController else {
            owsFailDebug("Missing presenting view controller!")
            return
        }

        presentingViewController.dismiss(animated: true) {
            SSKEnvironment.shared.databaseStorageRef.read { tx in
                UsernameQuerier().queryForUsernameLink(
                    link: usernameLink,
                    fromViewController: presentingViewController,
                    tx: tx
                ) { _, aci in
                    SignalApp.shared.presentConversationForAddress(
                        SignalServiceAddress(aci),
                        animated: true
                    )
                }
            }
        }
    }
}
