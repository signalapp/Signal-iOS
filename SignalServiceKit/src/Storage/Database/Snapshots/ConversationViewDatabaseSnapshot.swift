//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public protocol ConversationViewDatabaseSnapshotDelegate: AnyObject {
    func conversationViewDatabaseSnapshotWillUpdate()
    func conversationViewDatabaseSnapshotDidUpdate(transactionChanges: ConversationViewDatabaseTransactionChanges)
    func conversationViewDatabaseSnapshotDidUpdateExternally()
    func conversationViewDatabaseSnapshotDidReset()
}

@objc
public class ConversationViewDatabaseObserver: NSObject {

    private var _snapshotDelegates: [Weak<ConversationViewDatabaseSnapshotDelegate>] = []
    private var snapshotDelegates: [ConversationViewDatabaseSnapshotDelegate] {
        return _snapshotDelegates.compactMap { $0.value }
    }

    @objc
    public func appendSnapshotDelegate(_ snapshotDelegate: ConversationViewDatabaseSnapshotDelegate) {
        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()
        let rowId = RowId(interaction.sortId)
        assert(rowId > 0)
        pendingChanges.append(interactionChange: rowId)

        let interactionThread: TSThread? = interaction.thread(transaction: transaction.asAnyRead)
        if let thread = interactionThread {
            didTouch(thread: thread, transaction: transaction)
        } else {
            owsFailDebug("Could not load thread for interaction.")
        }
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(thread: TSThread, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()

        guard let grdbId = thread.grdbId else {
            owsFailDebug("Missing grdbId.")
            return
        }

        pendingChanges.append(threadChange: grdbId.int64Value)
    }

    fileprivate typealias RowId = Int64
    fileprivate var pendingChanges = ObservedDatabaseChanges<RowId>(concurrencyMode: .uiDatabaseObserverSerialQueue)
    fileprivate var committedChanges = ObservedDatabaseChanges<RowId>(concurrencyMode: .mainThread)
}

// MARK: -

@objc
public class ConversationViewDatabaseTransactionChanges: NSObject {
    private let updatedRowIds: Set<Int64>
    private let updatedThreadIds: Set<Int64>

    init(updatedRowIds: Set<Int64>, updatedThreadIds: Set<Int64>) throws {
        guard updatedRowIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        self.updatedRowIds = updatedRowIds
        self.updatedThreadIds = updatedThreadIds
    }

    @objc
    public func updatedInteractionIds(forThreadId threadUniqueId: String, transaction: GRDBReadTransaction) throws -> Set<String> {
        guard updatedRowIds.count > 0 else {
            return Set()
        }

        guard updatedRowIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            owsFailDebug("updatedRowIds count should be enforced in initializer")
            throw DatabaseObserverError.changeTooLarge
        }

        let commaSeparatedRowIds = updatedRowIds.map { String($0) }.joined(separator: ", ")
        let rowIdsSQL = "(\(commaSeparatedRowIds))"
        // GRDB TODO: I don't think we need to filter by threadUniqueId here.
        let sql = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE rowid IN \(rowIdsSQL)
        AND \(interactionColumn: .threadUniqueId) = ?
        """

        let uniqueIds = try String.fetchAll(transaction.database, sql: sql, arguments: [threadUniqueId])

        return Set(uniqueIds)
    }

    @objc(containsThreadRowId:)
    public func contains(threadRowId: NSNumber) -> Bool {
        return updatedThreadIds.contains(threadRowId.int64Value)
    }
}

extension ConversationViewDatabaseObserver: DatabaseSnapshotDelegate {

    // MARK: - Transaction LifeCycle

    public func snapshotTransactionDidChange(with event: DatabaseEvent) {
        Logger.verbose("")
        AssertIsOnUIDatabaseObserverSerialQueue()
        if event.tableName == InteractionRecord.databaseTableName {
            pendingChanges.append(interactionChange: event.rowID)
        } else if event.tableName == ThreadRecord.databaseTableName {
            pendingChanges.append(threadChange: event.rowID)
        }
    }

    public func snapshotTransactionDidCommit(db: Database) {
        AssertIsOnUIDatabaseObserverSerialQueue()

        let interactionChanges = pendingChanges.interactionChanges
        let threadChanges = pendingChanges.threadChanges
        pendingChanges.reset()

        DispatchQueue.main.async {
            self.committedChanges.append(interactionChanges: interactionChanges)
            self.committedChanges.append(threadChanges: threadChanges)
        }
    }

    public func snapshotTransactionDidRollback(db: Database) {
        owsFailDebug("we should verify this works if we ever start to use rollbacks")
        AssertIsOnUIDatabaseObserverSerialQueue()

        pendingChanges.reset()
    }

    // MARK: - Snapshot LifeCycle (Post Commit)

    public func databaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
        for delegate in snapshotDelegates {
            delegate.conversationViewDatabaseSnapshotWillUpdate()
        }
    }

    public func databaseSnapshotDidUpdate() {
        AssertIsOnMainThread()

        defer {
            self.committedChanges.reset()
        }

        // We don't yet use lastError in this snapshot, but we might eventually.
        if let error = self.committedChanges.lastError {
            owsFailDebug("unknown error: \(error)")
            for delegate in snapshotDelegates {
                delegate.conversationViewDatabaseSnapshotDidReset()
            }
            return
        }

        do {
            let interactionChanges = self.committedChanges.interactionChanges
            let threadChanges = self.committedChanges.threadChanges

            let transactionChanges = try ConversationViewDatabaseTransactionChanges(updatedRowIds: interactionChanges,
                                                                                    updatedThreadIds: threadChanges)
            for delegate in snapshotDelegates {
                delegate.conversationViewDatabaseSnapshotDidUpdate(transactionChanges: transactionChanges)
            }
        } catch DatabaseObserverError.changeTooLarge {
            for delegate in snapshotDelegates {
                delegate.conversationViewDatabaseSnapshotDidReset()
            }
        } catch {
            owsFailDebug("unknown error: \(error)")
            for delegate in snapshotDelegates {
                delegate.conversationViewDatabaseSnapshotDidReset()
            }
        }
    }

    public func databaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        for delegate in snapshotDelegates {
            delegate.conversationViewDatabaseSnapshotDidUpdateExternally()
        }
    }
}
