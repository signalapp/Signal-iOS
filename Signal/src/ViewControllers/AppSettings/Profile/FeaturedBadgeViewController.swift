//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI

class FeaturedBadgeViewController: OWSTableViewController2 {
    private weak var badgeDataSource: BadgeCollectionDataSource?
    private lazy var avatarView: UIView = {
        let avatarView = ConversationAvatarView(sizeClass: .eightyEight, localUserDisplayMode: .asUser, badged: true)
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            // TODO Fix
            config.dataSource = .address(tsAccountManager.localAddress!)
        }

        let containerView = UIView()
        containerView.addSubview(avatarView)
        avatarView.autoHCenterInSuperview()
        avatarView.autoPinEdge(toSuperviewEdge: .top, withInset: 88)
        avatarView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 36)
        return containerView
    }()

    init(badgeDataSource: BadgeCollectionDataSource) {
        self.badgeDataSource = badgeDataSource
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()

        // We don't set up our own navigation bar. We expect to be presented from within a nav controller
        owsAssertDebug(navigationController != nil)
    }

    // MARK: - TableContents

    func updateTableContents() {
        self.contents = OWSTableContents(
            title: "Featured Badge",
            sections: [
                OWSTableSection(header: {
                    return avatarView
                }),

                OWSTableSection(
                    title: "Select a Badge",
                    items: [
                        OWSTableItem(customCellBlock: { [weak self] in
                            let badgeCollectionView: UIView
                            if let badgeDataSource = self?.badgeDataSource {
                                badgeCollectionView = BadgeCollectionView(dataSource: badgeDataSource)
                            } else {
                                badgeCollectionView = UIView()
                            }

                            let cell = OWSTableItem.newCell()
                            cell.contentView.addSubview(badgeCollectionView)
                            badgeCollectionView.autoPinEdgesToSuperviewMargins()

                            // Pre-layout the collection view so the UITableView caches the correct resolved
                            // autolayout height.
                            badgeCollectionView.layoutIfNeeded()

                            return cell
                        }, actionBlock: nil)
                    ])
            ])
    }
}
