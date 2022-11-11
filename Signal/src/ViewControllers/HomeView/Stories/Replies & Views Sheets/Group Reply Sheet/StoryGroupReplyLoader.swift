//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalMessaging

class StoryGroupReplyLoader: Dependencies {
    private let loadingLock = UnfairLock()
    private var messageMapping: CVMessageMapping!
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

    var oldestLoadedRow: Int? {
        let loadedInteractions = loadingLock.withLock { messageMapping.loadedInteractions }
        guard let uniqueId = loadedInteractions.first?.uniqueId else { return nil }
        return replyUniqueIds.firstIndex(of: uniqueId)
    }

    var newestLoadedRow: Int? {
        let loadedInteractions = loadingLock.withLock { messageMapping.loadedInteractions }
        guard let uniqueId = loadedInteractions.last?.uniqueId else { return nil }
        return replyUniqueIds.firstIndex(of: uniqueId)
    }

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

        // Load the first page synchronously.
        databaseStorage.read { transaction in
            messageMapping = CVMessageMapping(
                threadUniqueId: threadUniqueId,
                storyReplyQueryMode: .onlyGroupReplies(storyTimestamp: storyMessage.timestamp)
            )

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
            guard self.loadingLock.withLock({ self.messageMapping.canLoadNewer }) else { return }
            self.databaseStorage.read { self.load(mode: .newer, transaction: $0) }
        }
    }

    func loadOlderPageIfNecessary() {
        LoadingMode.older.async {
            guard self.loadingLock.withLock({ self.messageMapping.canLoadOlder }) else { return }
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
            let loadedInteractions = loadingLock.withLock { messageMapping.loadedInteractions }
            reusableInteractions = loadedInteractions.reduce(
                into: [String: TSInteraction]()
            ) { partialResult, interaction in
                guard updatedInteractionIds?.contains(interaction.uniqueId) != true else { return }
                partialResult[interaction.uniqueId] = interaction
            }
        } else {
            reusableInteractions = [:]
        }

        loadingLock.withLock {
            do {
                switch mode {
                case .initial:
                    try self.messageMapping.loadInitialMessagePage(
                        focusMessageId: nil,
                        reusableInteractions: reusableInteractions,
                        deletedInteractionIds: deletedInteractionIds,
                        transaction: transaction
                    )
                case .newer:
                    try self.messageMapping.loadNewerMessagePage(
                        reusableInteractions: reusableInteractions,
                        deletedInteractionIds: deletedInteractionIds,
                        transaction: transaction
                    )
                case .older:
                    try self.messageMapping.loadOlderMessagePage(
                        reusableInteractions: reusableInteractions,
                        deletedInteractionIds: deletedInteractionIds,
                        transaction: transaction
                    )
                case .reload:
                    try self.messageMapping.loadSameLocation(
                        reusableInteractions: reusableInteractions,
                        deletedInteractionIds: deletedInteractionIds,
                        transaction: transaction
                    )
                }
            } catch {
                owsFailDebug("Load failed for mode \(mode): \(error)")
                return
            }
        }

        let newReplyItems = buildItems(reusableInteractionIds: Array(reusableInteractions.keys), transaction: transaction)
        let replyUniqueIds = InteractionFinder.groupReplyUniqueIds(for: self.storyMessage, transaction: transaction)

        DispatchQueue.main.async {
            let wasScrolledToBottom = self.isScrolledToBottom

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

        let loadedInteractions = loadingLock.withLock { messageMapping.loadedInteractions }

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
