//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class HVViewState: NSObject {

    public let tableDataSource = HVTableDataSource()
    public let threadViewModelCache = LRUCache<String, ThreadViewModel>(maxSize: 32)
    public let cellMeasurementCache = LRUCache<String, HVCellMeasurement>(maxSize: 256)

    public let loadCoordinator = HVLoadCoordinator()

    // MARK: - Views

    public let reminderViewCell = UITableViewCell()
    public let searchBar = OWSSearchBar()
    public let searchResultsController = ConversationSearchViewController()

    // MARK: - State

    // TODO: We should make this a let.
    public var homeViewMode: HomeViewMode = .inbox

    public var shouldBeUpdatingView = false

    public var isViewVisible = false
    public var hasEverAppeared = false

    public var hasArchivedThreadsRow = false
    public var hasVisibleReminders = false

    // MARK: - Initializer

    @objc
    public override required init() {
        super.init()

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
    var cellMeasurementCache: LRUCache<String, HVCellMeasurement> { viewState.cellMeasurementCache }

    var loadCoordinator: HVLoadCoordinator { viewState.loadCoordinator }

    // MARK: - Views

    var tableView: HVTableView { tableDataSource.tableView }
    var reminderViewCell: UITableViewCell { viewState.reminderViewCell }
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

    var hasArchivedThreadsRow: Bool {
        get { viewState.hasArchivedThreadsRow }
        set { viewState.hasArchivedThreadsRow = newValue }
    }
}
