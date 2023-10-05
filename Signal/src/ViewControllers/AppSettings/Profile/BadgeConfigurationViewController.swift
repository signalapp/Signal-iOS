//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

enum BadgeConfiguration {
    case doNotDisplayPublicly
    case display(featuredBadge: OWSUserProfileBadgeInfo)
}

protocol BadgeConfigurationDelegate: AnyObject {
    func badgeConfiguration(_: BadgeConfigurationViewController, didCompleteWithBadgeSetting setting: BadgeConfiguration)
    func badgeConfirmationDidCancel(_: BadgeConfigurationViewController)
}

class BadgeConfigurationViewController: OWSTableViewController2, BadgeCollectionDataSource {
    private weak var badgeConfigDelegate: BadgeConfigurationDelegate?

    let availableBadges: [OWSUserProfileBadgeInfo]
    private let initialDisplaySetting: Bool
    private let avatarImage: UIImage?

    private var displayBadgeOnProfile: Bool {
        didSet {
            updateNavigation()
            updateTableContents()
        }
    }

    var selectedBadgeIndex: Int = 0 {
        didSet {
            if !availableBadges.indices.contains(selectedBadgeIndex) {
                owsFailDebug("Invalid badge index")
                selectedBadgeIndex = oldValue
            } else {
                updateNavigation()
                updateTableContents()
            }
        }
    }

    private var selectedPrimaryBadge: OWSUserProfileBadgeInfo? {
        displayBadgeOnProfile ? availableBadges[safe: selectedBadgeIndex] : nil
    }

    private var hasUnsavedChanges: Bool {
        if displayBadgeOnProfile, selectedBadgeIndex != 0 {
            return true
        } else {
            return displayBadgeOnProfile != initialDisplaySetting
        }
    }

    public var showDismissalActivity = false {
        didSet {
            updateNavigation()
        }
    }

    convenience init(fetchingDataFromLocalProfileWithDelegate delegate: BadgeConfigurationDelegate) {
        let snapshot = Self.profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: false)
        let allBadges = snapshot.profileBadgeInfo ?? []
        let shouldDisplayOnProfile = Self.subscriptionManager.displayBadgesOnProfile

        self.init(availableBadges: allBadges, shouldDisplayOnProfile: shouldDisplayOnProfile, delegate: delegate)
    }

    init(availableBadges: [OWSUserProfileBadgeInfo], shouldDisplayOnProfile: Bool, avatarImage: UIImage? = nil, delegate: BadgeConfigurationDelegate) {
        self.availableBadges = availableBadges
        self.initialDisplaySetting = shouldDisplayOnProfile
        owsAssertDebug(availableBadges.indices.contains(selectedBadgeIndex))

        self.displayBadgeOnProfile = self.initialDisplaySetting
        self.badgeConfigDelegate = delegate
        self.avatarImage = avatarImage
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateNavigation()
        updateTableContents()
    }

    // MARK: - Navigation Bar

    private func updateNavigation() {
        if navigationController?.viewControllers.count == 1 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(didTapCancel),
                accessibilityIdentifier: "cancel_button")
        }

        if hasUnsavedChanges, showDismissalActivity {
            let indicatorStyle: UIActivityIndicatorView.Style
            indicatorStyle = .medium
            let spinner = UIActivityIndicatorView(style: indicatorStyle)
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else if hasUnsavedChanges, !showDismissalActivity {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "set_button")
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc
    private func didTapCancel() {
        let requestDismissal: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.badgeConfigDelegate?.badgeConfirmationDidCancel(self)
        }

        if hasUnsavedChanges {
            OWSActionSheets.showPendingChangesActionSheet(discardAction: requestDismissal)
        } else {
            requestDismissal()
        }
    }

    @objc
    private func didTapDone() {
        if displayBadgeOnProfile, let selectedPrimaryBadge = selectedPrimaryBadge {
            badgeConfigDelegate?.badgeConfiguration(self, didCompleteWithBadgeSetting: .display(featuredBadge: selectedPrimaryBadge))
        } else {
            badgeConfigDelegate?.badgeConfiguration(self, didCompleteWithBadgeSetting: .doNotDisplayPublicly)
        }
    }

    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    // MARK: - TableContents

    func updateTableContents() {
        self.contents = OWSTableContents(
            title: OWSLocalizedString("BADGE_CONFIGURATION_TITLE", comment: "The title for the badge configuration page"),
            sections: [
                OWSTableSection(
                    title: OWSLocalizedString(
                        "BADGE_CONFIGURATION_BADGE_SECTION_TITLE",
                        comment: "Section header for badge view section in the badge configuration page"),
                    items: [
                        OWSTableItem(customCellBlock: { [weak self] in
                            let cell = OWSTableItem.newCell()
                            guard let self = self else { return cell }
                            let collectionView = BadgeCollectionView(dataSource: self)

                            if let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress {
                                let localShortName = self.databaseStorage.read { self.contactsManager.shortDisplayName(for: localAddress, transaction: $0) }
                                collectionView.badgeSelectionMode = .detailsSheet(owner: .local(shortName: localShortName))
                            } else {
                                owsFailDebug("Unexpectedly missing local address")
                            }

                            cell.contentView.addSubview(collectionView)
                            collectionView.autoPinEdgesToSuperviewMargins()

                            // Pre-layout the collection view so the UITableView caches the correct resolved
                            // autolayout height.
                            collectionView.layoutIfNeeded()

                            return cell
                        }, actionBlock: nil)
                ]),

                OWSTableSection(title: nil, items: [
                    .switch(
                        withText: OWSLocalizedString(
                            "DISPLAY_BADGES_ON_PROFILE_SETTING",
                            comment: "Title for switch to enable sharing of badges publicly"),
                        isOn: { [weak self] in self?.displayBadgeOnProfile ?? false },
                        target: self,
                        selector: #selector(didTogglePublicDisplaySetting(_:))),

                    .item(
                        name: OWSLocalizedString(
                            "FEATURED_BADGE_SETTINGS_TITLE",
                            comment: "The title for the featured badge settings page"),
                        textColor: displayBadgeOnProfile ? nil : .ows_gray45,
                        accessoryText: selectedPrimaryBadge?.badge?.localizedName,
                        accessoryType: .disclosureIndicator,
                        accessibilityIdentifier: "badge_configuration_row",
                        actionBlock: { [weak self] in
                            guard let self = self, let navController = self.navigationController else { return }
                            guard self.displayBadgeOnProfile else { return }

                            let featuredBadgeSettings = FeaturedBadgeViewController(avatarImage: self.avatarImage, badgeDataSource: self)
                            navController.pushViewController(featuredBadgeSettings, animated: true)
                        })
                ])
        ])
    }

    @objc
    private func didTogglePublicDisplaySetting(_ sender: UISwitch) {
        displayBadgeOnProfile = sender.isOn
    }

    var shouldCancelNavigationBack: Bool {
        if hasUnsavedChanges {
            didTapCancel()
            return true
        } else {
            return false
        }
    }
}
