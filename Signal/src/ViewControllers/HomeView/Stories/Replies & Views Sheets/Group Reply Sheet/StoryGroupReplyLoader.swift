//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalMessaging

class StoryGroupReplyLoader: Dependencies {
    private let messageBatchFetcher: StoryGroupReplyBatchFetcher
    private let messageLoader: MessageLoader
    private let threadUniqueId: String
    private let storyMessage: StoryMessage
    private weak var tableView: UITableView?
    private var replyUniqueIds = [String]() {
        didSet { AssertIsOnMainThread() }
    }
    private var replyItems = [String: StoryGroupReplyViewItem]() {
        didSet { AssertIsOnMainThread() }
    }

    var numberOfRows: Int { replyUniqueIds.count }

    private(set) var oldestLoadedRow: Int?

    private(set) var newestLoadedRow: Int?

    var isScrolledToBottom: Bool {
        AssertIsOnMainThread()
        guard let tableView = tableView else { return false }

        let lastIndexPath = IndexPath(row: replyUniqueIds.count - 1, section: 0)

        guard tableView.indexPathsForVisibleRows?.contains(lastIndexPath) ?? false else { return false }

        var container = tableView.bounds
        container.y += tableView.contentInset.top + tableView.safeAreaInsets.top
        container.height -= tableView.contentInset.totalHeight + tableView.safeAreaInsets.totalHeight

        return container.contains(tableView.rectForRow(at: lastIndexPath))
    }

    init?(storyMessage: StoryMessage, threadUniqueId: String?, tableView: UITableView) {
        guard let threadUniqueId = threadUniqueId else {
            owsFailDebug("Unexpectedly missing threadUniqueId")
            return nil
        }

        self.threadUniqueId = threadUniqueId
        self.storyMessage = storyMessage
        self.tableView = tableView
        self.messageBatchFetcher = StoryGroupReplyBatchFetcher(
            storyAuthor: ServiceId(storyMessage.authorUuid),
            storyTimestamp: storyMessage.timestamp
        )
        self.messageLoader = MessageLoader(
            batchFetcher: messageBatchFetcher,
            interactionFetchers: [NSObject.modelReadCaches.interactionReadCache, SDSInteractionFetcherImpl()]
        )

        // Load the first page synchronously.
        databaseStorage.read { transaction in
            load(mode: .initial, transaction: transaction)
        }
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    func replyItem(for indexPath: IndexPath) -> StoryGroupReplyViewItem? {
        guard let uniqueId = replyUniqueIds[safe: indexPath.row] else {
            owsFailDebug("Unexpectedly missing uniqueId for indexPath \(indexPath)")
            return nil
        }

        return replyItems[uniqueId]
    }

    func scrollToBottomOfLoadWindow(animated: Bool) {
        guard numberOfRows > 0 else { return }
        tableView?.scrollToRow(at: IndexPath(row: numberOfRows - 1, section: 0), at: .bottom, animated: animated)
    }

    func loadNewerPageIfNecessary() {
        LoadingMode.newer.async {
            guard self.messageLoader.canLoadNewer else { return }
            self.databaseStorage.read { self.load(mode: .newer, transaction: $0) }
        }
    }

    func loadOlderPageIfNecessary() {
        LoadingMode.older.async {
            guard self.messageLoader.canLoadOlder else { return }
            self.databaseStorage.read { self.load(mode: .older, transaction: $0) }
        }
    }

    func reload(
        updatedInteractionIds: Set<String>? = nil,
        deletedInteractionIds: Set<String>? = nil,
        canReuseInteractions: Bool = true
    ) {
        LoadingMode.reload.async {
            self.databaseStorage.read { self.load(
                mode: .reload,
                canReuseInteractions: canReuseInteractions,
                updatedInteractionIds: updatedInteractionIds,
                deletedInteractionIds: deletedInteractionIds,
                transaction: $0
            ) }
        }
    }

    private enum LoadingMode: Equatable {
        case initial
        case older
        case newer
        case reload

        func async(block: @escaping () -> Void) {
            switch self {
            case .initial:
                DispatchMainThreadSafe(block)
            default:
                DispatchQueue.sharedUserInteractive.async(execute: block)
            }
        }

        var queue: DispatchQueue {
            switch self {
            case .initial: return .main
            default: return .sharedUserInteractive
            }
        }
    }

    private func load(
        mode: LoadingMode,
        canReuseInteractions: Bool = true,
        updatedInteractionIds: Set<String>? = nil,
        deletedInteractionIds: Set<String>? = nil,
        transaction: SDSAnyReadTransaction
    ) {
        assertOnQueue(mode.queue)

        Logger.info("Loading \(mode)")

        let reusableInteractions: [String: TSInteraction]
        if canReuseInteractions {
            let loadedInteractions = messageLoader.loadedInteractions
            reusableInteractions = loadedInteractions.reduce(
                into: [String: TSInteraction]()
            ) { partialResult, interaction in
                guard updatedInteractionIds?.contains(interaction.uniqueId) != true else { return }
                partialResult[interaction.uniqueId] = interaction
            }
        } else {
            reusableInteractions = [:]
        }

        messageBatchFetcher.refetch(tx: transaction)

        do {
            switch mode {
            case .initial:
                try self.messageLoader.loadInitialMessagePage(
                    focusMessageId: messageBatchFetcher.uniqueIdsAndRowIds.first?.uniqueId,
                    reusableInteractions: reusableInteractions,
                    deletedInteractionIds: deletedInteractionIds,
                    tx: transaction.asV2Read
                )
            case .newer:
                try self.messageLoader.loadNewerMessagePage(
                    reusableInteractions: reusableInteractions,
                    deletedInteractionIds: deletedInteractionIds,
                    tx: transaction.asV2Read
                )
            case .older:
                try self.messageLoader.loadOlderMessagePage(
                    reusableInteractions: reusableInteractions,
                    deletedInteractionIds: deletedInteractionIds,
                    tx: transaction.asV2Read
                )
            case .reload:
                try self.messageLoader.loadSameLocation(
                    reusableInteractions: reusableInteractions,
                    deletedInteractionIds: deletedInteractionIds,
                    tx: transaction.asV2Read
                )
            }
        } catch {
            owsFailDebug("Couldn't load story replies \(error)")
        }

        let newReplyItems = buildItems(reusableInteractionIds: Array(reusableInteractions.keys), transaction: transaction)
        let replyUniqueIds = messageBatchFetcher.uniqueIdsAndRowIds.map { $0.uniqueId }
        let oldestLoadedRow = messageLoader.loadedInteractions.first.flatMap { replyUniqueIds.firstIndex(of: $0.uniqueId) }
        let newestLoadedRow = messageLoader.loadedInteractions.last.flatMap { replyUniqueIds.firstIndex(of: $0.uniqueId) }

        DispatchQueue.main.async {
            let wasScrolledToBottom = self.isScrolledToBottom

            self.oldestLoadedRow = oldestLoadedRow
            self.newestLoadedRow = newestLoadedRow
            self.replyUniqueIds = replyUniqueIds
            self.replyItems = newReplyItems
            self.tableView?.reloadData()

            if wasScrolledToBottom { self.scrollToBottomOfLoadWindow(animated: true) }
        }
    }

    private func buildItems(reusableInteractionIds: [String], transaction: SDSAnyReadTransaction) -> [String: StoryGroupReplyViewItem] {
        guard let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: threadUniqueId, transaction: transaction) else {
            owsFailDebug("Missing group thread for story")
            return replyItems
        }

        let loadedInteractions = messageLoader.loadedInteractions

        var messages = [(SignalServiceAddress, TSMessage)]()
        var authorAddresses = Set<SignalServiceAddress>()

        for interaction in loadedInteractions {
            if let outgoingMessage = interaction as? TSOutgoingMessage {
                messages.append((tsAccountManager.localAddress!, outgoingMessage))
                authorAddresses.insert(tsAccountManager.localAddress!)
            } else if let incomingMessage = interaction as? TSIncomingMessage {
                messages.append((incomingMessage.authorAddress, incomingMessage))
                authorAddresses.insert(incomingMessage.authorAddress)
            }
        }

        let groupNameColors = ChatColors.groupNameColors(forThread: groupThread)
        let displayNamesByAddress = contactsManagerImpl.displayNamesByAddress(
            for: Array(authorAddresses),
            transaction: transaction
        )

        var newReplyItems = [String: StoryGroupReplyViewItem]()
        var previousItem: StoryGroupReplyViewItem?
        for (authorAddress, message) in messages {
            let replyItem: StoryGroupReplyViewItem
            if reusableInteractionIds.contains(message.uniqueId), let reusableReplyItem = replyItems[message.uniqueId] {
                replyItem = reusableReplyItem
            } else {
                let recipientStatus: MessageReceiptStatus?
                if let message = message as? TSOutgoingMessage {
                    recipientStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: message)
                } else {
                    recipientStatus = nil
                }

                let displayName = authorAddress.isLocalAddress
                    ? CommonStrings.you
                    : displayNamesByAddress[authorAddress]
                replyItem = StoryGroupReplyViewItem(
                    message: message,
                    authorAddress: authorAddress,
                    authorDisplayName: displayName,
                    authorColor: groupNameColors.color(for: authorAddress),
                    recipientStatus: recipientStatus,
                    transaction: transaction
                )
            }

            newReplyItems[message.uniqueId] = replyItem

            if let previousItem = previousItem, canCollapse(item: replyItem, previousItem: previousItem) {
                switch previousItem.cellType.position {
                case .standalone:
                    previousItem.cellType.position = .top
                case .bottom:
                    previousItem.cellType.position = .middle
                case .top, .middle:
                    break
                }

                replyItem.cellType.position = .bottom
            } else {
                switch replyItem.cellType.position {
                case .standalone:
                    break
                case .top, .middle, .bottom:
                    replyItem.cellType.position = .standalone
                }
            }

            previousItem = replyItem
        }

        return newReplyItems
    }

    private func canCollapse(item: StoryGroupReplyViewItem, previousItem: StoryGroupReplyViewItem) -> Bool {
        guard previousItem.cellType.kind == item.cellType.kind else { return false }
        switch item.cellType.kind {
        case .reaction: return true
        case .text:
            return previousItem.authorAddress == item.authorAddress &&
            previousItem.timeString == item.timeString &&
            ![.pending, .uploading, .sending, .failed].contains(previousItem.recipientStatus)
        }
    }
}

extension StoryGroupReplyLoader: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard let storyId = storyMessage.id, databaseChanges.storyMessageRowIds.contains(storyId) else { return }
        reload(
            updatedInteractionIds: databaseChanges.interactionUniqueIds,
            deletedInteractionIds: databaseChanges.interactionDeletedUniqueIds
        )
    }

    func databaseChangesDidUpdateExternally() {
        reload(canReuseInteractions: false)
    }

    func databaseChangesDidReset() {
        reload(canReuseInteractions: false)
    }
}

// MARK: - Batch Fetcher

private class StoryGroupReplyBatchFetcher: MessageLoaderBatchFetcher {
    private let storyAuthor: ServiceId
    private let storyTimestamp: UInt64

    private(set) var uniqueIdsAndRowIds = [(uniqueId: String, rowId: Int64)]()

    init(storyAuthor: ServiceId, storyTimestamp: UInt64) {
        self.storyAuthor = storyAuthor
        self.storyTimestamp = storyTimestamp
    }

    func refetch(tx: SDSAnyReadTransaction) {
        uniqueIdsAndRowIds = InteractionFinder.groupReplyUniqueIdsAndRowIds(
            storyAuthor: storyAuthor,
            storyTimestamp: storyTimestamp,
            transaction: tx
        )
    }

    func fetchUniqueIds(filter: RowIdFilter, excludingPlaceholders excludePlaceholders: Bool, limit: Int, tx: DBReadTransaction) throws -> [String] {
        // This design is extremely weird. However, we already fetch all the
        // uniqueIds for a given story when rendering the view, and while we could
        // design a bunch of equivalent database queries to do the same thing, we
        // already have access to everything we need in memory. The performance of
        // this entire method is O(n), but the constant factor on this O(n) will be
        // much smaller than the one where we fetch `uniqueIdsAndRowIds` (which we
        // do just as often as we invoked this method (from a big-O perspective)).
        // In the future, we should support proper paging on this view, but for
        // now, this is probably faster than what we had before.
        switch filter {
        case .newest:
            return Array(uniqueIdsAndRowIds.lazy.suffix(limit).map { $0.uniqueId })
        case .before(let rowId):
            return Array(uniqueIdsAndRowIds.lazy.filter { $0.rowId < rowId }.suffix(limit).map { $0.uniqueId })
        case .after(let rowId):
            return Array(uniqueIdsAndRowIds.lazy.filter { $0.rowId > rowId }.prefix(limit).map { $0.uniqueId })
        case .range(let rowIds):
            return Array(uniqueIdsAndRowIds.lazy.filter { rowIds.contains($0.rowId) }.prefix(limit).map { $0.uniqueId })
        }
    }
}
