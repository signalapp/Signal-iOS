//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class HVViewState: NSObject {

    public let tableDataSource = HVTableDataSource()
    public let threadViewModelCache = LRUCache<String, ThreadViewModel>(maxSize: 32)
    public let cellContentCache = LRUCache<String, HVCellContentToken>(maxSize: 256)

    public let loadCoordinator = HVLoadCoordinator()

    // MARK: - Views

    public let searchBar = OWSSearchBar()
    public let searchResultsController = ConversationSearchViewController()
    public let reminderViews = HVReminderViews()

    // MARK: - State

    // TODO: We should make this a let.
    public var homeViewMode: HomeViewMode = .inbox

    public var shouldBeUpdatingView = false

    public var isViewVisible = false
    public var hasEverAppeared = false

    public var unreadPaymentNotificationsCount: UInt = 0
    public var firstUnreadPaymentModel: TSPaymentModel?

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
public extension HomeViewController {

    var tableDataSource: HVTableDataSource { viewState.tableDataSource }

    @nonobjc
    var threadViewModelCache: LRUCache<String, ThreadViewModel> { viewState.threadViewModelCache }

    @nonobjc
    var cellContentCache: LRUCache<String, HVCellContentToken> { viewState.cellContentCache }

    var loadCoordinator: HVLoadCoordinator { viewState.loadCoordinator }

    // MARK: - Views

    var tableView: HVTableView { tableDataSource.tableView }
    var searchBar: OWSSearchBar { viewState.searchBar }
    var searchResultsController: ConversationSearchViewController { viewState.searchResultsController }

    // MARK: - State

    var homeViewMode: HomeViewMode {
        get { viewState.homeViewMode }
        set { viewState.homeViewMode = newValue }
    }

    var hasEverAppeared: Bool {
        get { viewState.hasEverAppeared }
        set { viewState.hasEverAppeared = newValue }
    }
}
