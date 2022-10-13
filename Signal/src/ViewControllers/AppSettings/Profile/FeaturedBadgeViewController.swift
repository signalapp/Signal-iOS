//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

class FeaturedBadgeViewController: OWSTableViewController2, BadgeCollectionDataSource {
    private weak var badgeDataSource: BadgeCollectionDataSource?

    private var avatarImage: UIImage?
    private let sizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight
    private lazy var avatarView = ConversationAvatarView(sizeClass: sizeClass, localUserDisplayMode: .asUser)

    init(avatarImage: UIImage?, badgeDataSource: BadgeCollectionDataSource) {
        self.avatarImage = avatarImage
        self.badgeDataSource = badgeDataSource
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if avatarImage == nil {
            avatarImage = Self.avatarBuilder.avatarImageForLocalUserWithSneakyTransaction(
                diameterPoints: sizeClass.diameter,
                localUserDisplayMode: .asUser)
        }
        updateAvatarView()
        updateTableContents()

        // We don't set up our own navigation bar. We expect to be presented from within a nav controller
        owsAssertDebug(navigationController != nil)
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateAvatarView()
    }

    // MARK: - TableContents

    func updateTableContents() {
        self.contents = OWSTableContents(
            title: NSLocalizedString("FEATURED_BADGE_SETTINGS_TITLE", comment: "The title for the featured badge settings page"),
            sections: [
                OWSTableSection(header: { [weak self] in
                    guard let avatarView = self?.avatarView else { return UIView() }

                    let containerView = UIView()
                    containerView.addSubview(avatarView)
                    avatarView.autoHCenterInSuperview()
                    avatarView.autoPinEdge(toSuperviewEdge: .top, withInset: 88)
                    avatarView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 36)
                    return containerView
                }),

                OWSTableSection(
                    title: NSLocalizedString("FEATURED_BADGE_SECTION_HEADER", comment: "Section header directing user to select a badge"),
                    items: [
                        OWSTableItem(customCellBlock: { [weak self] in
                            let cellContent: UIView
                            if let self = self {
                                let badgeCollectionView = BadgeCollectionView(dataSource: self)
                                badgeCollectionView.badgeSelectionMode = .feature
                                cellContent = badgeCollectionView
                            } else {
                                cellContent = UIView()
                            }

                            let cell = OWSTableItem.newCell()
                            cell.contentView.addSubview(cellContent)
                            cellContent.autoPinEdgesToSuperviewMargins()

                            // Pre-layout the collection view so the UITableView caches the correct resolved
                            // autolayout height.
                            cellContent.layoutIfNeeded()

                            return cell
                        }, actionBlock: nil)
                    ])
            ])
    }

    func updateAvatarView() {
        let assets = availableBadges[safe: selectedBadgeIndex]?.badge?.assets
        let avatarBadge = assets.flatMap { sizeClass.fetchImageFromBadgeAssets($0) }

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .asset(avatar: avatarImage, badge: avatarBadge)
        }
    }

    // MARK: - <BadgeCollectionDataSource>

    // We insert ourselves into the data source chain in order to be notified of a change to the selectedBadgeIndex
    // Otherwise, we just forward everything to our badge data source

    var availableBadges: [OWSUserProfileBadgeInfo] { badgeDataSource?.availableBadges ?? [] }
    var selectedBadgeIndex: Int {
        get { badgeDataSource?.selectedBadgeIndex ?? 0 }
        set {
            badgeDataSource?.selectedBadgeIndex = newValue
            updateAvatarView()
        }
    }
}
