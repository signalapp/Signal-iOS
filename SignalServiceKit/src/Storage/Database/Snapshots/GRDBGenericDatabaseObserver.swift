//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

@objc
public protocol GRDBGenericDatabaseObserverDelegate: AnyObject {
    func genericDatabaseSnapshotWillUpdate()
    func genericDatabaseSnapshotDidUpdate(updatedCollections: Set<String>,
                                          updatedInteractionIds: Set<String>)
    func genericDatabaseSnapshotDidUpdateExternally()
    func genericDatabaseSnapshotDidReset()
}

// MARK: -

@objc
public class GRDBGenericDatabaseObserver: NSObject {

    private var _snapshotDelegates: [Weak<GRDBGenericDatabaseObserverDelegate>] = []
    private var snapshotDelegates: [GRDBGenericDatabaseObserverDelegate] {
        AssertIsOnMainThread()

        return _snapshotDelegates.compactMap { $0.value }
    }

    @objc
    public func appendSnapshotDelegate(_ snapshotDelegate: GRDBGenericDatabaseObserverDelegate) {
        AssertIsOnMainThread()

        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
    }

    private struct PendingChanges {
        var collections: Set<String> = Set()
        var tableNames: Set<String> = Set()
        var interactionIds: Set<String> = Set()
        var interactionRowIds: Set<Int64> = Set()
    }
    private var _pendingChanges = PendingChanges()
    private var pendingChanges: PendingChanges {
        get {
            AssertIsOnUIDatabaseObserverSerialQueue()

            return _pendingChanges
        }
        set {
            AssertIsOnUIDatabaseObserverSerialQueue()

            _pendingChanges = newValue
        }
    }

    private struct CommittedChanges {
        let collections: Set<String>
        let interactionIds: Set<String>

        init(collections: Set<String>,
             interactionIds: Set<String>) {
            self.collections = collections
            self.interactionIds = interactionIds
        }
    }
    private typealias CollectionName = String
    private var _committedChanges: CommittedChanges?
    private var committedChanges: CommittedChanges? {
        get {
            AssertIsOnMainThread()

            return _committedChanges
        }

        set {
            AssertIsOnMainThread()

            _committedChanges = newValue
        }
    }

    private lazy var tableNameToCollectionMap: [String: String] = {
        var result = [String: String]()
        for table in GRDBDatabaseStorageAdapter.tables {
            result[table.tableName] = table.collection
        }
        return result
    }()

    private func committedChanges(forPendingChanges pendingChanges: PendingChanges, db: Database) throws -> CommittedChanges {
        return CommittedChanges(collections: collections(forPendingChanges: pendingChanges, db: db),
                                interactionIds: try interactionIds(forPendingChanges: pendingChanges, db: db))
    }

    private func collections(forPendingChanges pendingChanges: PendingChanges, db: Database) -> Set<String> {
        guard pendingChanges.tableNames.count > 0 else {
            return pendingChanges.collections
        }

        // If necessary, convert GRDB table names to "collections".
        var allCollections = pendingChanges.collections
        for tableName in pendingChanges.tableNames {
            guard !tableName.hasPrefix(GRDBFullTextSearchFinder.databaseTableName) else {
                // Ignore updates to the GRDB FTS table(s).
                continue
            }
            guard let collection = self.tableNameToCollectionMap[tableName] else {
                owsFailDebug("Unknown table: \(tableName)")
                continue
            }
            allCollections.insert(collection)
        }
        return allCollections
    }

    private func interactionIds(forPendingChanges pendingChanges: PendingChanges, db: Database) throws -> Set<String> {
        let updatedRowIds = pendingChanges.interactionRowIds
        guard updatedRowIds.count > 0 else {
            return pendingChanges.interactionIds
        }

        // If necessary, convert GRDB rowIds to interaction ids.
        guard updatedRowIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            owsFailDebug("Too many updatedRowIds for incremental update.")
            throw DatabaseObserverError.changeTooLarge
        }

        let commaSeparatedRowIds = updatedRowIds.map { String($0) }.joined(separator: ", ")
        let rowIdsSQL = "(\(commaSeparatedRowIds))"
        let sql = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE rowid IN \(rowIdsSQL)
        """

        let convertedIds = try String.fetchAll(db, sql: sql, arguments: [])
        assert(convertedIds.count == updatedRowIds.count)
        return Set(convertedIds).union(pendingChanges.interactionIds)
    }

    @objc
    public func touchThread(transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.

        UIDatabaseObserver.serializedSync {
            pendingChanges.tableNames.insert(TSThread.table.tableName)
        }
    }

    @objc
    public func touchInteraction(interactionId: String, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.

        UIDatabaseObserver.serializedSync {
            pendingChanges.interactionIds.insert(interactionId)

            pendingChanges.tableNames.insert(TSInteraction.table.tableName)
        }
    }
}

// MARK: -

extension GRDBGenericDatabaseObserver: TransactionObserver {

    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        // Observe everything.
        return true
    }

    public func databaseDidChange(with event: DatabaseEvent) {
        UIDatabaseObserver.serializedSync {
            _ = pendingChanges.tableNames.insert(event.tableName)

            if event.tableName == InteractionRecord.databaseTableName {
                _ = pendingChanges.interactionRowIds.insert(event.rowID)
            }
        }
    }

    public func databaseDidCommit(_ db: Database) {
        // no - op

        // Although this class is a TransactionObserver, it is also a delegate
        // (DatabaseSnapshotDelegate) of another TransactionObserver, the UIDatabaseObserver.
        //
        // We use our own TransactionObserver methods to collect details about the changes,
        // but we wait for the UIDatabaseObserver's TransactionObserver methods to inform our own
        // delegate of these details in sync with when the UI DB Snapshot is updated
        // (via DatabaseSnapshotDelegate).
    }

    public func databaseDidRollback(_ db: Database) {
        owsFailDebug("test this if we ever use it")

        UIDatabaseObserver.serializedSync {
            pendingChanges = PendingChanges()
        }
    }
}

// MARK: -

extension GRDBGenericDatabaseObserver: DatabaseSnapshotDelegate {
    public func databaseSnapshotSourceDidCommit(db: Database) {
        AssertIsOnUIDatabaseObserverSerialQueue()

        do {
            let pendingChanges = self.pendingChanges
            self.pendingChanges = PendingChanges()

            let committedChanges = try self.committedChanges(forPendingChanges: pendingChanges, db: db)
            DispatchQueue.main.async {
                self.committedChanges = committedChanges
            }
        } catch {
            DispatchQueue.main.async {
                self.committedChanges = nil
            }
        }
    }

    public func databaseSnapshotWillUpdate() {
        AssertIsOnMainThread()

        for delegate in snapshotDelegates {
            delegate.genericDatabaseSnapshotWillUpdate()
        }
    }

    public func databaseSnapshotDidUpdate() {
        AssertIsOnMainThread()

        do {
            guard let committedChanges = self.committedChanges else {
                throw OWSErrorMakeAssertionError("committedChanges was unexpectedly nil")
            }
            self.committedChanges = nil

            for delegate in snapshotDelegates {
                delegate.genericDatabaseSnapshotDidUpdate(updatedCollections: committedChanges.collections,
                                                          updatedInteractionIds: committedChanges.interactionIds)
            }
        } catch {
            owsFailDebug("unknown error: \(error)")
            for delegate in snapshotDelegates {
                delegate.genericDatabaseSnapshotDidReset()
            }
        }
    }

    public func databaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()

        for delegate in snapshotDelegates {
            delegate.genericDatabaseSnapshotDidUpdateExternally()
        }
    }
}
