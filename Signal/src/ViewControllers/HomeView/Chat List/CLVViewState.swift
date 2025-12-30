//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CLVViewState {
    let tableDataSource: CLVTableDataSource
    let multiSelectState: MultiSelectState
    let loadCoordinator: CLVLoadCoordinator

    // MARK: - Caches

    let threadViewModelCache = LRUCache<String, ThreadViewModel>(maxSize: 32)
    let cellContentCache = LRUCache<String, CLVCellContentToken>(maxSize: 256)
    var conversationCellHeightCache: CGFloat?

    // MARK: - Views

    let searchResultsController: ConversationSearchViewController
    let searchController: UISearchController

    let containerView: ChatListContainerView
    let reminderViews: CLVReminderViews
    let backupDownloadProgressView: CLVBackupDownloadProgressView
    let settingsButtonCreator: ChatListSettingsButtonState
    let proxyButtonCreator: ChatListProxyButtonCreator

    let spoilerAnimationManager: SpoilerAnimationManager

    // MARK: - State

    let chatListMode: ChatListMode
    var inboxFilter: InboxFilter?
    var shouldBeUpdatingView = false
    var shouldFocusSearchOnAppear = false
    var isViewVisible = false
    var hasEverAppeared = false

    /// Keeps track of the last presented thread so it can remain onscreen even
    /// while filtering the chat list to only unread chats.
    var lastSelectedThreadId: String? {
        didSet {
            shouldBeUpdatingView = true
        }
    }

    var unreadPaymentNotificationsCount: UInt = 0 {
        didSet { settingsButtonCreator.updateState(hasUnreadPaymentNotification: unreadPaymentNotificationsCount > 0) }
    }

    var firstUnreadPaymentModel: TSPaymentModel?
    var lastKnownTableViewContentOffset: CGPoint?

    enum BackupFailureAlertType: CaseIterable {
        case avatarBadge
        case menuItemBadge
        case menuItem

        var errorBadgeTarget: BackupSettingsStore.ErrorBadgeTarget? {
            return switch self {
            case .avatarBadge: .chatListAvatar
            case .menuItemBadge: .chatListMenuItem
            case .menuItem: nil
            }
        }
    }

    var backupFailureAlerts: Set<BackupFailureAlertType> = [] {
        didSet {
            settingsButtonCreator.updateState(
                showBackupsFailedAvatarBadge: backupFailureAlerts.contains(.avatarBadge),
                showBackupsFailedMenuItemBadge: backupFailureAlerts.contains(.menuItemBadge),
                showBackupsFailedMenuItem: backupFailureAlerts.contains(.menuItem),
            )
        }
    }

    enum BackupSubscriptionFailedToRedeemAlertType: CaseIterable {
        case avatarBadge
        case menuItem
    }

    var backupSubscriptionFailedToRedeemAlerts: Set<BackupSubscriptionFailedToRedeemAlertType> = [] {
        didSet {
            settingsButtonCreator.updateState(
                showBackupsSubscriptionAlreadyRedeemedAvatarBadge: backupSubscriptionFailedToRedeemAlerts.contains(.avatarBadge),
                showBackupsSubscriptionAlreadyRedeemedMenuItem: backupSubscriptionFailedToRedeemAlerts.contains(.menuItem),
            )
        }
    }

    enum BackupIAPNotFoundLocallyAlertType: CaseIterable {
        case avatarBadge
        case menuItem
    }

    var backupIAPNotFoundLocallyAlerts: Set<BackupIAPNotFoundLocallyAlertType> = [] {
        didSet {
            settingsButtonCreator.updateState(
                showBackupsIAPNotFoundLocallyAvatarBadge: backupIAPNotFoundLocallyAlerts.contains(.avatarBadge),
                showBackupsIAPNotFoundLocallyMenuItem: backupIAPNotFoundLocallyAlerts.contains(.menuItem),
            )
        }
    }

    var hasConsumedMediaTierCapacity: Bool? {
        didSet {
            settingsButtonCreator.updateState(hasConsumedMediaTierCapacity: hasConsumedMediaTierCapacity)
        }
    }

    let backupDownloadProgressViewState = CLVBackupDownloadProgressView.State()

    // MARK: - Initializer

    @MainActor
    init(chatListMode: ChatListMode, inboxFilter: InboxFilter?) {
        self.chatListMode = chatListMode
        self.inboxFilter = inboxFilter

        self.tableDataSource = CLVTableDataSource()
        self.multiSelectState = MultiSelectState()
        self.loadCoordinator = CLVLoadCoordinator()

        self.spoilerAnimationManager = SpoilerAnimationManager()

        self.searchResultsController = ConversationSearchViewController()
        self.searchController = UISearchController(searchResultsController: searchResultsController)

        self.containerView = ChatListContainerView(tableView: tableDataSource.tableView, searchBar: searchController.searchBar)
        self.reminderViews = CLVReminderViews()
        self.backupDownloadProgressView = CLVBackupDownloadProgressView()
        self.settingsButtonCreator = ChatListSettingsButtonState()
        self.proxyButtonCreator = ChatListProxyButtonCreator(chatConnectionManager: DependenciesBridge.shared.chatConnectionManager)
    }

    func configure() {
        tableDataSource.configure(viewState: self)
    }

    func updateViewInfo(_ viewInfo: CLVViewInfo) {
        inboxFilter = viewInfo.inboxFilter
        settingsButtonCreator.updateState(
            hasInboxChats: viewInfo.inboxCount > 0,
            hasArchivedChats: viewInfo.archiveCount > 0,
        )
    }
}

// MARK: -

extension ChatListViewController {

    var tableDataSource: CLVTableDataSource { viewState.tableDataSource }

    var loadCoordinator: CLVLoadCoordinator { viewState.loadCoordinator }

    // MARK: - Caches

    var threadViewModelCache: LRUCache<String, ThreadViewModel> { viewState.threadViewModelCache }

    var cellContentCache: LRUCache<String, CLVCellContentToken> { viewState.cellContentCache }

    var conversationCellHeightCache: CGFloat? {
        get { viewState.conversationCellHeightCache }
        set { viewState.conversationCellHeightCache = newValue }
    }

    // MARK: - Views

    var tableView: CLVTableView { tableDataSource.tableView }

    var searchBar: UISearchBar { viewState.searchController.searchBar }
    var searchResultsController: ConversationSearchViewController { viewState.searchResultsController }

    var containerView: ChatListContainerView { viewState.containerView }
    var filterControl: ChatListFilterControl? { containerView.filterControl }

    // MARK: - State

    var renderState: CLVRenderState { viewState.tableDataSource.renderState }

    var hasEverAppeared: Bool {
        get { viewState.hasEverAppeared }
        set { viewState.hasEverAppeared = newValue }
    }

    var lastKnownTableViewContentOffset: CGPoint? {
        get { viewState.lastKnownTableViewContentOffset }
        set { viewState.lastKnownTableViewContentOffset = newValue }
    }
}
