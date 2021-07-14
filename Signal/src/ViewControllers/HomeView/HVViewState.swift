//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class HVViewState: NSObject {
    public let threadMapping = ThreadMapping()

    // TODO: Rework OWSBlockListCache.
    public let blocklistCache = BlockListCache()

    // MARK: - Views

    public let tableView = UITableView(frame: .zero, style: .grouped)
    public let reminderViewCell = UITableViewCell()

    // MARK: - State

    public var conversationListMode: ConversationListMode = .inbox

    public var isViewVisible = false
    public var hasEverAppeared = false
    public var lastReloadDate: Date?

    // TODO: Review.
    public var hasArchivedThreadsRow = false
    // TODO: Review.
    public var hasThemeChanged = false
    // TODO: Review.
    public var hasVisibleReminders = false
}

// MARK: -

@objc
public extension ConversationListViewController {

    var threadMapping: ThreadMapping { viewState.threadMapping }
    var blocklistCache: BlockListCache { viewState.blocklistCache }

    // MARK: - Views

    var tableView: UITableView { viewState.tableView }
    var reminderViewCell: UITableViewCell { viewState.reminderViewCell }

    // MARK: - State

    var conversationListMode: ConversationListMode {
        get { viewState.conversationListMode }
        set { viewState.conversationListMode = newValue }
    }

    var isViewVisible: Bool {
        get { viewState.isViewVisible }
        set { viewState.isViewVisible = newValue }
    }
    var hasEverAppeared: Bool {
        get { viewState.hasEverAppeared }
        set { viewState.hasEverAppeared = newValue }
    }
    var lastReloadDate: Date? {
        get { viewState.lastReloadDate }
        set { viewState.lastReloadDate = newValue }
    }

    var hasArchivedThreadsRow: Bool {
        get { viewState.hasArchivedThreadsRow }
        set { viewState.hasArchivedThreadsRow = newValue }
    }
    var hasThemeChanged: Bool {
        get { viewState.hasThemeChanged }
        set { viewState.hasThemeChanged = newValue }
    }
    var hasVisibleReminders: Bool {
        get { viewState.hasVisibleReminders }
        set { viewState.hasVisibleReminders = newValue }
    }
}
