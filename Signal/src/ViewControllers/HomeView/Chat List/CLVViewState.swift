//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

@objc
public class CLVViewState: NSObject {

    public let tableDataSource = CLVTableDataSource()

    @objc
    public let multiSelectState = MultiSelectState()

    public let loadCoordinator = CLVLoadCoordinator()

    // MARK: - Caches

    public let threadViewModelCache = LRUCache<String, ThreadViewModel>(maxSize: 32)
    let cellContentCache = LRUCache<String, CLVCellContentToken>(maxSize: 256)
    public var conversationCellHeightCache: CGFloat?

    // MARK: - Views

    public let searchBar = OWSSearchBar()
    public let searchResultsController = ConversationSearchViewController()
    public let reminderViews = CLVReminderViews()

    // MARK: - State

    // TODO: We should make this a let.
    public var chatListMode: ChatListMode = .inbox

    public var shouldBeUpdatingView = false

    public var isViewVisible = false
    public var hasEverAppeared = false

    public var unreadPaymentNotificationsCount: UInt = 0
    public var firstUnreadPaymentModel: TSPaymentModel?
    public var lastKnownTableViewContentOffset: CGPoint?

    // MARK: - Initializer

    @objc
    public override required init() {
        super.init()
    }

    @objc
    public func configure() {
        tableDataSource.configure(viewState: self)
    }
}

// MARK: -

@objc
public extension ChatListViewController {

    var tableDataSource: CLVTableDataSource { viewState.tableDataSource }

    var loadCoordinator: CLVLoadCoordinator { viewState.loadCoordinator }

    // MARK: - Caches

    @nonobjc
    var threadViewModelCache: LRUCache<String, ThreadViewModel> { viewState.threadViewModelCache }

    @nonobjc
    internal var cellContentCache: LRUCache<String, CLVCellContentToken> { viewState.cellContentCache }

    @nonobjc
    var conversationCellHeightCache: CGFloat? {
        get { viewState.conversationCellHeightCache }
        set { viewState.conversationCellHeightCache = newValue }
    }

    // MARK: - Views

    var tableView: CLVTableView { tableDataSource.tableView }
    var searchBar: OWSSearchBar { viewState.searchBar }
    var searchResultsController: ConversationSearchViewController { viewState.searchResultsController }

    // MARK: - State

    var chatListMode: ChatListMode {
        get { viewState.chatListMode }
        set { viewState.chatListMode = newValue }
    }

    var hasEverAppeared: Bool {
        get { viewState.hasEverAppeared }
        set { viewState.hasEverAppeared = newValue }
    }

    @nonobjc
    var lastKnownTableViewContentOffset: CGPoint? {
        get { viewState.lastKnownTableViewContentOffset }
        set { viewState.lastKnownTableViewContentOffset = newValue }
    }
}
