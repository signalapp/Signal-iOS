//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit
import SignalUI

class HomeTabBarController: UITabBarController {
    enum Tabs: Int {
        case chatList = 0
        case stories = 1
    }

    lazy var chatListViewController = ChatListViewController()
    lazy var chatListNavController = OWSNavigationController(rootViewController: chatListViewController)
    lazy var chatListTabBarItem = UITabBarItem(
        title: NSLocalizedString("CHAT_LIST_TITLE_INBOX", comment: "Title for the chat list's default mode."),
        image: #imageLiteral(resourceName: "message-solid-24"),
        selectedImage: #imageLiteral(resourceName: "message-solid-24")
    )

    lazy var storiesViewController = StoriesViewController()
    lazy var storiesNavController = OWSNavigationController(rootViewController: storiesViewController)
    lazy var storiesTabBarItem = UITabBarItem(
        title: NSLocalizedString("STORIES_TITLE", comment: "Title for the stories view."),
        image: #imageLiteral(resourceName: "stories-solid-24"),
        selectedImage: #imageLiteral(resourceName: "stories-solid-24")
    )

    var selectedTab: Tabs { Tabs(rawValue: selectedIndex) ?? .chatList }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Don't render the tab bar if stories isn't enabled.
        // TODO: Eventually there will be a setting for hiding stories.
        guard FeatureFlags.stories else {
            viewControllers = [chatListNavController]
            tabBar.isHidden = true
            return
        }

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
        applyTheme()

        databaseStorage.appendDatabaseChangeDelegate(self)

        viewControllers = [chatListNavController, storiesNavController]

        chatListNavController.tabBarItem = chatListTabBarItem
        storiesNavController.tabBarItem = storiesTabBarItem

        updateAllBadges()
    }

    @objc
    func applyTheme() {
        tabBar.tintColor = Theme.primaryTextColor
    }

    func updateAllBadges() {
        updateStoriesBadge()
        updateChatListBadge()
    }

    func updateStoriesBadge() {
        guard !tabBar.isHidden else { return }
        let unviewedStoriesCount = databaseStorage.read { transaction in
            StoryFinder.unviewedSenderCount(transaction: transaction)
        }
        storiesTabBarItem.badgeValue = unviewedStoriesCount > 0 ? "\(unviewedStoriesCount)" : nil
    }

    func updateChatListBadge() {
        guard !tabBar.isHidden else { return }
        let unreadMessageCount = databaseStorage.read { transaction in
            InteractionFinder.unreadCountInAllThreads(transaction: transaction.unwrapGrdbRead)
        }
        chatListTabBarItem.badgeValue = unreadMessageCount > 0 ? "\(unreadMessageCount)" : nil
    }
}

extension HomeTabBarController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdateInteractions || databaseChanges.didUpdateModel(collection: String(describing: ThreadAssociatedData.self)) {
            updateChatListBadge()
        }
        if databaseChanges.didUpdateModel(collection: StoryMessage.collection()) {
            updateStoriesBadge()
        }
    }

    func databaseChangesDidUpdateExternally() {
        updateAllBadges()
    }

    func databaseChangesDidReset() {
        updateAllBadges()
    }
}
