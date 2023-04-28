//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

@objc
class AppSettingsViewController: OWSTableViewController2 {

    @objc
    class func inModalNavigationController() -> OWSNavigationController {
        OWSNavigationController(rootViewController: AppSettingsViewController())
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_NAV_BAR_TITLE", comment: "Title for settings activity")
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        updateHasExpiredGiftBadge()
        updateTableContents()

        if let localAddress = tsAccountManager.localAddress {
            bulkProfileFetch.fetchProfile(address: localAddress)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localProfileDidChange),
            name: .localProfileDidChange,
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
            name: SubscriptionManagerImpl.SubscriptionJobQueueDidFinishJobNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hasExpiredGiftBadgeDidChange),
            name: .hasExpiredGiftBadgeDidChangeNotification,
            object: nil
        )
    }

    @objc
    func didTapDone() {
        dismiss(animated: true)
    }

    @objc
    func localProfileDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    @objc
    func localNumberDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    @objc
    func subscriptionStateDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    private var hasExpiredGiftBadge: Bool = false

    private func updateHasExpiredGiftBadge() {
        self.hasExpiredGiftBadge = DonationSettingsViewController.shouldShowExpiredGiftBadgeSheetWithSneakyTransaction()
    }

    @objc
    func hasExpiredGiftBadgeDidChange() {
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
        let contents = OWSTableContents()

        let profileSection = OWSTableSection()
        profileSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            return self.profileCell()
        },
            actionBlock: { [weak self] in
                let vc = ProfileSettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(profileSection)

        let section1 = OWSTableSection()
        section1.add(.disclosureItem(
            icon: .settingsAccount,
            name: NSLocalizedString("SETTINGS_ACCOUNT", comment: "Title for the 'account' link in settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "account"),
            actionBlock: { [weak self] in
                let vc = AccountSettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        if self.tsAccountManager.isPrimaryDevice {
            section1.add(.disclosureItem(
                icon: .settingsLinkedDevices,
                name: NSLocalizedString("LINKED_DEVICES_TITLE", comment: "Menu item and navbar title for the device manager"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "linked-devices"),
                actionBlock: { [weak self] in
                    let vc = LinkedDevicesTableViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }
        section1.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let accessoryView: UIView?
            if self.hasExpiredGiftBadge {
                let imageView = UIImageView(image: UIImage(named: "info-solid-24")?.withRenderingMode(.alwaysTemplate))
                imageView.tintColor = Theme.accentBlueColor
                imageView.autoSetDimensions(to: CGSize(square: 24))
                accessoryView = imageView
            } else {
                accessoryView = nil
            }
            return OWSTableItem.buildCellWithAccessoryLabel(
                icon: .settingsDonate,
                itemName: NSLocalizedString("SETTINGS_DONATE", comment: "Title for the 'donate to signal' link in settings."),
                accessoryType: .disclosureIndicator,
                accessoryView: accessoryView,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donate")
            )
        }, actionBlock: { [weak self] in
            self?.didTapDonate()
        }))
        contents.addSection(section1)

        let section2 = OWSTableSection()
        section2.add(.disclosureItem(
            icon: .settingsAppearance,
            name: NSLocalizedString("SETTINGS_APPEARANCE_TITLE", comment: "The title for the appearance settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "appearance"),
            actionBlock: { [weak self] in
                let vc = AppearanceSettingsTableViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsChats,
            name: NSLocalizedString("SETTINGS_CHATS", comment: "Title for the 'chats' link in settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "chats"),
            actionBlock: { [weak self] in
                let vc = ChatsSettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        if RemoteConfig.stories {
            section2.add(.disclosureItem(
                icon: .settingsStories,
                name: NSLocalizedString(
                    "STORY_SETTINGS_TITLE",
                    comment: "Label for the stories section of the settings view"
                ),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "stories"),
                actionBlock: { [weak self] in
                    let vc = StoryPrivacySettingsViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }
        section2.add(.disclosureItem(
            icon: .settingsNotifications,
            name: NSLocalizedString("SETTINGS_NOTIFICATIONS", comment: "The title for the notification settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "notifications"),
            actionBlock: { [weak self] in
                let vc = NotificationSettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsPrivacy,
            name: NSLocalizedString("SETTINGS_PRIVACY_TITLE", comment: "The title for the privacy settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "privacy"),
            actionBlock: { [weak self] in
                let vc = PrivacySettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsDataUsage,
            name: NSLocalizedString("SETTINGS_DATA", comment: "Label for the 'data' section of the app settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "data-usage"),
            actionBlock: { [weak self] in
                let vc = DataSettingsTableViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(section2)

        if payments.shouldShowPaymentsUI {
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
                    nameLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_TITLE",
                                                       comment: "Label for the 'payments' section of the app settings.")
                    nameLabel.textColor = Theme.primaryTextColor
                    nameLabel.font = OWSTableItem.primaryLabelFont
                    nameLabel.adjustsFontForContentSizeCategory = true
                    nameLabel.numberOfLines = 0
                    nameLabel.lineBreakMode = .byWordWrapping
                    nameLabel.setContentHuggingLow()
                    nameLabel.setCompressionResistanceHigh()
                    subviews.append(nameLabel)

                    let betaIcon = UIImage(named: Theme.isDarkThemeEnabled ? "beta-dark-24" : "beta-light-24")
                    let betaIconView = UIImageView(image: betaIcon)
                    betaIconView.setCompressionResistanceHorizontalHigh()
                    subviews.append(UIView.spacer(withWidth: 8))
                    subviews.append(betaIconView)

                    subviews.append(UIView.hStretchingSpacer())

                    let unreadPaymentsCount = Self.databaseStorage.read { transaction in
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
                actionBlock: { [weak self] in
                    let vc = PaymentsSettingsViewController(mode: .inAppSettings)
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
            contents.addSection(paymentsSection)
        }

        let section3 = OWSTableSection()
        section3.add(.disclosureItem(
            icon: .settingsHelp,
            name: CommonStrings.help,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "help"),
            actionBlock: { [weak self] in
                let vc = HelpViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section3.add(.item(
            icon: .settingsInvite,
            name: NSLocalizedString("SETTINGS_INVITE_TITLE", comment: "Settings table view cell label"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "invite"),
            actionBlock: { [weak self] in
                self?.showInviteFlow()
            }
        ))
        contents.addSection(section3)

        if DebugFlags.internalSettings {
            let internalSection = OWSTableSection()
            internalSection.add(.disclosureItem(
                icon: .settingsAdvanced,
                name: "Internal",
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "internal"),
                actionBlock: { [weak self] in
                    let vc = InternalSettingsViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
            contents.addSection(internalSection)
        }

        self.contents = contents
    }

    private var inviteFlow: InviteFlow?
    private func showInviteFlow() {
        let inviteFlow = InviteFlow(presentingViewController: self)
        self.inviteFlow = inviteFlow
        inviteFlow.present(isAnimated: true, completion: nil)
    }

    private func profileCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.accessoryType = .disclosureIndicator

        let hStackView = UIStackView()
        hStackView.axis = .horizontal
        hStackView.spacing = 12

        cell.contentView.addSubview(hStackView)
        hStackView.autoPinEdgesToSuperviewMargins()

        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: false)

        let avatarImageView = ConversationAvatarView(
            sizeClass: .sixtyFour,
            localUserDisplayMode: .asUser)

        if let localAddress = tsAccountManager.localAddress {
            avatarImageView.updateWithSneakyTransactionIfNecessary { config in
                config.dataSource = .address(localAddress)
            }
        }

        hStackView.addArrangedSubview(avatarImageView)

        let vStackView = UIStackView()
        vStackView.axis = .vertical
        vStackView.spacing = 0
        hStackView.addArrangedSubview(vStackView)

        let nameLabel = UILabel()
        vStackView.addArrangedSubview(nameLabel)
        nameLabel.font = UIFont.dynamicTypeTitle2Clamped.medium()
        if let fullName = snapshot.fullName, !fullName.isEmpty {
            nameLabel.text = fullName
            nameLabel.textColor = Theme.primaryTextColor
        } else {
            nameLabel.text = NSLocalizedString(
                "APP_SETTINGS_EDIT_PROFILE_NAME_PROMPT",
                comment: "Text prompting user to edit their profile name."
            )
            nameLabel.textColor = Theme.accentBlueColor
        }

        func addSubtitleLabel(text: String?, isLast: Bool = false) {
            guard let text = text, !text.isEmpty else { return }

            let label = UILabel()
            label.font = .dynamicTypeFootnoteClamped
            label.text = text
            label.textColor = Theme.secondaryTextAndIconColor

            let containerView = UIView()
            containerView.layoutMargins = UIEdgeInsets(top: 2, left: 0, bottom: isLast ? 0 : 2, right: 0)
            containerView.addSubview(label)
            label.autoPinEdgesToSuperviewMargins()

            vStackView.addArrangedSubview(containerView)
        }

        addSubtitleLabel(text: OWSUserProfile.bioForDisplay(bio: snapshot.bio, bioEmoji: snapshot.bioEmoji))

        if let phoneNumber = tsAccountManager.localNumber {
            addSubtitleLabel(
                text: PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber),
                isLast: true
            )
        } else {
            owsFailDebug("Missing local number")
        }

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        vStackView.insertArrangedSubview(topSpacer, at: 0)
        vStackView.addArrangedSubview(bottomSpacer)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        return cell
    }

    private func didTapDonate() {
        let vc: UIViewController
        if DonationSettingsViewController.hasAnythingToShowWithSneakyTransaction() {
            vc = DonationSettingsViewController()
        } else if DonationUtilities.canDonateInAnyWay(localNumber: tsAccountManager.localNumber) {
            vc = DonateViewController(preferredDonateMode: .oneTime) { finishResult in
                let frontVc = { CurrentAppContext().frontmostViewController() }
                switch finishResult {
                case let .completedDonation(donateSheet, thanksSheet):
                    donateSheet.dismiss(animated: true) {
                        frontVc()?.present(thanksSheet, animated: true)
                    }
                case let .monthlySubscriptionCancelled(donateSheet, toastText):
                    donateSheet.dismiss(animated: true) {
                        frontVc()?.presentToast(text: toastText)
                    }
                }
            }
        } else {
            DonationViewsUtil.openDonateWebsite()
            return
        }

        navigationController?.pushViewController(vc, animated: true)
    }
}
