//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI

protocol BadgeConfigurationDelegate: AnyObject {
    func updateFeaturedBadge(_: OWSUserProfileBadgeInfo)
    func shouldDisplayBadgesPublicly(_: Bool)
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
        displayBadgeOnProfile != initialDisplaySetting || selectedBadgeIndex != 0
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "set_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc
    func didTapCancel() {
        let dismissBlock: () -> Void = { [weak self] in
            self?.dismiss(animated: true)
        }

        if hasUnsavedChanges {
            OWSActionSheets.showPendingChangesActionSheet(discardAction: dismissBlock)
        } else {
            dismissBlock()
        }
    }

    @objc
    func didTapDone() {
        if selectedBadgeIndex != 0, let selectedPrimaryBadge = selectedPrimaryBadge {
            badgeConfigDelegate?.updateFeaturedBadge(selectedPrimaryBadge)
        }
        if displayBadgeOnProfile != initialDisplaySetting {
            badgeConfigDelegate?.shouldDisplayBadgesPublicly(displayBadgeOnProfile)
        }
        dismiss(animated: true)
    }

    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set { owsFailDebug("Unsupported") }
    }

    // MARK: - TableContents

    func updateTableContents() {
        self.contents = OWSTableContents(
            title: NSLocalizedString("BADGE_CONFIGURATION_TITLE", comment: "The title for the badge configuration page"),
            sections: [
                OWSTableSection(
                    title: NSLocalizedString(
                        "BADGE_CONFIGURATION_BADGE_SECTION_TITLE",
                        comment: "Section header for badge view section in the badge configuration page"),
                    items: [
                        OWSTableItem(customCellBlock: {
                            let collectionView = BadgeCollectionView(dataSource: self)
                            let cell = OWSTableItem.newCell()
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
                        withText: NSLocalizedString(
                            "DISPLAY_BADGES_ON_PROFILE_SETTING",
                            comment: "Title for switch to enable sharing of badges publicly"),
                        isOn: { [weak self] in self?.displayBadgeOnProfile ?? false },
                        target: self,
                        selector: #selector(didTogglePublicDisplaySetting(_:))),

                    .item(
                        name: NSLocalizedString(
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
    func didTogglePublicDisplaySetting(_ sender: UISwitch) {
        displayBadgeOnProfile = sender.isOn
    }
}
