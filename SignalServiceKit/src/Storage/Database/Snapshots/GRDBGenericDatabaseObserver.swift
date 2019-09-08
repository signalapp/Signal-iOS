//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public protocol GRDBGenericDatabaseObserverDelegate: AnyObject {
    func genericDatabaseSnapshotWillUpdate()
    func genericDatabaseSnapshotDidUpdate(updatedCollections: Set<String>,
                                          updatedInteractionIds: Set<Int64>)
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
        var interactionIds: Set<Int64> = Set()
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
        let interactionIds: Set<Int64>
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
                                interactionIds: pendingChanges.interactionIds)
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

    private typealias RowId = Int64

    // internal - should only be called by DatabaseStorage
    func didTouchThread(transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()
        pendingChanges.tableNames.insert(TSThread.table.tableName)
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()
        let rowId = RowId(interaction.sortId)
        pendingChanges.interactionIds.insert(rowId)
        pendingChanges.tableNames.insert(TSInteraction.table.tableName)
    }
}

// MARK: -

extension GRDBGenericDatabaseObserver: DatabaseSnapshotDelegate {

    // MARK: - Transaction Lifecycle

    public func snapshotTransactionDidChange(with event: DatabaseEvent) {
        AssertIsOnUIDatabaseObserverSerialQueue()

        _ = pendingChanges.tableNames.insert(event.tableName)

        if event.tableName == InteractionRecord.databaseTableName {
            _ = pendingChanges.interactionIds.insert(event.rowID)
        }
    }

    public func snapshotTransactionDidCommit(db: Database) {
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

    public func snapshotTransactionDidRollback(db: Database) {
        owsFailDebug("test this if we ever use it")
        AssertIsOnUIDatabaseObserverSerialQueue()
        pendingChanges = PendingChanges()
    }

    // MARK: - Snapshot LifeCycle (Post Commit)

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
