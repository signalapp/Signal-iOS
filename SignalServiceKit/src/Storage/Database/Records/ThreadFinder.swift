//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public protocol ThreadFinder {
    associatedtype ReadTransaction

    func visibleThreadCount(isArchived: Bool, transaction: ReadTransaction) throws -> UInt
    func enumerateVisibleThreads(isArchived: Bool, transaction: ReadTransaction, block: @escaping (TSThread) -> Void) throws
    func visibleThreadIds(isArchived: Bool, transaction: ReadTransaction) throws -> [String]
    func sortIndex(thread: TSThread, transaction: ReadTransaction) throws -> UInt?
    func threads(withThreadIds threadIds: Set<String>, transaction: ReadTransaction) throws -> Set<TSThread>
}

@objc
public class AnyThreadFinder: NSObject, ThreadFinder {
    public typealias ReadTransaction = SDSAnyReadTransaction

    let grdbAdapter: GRDBThreadFinder = GRDBThreadFinder()

    public func visibleThreadCount(isArchived: Bool, transaction: SDSAnyReadTransaction) throws -> UInt {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.visibleThreadCount(isArchived: isArchived, transaction: grdb)
        }
    }

    @objc
    public func enumerateVisibleThreads(isArchived: Bool, transaction: SDSAnyReadTransaction, block: @escaping (TSThread) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            try grdbAdapter.enumerateVisibleThreads(isArchived: isArchived, transaction: grdb, block: block)
        }
    }

    @objc
    public func visibleThreadIds(isArchived: Bool, transaction: SDSAnyReadTransaction) throws -> [String] {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.visibleThreadIds(isArchived: isArchived, transaction: grdb)
        }
    }

    @objc
    public func sortIndexObjc(thread: TSThread, transaction: ReadTransaction) -> NSNumber? {
        do {
            guard let value = try sortIndex(thread: thread, transaction: transaction) else {
                return nil
            }
            return NSNumber(value: value)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    public func sortIndex(thread: TSThread, transaction: SDSAnyReadTransaction) throws -> UInt? {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.sortIndex(thread: thread, transaction: grdb)
        }
    }

    public func threads(withThreadIds threadIds: Set<String>, transaction: SDSAnyReadTransaction) throws -> Set<TSThread> {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.threads(withThreadIds: threadIds, transaction: grdb)
        }
    }
}

// MARK: -

@objc
public class GRDBThreadFinder: NSObject, ThreadFinder {

    public typealias ReadTransaction = GRDBReadTransaction

    static let cn = ThreadRecord.columnName

    public func visibleThreadCount(isArchived: Bool, transaction: GRDBReadTransaction) throws -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
        """

        guard let count = try UInt.fetchOne(transaction.database, sql: sql) else {
            owsFailDebug("count was unexpectedly nil")
            return 0
        }

        return count
    }

    @objc
    public func enumerateVisibleThreads(isArchived: Bool, transaction: GRDBReadTransaction, block: @escaping (TSThread) -> Void) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            """

        try ThreadRecord.fetchCursor(transaction.database, sql: sql).forEach { threadRecord in
            block(try TSThread.fromRecord(threadRecord))
        }
    }

    private func archivedJoin(isArchived: Bool) -> String {
        return """
            INNER JOIN \(ThreadAssociatedData.databaseTableName) AS ad
                ON ad.threadUniqueId = \(threadColumn: .uniqueId)
            WHERE ad.isArchived = \(isArchived ? "1" : "0")
        """
    }

    @objc
    public func visibleThreadIds(isArchived: Bool, transaction: GRDBReadTransaction) throws -> [String] {
        let sql = """
            SELECT \(threadColumn: .uniqueId)
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
        """
        return try String.fetchAll(transaction.database, sql: sql)
    }

    public func sortIndex(thread: TSThread, transaction: GRDBReadTransaction) throws -> UInt? {
        let sql = """
        SELECT sortIndex
        FROM (
            SELECT
                (ROW_NUMBER() OVER (ORDER BY \(threadColumn: .lastInteractionRowId) DESC) - 1) as sortIndex,
                \(threadColumn: .id)
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
        )
        WHERE \(threadColumn: .id) = ?
        """
        guard let grdbId = thread.grdbId, grdbId.intValue > 0 else {
            throw OWSAssertionError("grdbId was unexpectedly nil")
        }

        let arguments: StatementArguments = [grdbId.intValue]
        return try UInt.fetchOne(transaction.database, sql: sql, arguments: arguments)
    }

    @objc
    public class func isPreMessageRequestsThread(_ thread: TSThread, transaction: GRDBReadTransaction) -> Bool {
        guard !RemoteConfig.profilesForAll else { return false }

        // Grandfather legacy threads where you haven't shared your profile.
        guard !thread.isNoteToSelf else { return false }

        let interactionFinder = GRDBInteractionFinder(threadUniqueId: thread.uniqueId)

        // We don't want to show message requests for threads that existed before we
        // enabled the feature. In order to make sure this is the case, we record
        // the max row id from the interactions table when the feature is turned on.
        // If the current thread contains messages that are earlier than that id,
        // we don't show the message request.
        if let messageRequestInteractionIdEpoch = SSKPreferences.messageRequestInteractionIdEpoch(transaction: transaction),
            let earliestKnownInteractionId = interactionFinder.earliestKnownInteractionRowId(transaction: transaction),
            earliestKnownInteractionId <= messageRequestInteractionIdEpoch {
            return true
        }

        // It's possible we pass the above check for a legacy thread, for example if
        // you have a strict disappearing message timer enabled that deletes all the
        // messages before the epoch. As an additional safe guard, we treat the thread
        // as pre-message requests if you've ever sent an outgoing message AND you have
        // not shared your profile since that shouldn't be possible in a message request
        // world.
        let hasSentMessages = interactionFinder.existsOutgoingMessage(transaction: transaction)

        let threadIsWhitelisted = Self.profileManager.isThread(
            inProfileWhitelist: thread,
            transaction: transaction.asAnyRead
        )

        return hasSentMessages && !threadIsWhitelisted
    }

    @objc
    public class func hasPendingMessageRequest(thread: TSThread, transaction: GRDBReadTransaction) -> Bool {

        // TODO: Should we consult isRequestingMember() here?
        if let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread,
            groupThread.isLocalUserInvitedMember {
            return true
        }

        // If we're creating the thread, don't show the message request view
        guard thread.shouldThreadBeVisible else { return false }

        // If this thread is blocked AND we're still in the thread, show the message
        // request view regardless of if we have sent messages or not.
        if blockingManager.isThreadBlocked(thread) { return true }

        let isGroupThread = thread is TSGroupThread
        let isLocalUserInGroup = (thread as? TSGroupThread)?.isLocalUserFullOrInvitedMember == true

        // If this is a group thread and we're not a member, never show the message request.
        if isGroupThread, !isLocalUserInGroup { return false }

        // If the thread is already whitelisted, do nothing. The user has already
        // accepted the request for this thread.
        guard !Self.profileManager.isThread(
            inProfileWhitelist: thread,
            transaction: transaction.asAnyRead
        ) else { return false }

        // If this thread is from before we supported message requests,
        // don't show the message request view.
        guard !isPreMessageRequestsThread(thread, transaction: transaction) else { return false }

        let interactionFinder = GRDBInteractionFinder(threadUniqueId: thread.uniqueId)

        if isGroupThread {
            // At this point, we know this is an un-whitelisted group thread.
            // If someone added us to the group, there will be a group update info message
            // in which case we want to show a pending message request. If the thread
            // is otherwise empty, we don't want to show the message request.
            if interactionFinder.hasGroupUpdateInfoMessage(transaction: transaction) { return true }
        }

        // This thread is likely only visible because of system messages like so-and-so
        // is on signal or sync status. Some of the "possibly" incoming messages might
        // actually have been triggered by us, but if we sent one of these then the thread
        // should be in our profile white list and not make it to this check.
        guard interactionFinder.possiblyHasIncomingMessages(transaction: transaction) else { return false }

        return true
    }

    @objc
    public class func shouldSetDefaultDisappearingMessageTimer(
        thread: TSThread,
        transaction: GRDBReadTransaction
    ) -> Bool {
        guard FeatureFlags.universalDisappearingMessages else { return false }

        // We never set the default timer for group threads. Group thread timers
        // are set during group creation.
        guard !thread.isGroupThread else { return false }

        // Make sure the universal timer is enabled.
        guard OWSDisappearingMessagesConfiguration.fetchOrBuildDefaultUniversalConfiguration(
            with: transaction.asAnyRead
        ).isEnabled else {
            return false
        }

        // Make sure there the current timer is disabled.
        guard !thread.disappearingMessagesConfiguration(with: transaction.asAnyRead).isEnabled else {
            return false
        }

        // Make sure there has been no user initiated interactions.
        return !GRDBInteractionFinder(threadUniqueId: thread.uniqueId)
            .hasUserInitiatedInteraction(transaction: transaction)
    }

    @objc
    public func threads(withThreadIds threadIds: Set<String>, transaction: GRDBReadTransaction) throws -> Set<TSThread> {
        guard !threadIds.isEmpty else {
            return []
        }

        let sql = """
        SELECT * FROM \(ThreadRecord.databaseTableName)
        WHERE \(threadColumn: .uniqueId) IN (\(threadIds.map { "\'\($0)'" }.joined(separator: ",")))
        """
        let arguments: StatementArguments = []
        let cursor = TSThread.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction)
        var threads = Set<TSThread>()
        while let thread = try cursor.next() {
            threads.insert(thread)
        }
        return threads
    }

    @objc
    public class func existsGroupThread(transaction: GRDBReadTransaction) -> Bool {
        let sql = """
        SELECT EXISTS(
            SELECT 1
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .recordType) = ?
            LIMIT 1
        )
        """
        let arguments: StatementArguments = [SDSRecordType.groupThread.rawValue]
        return try! Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
    }
}
