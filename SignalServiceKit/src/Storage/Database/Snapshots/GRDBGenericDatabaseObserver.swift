//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public protocol GRDBGenericDatabaseObserverDelegate: AnyObject {
    func genericDatabaseSnapshotWillUpdate()
    func genericDatabaseSnapshotDidUpdate(updatedCollections: Set<String>,
                                          updatedInteractionRowIds: Set<Int64>)
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

    fileprivate typealias RowId = Int64
    fileprivate var pendingChanges = ObservedDatabaseChanges<RowId>(concurrencyMode: .uiDatabaseObserverSerialQueue)
    fileprivate var committedChanges = ObservedDatabaseChanges<RowId>(concurrencyMode: .mainThread)

    private static var tableNameToCollectionMap: [String: String] = {
        var result = [String: String]()
        for table in GRDBDatabaseStorageAdapter.tables {
            result[table.tableName] = table.collection
        }
        result[SDSKeyValueStore.tableName] = SDSKeyValueStore.dataStoreCollection
        return result
    }()

    private class func committedCollectionsForPendingChanges(pendingChanges: ObservedDatabaseChanges<RowId>,
                                                             db: Database) -> Set<String> {
        let tableNames = pendingChanges.tableNames
        let collections = pendingChanges.collections
        guard tableNames.count > 0 else {
            return collections
        }

        // If necessary, convert GRDB table names to "collections".
        var allCollections = collections
        for tableName in tableNames {
            guard !tableName.hasPrefix(GRDBFullTextSearchFinder.contentTableName) else {
                owsFailDebug("should not have been notified for changes to FTS tables")
                continue
            }
            guard let collection = tableNameToCollectionMap[tableName] else {
                owsFailDebug("Unknown table: \(tableName)")
                continue
            }
            allCollections.insert(collection)
        }
        return allCollections
    }

    // internal - should only be called by DatabaseStorage
    func didTouchThread(transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()
        pendingChanges.append(tableName: TSThread.table.tableName)
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
        pendingChanges.append(tableName: TSInteraction.table.tableName)
    }
}

// MARK: -

extension GRDBGenericDatabaseObserver: DatabaseSnapshotDelegate {

    // MARK: - Transaction Lifecycle

    public func snapshotTransactionDidChange(with event: DatabaseEvent) {
        AssertIsOnUIDatabaseObserverSerialQueue()

        pendingChanges.append(tableName: event.tableName)

        if event.tableName == InteractionRecord.databaseTableName {
            pendingChanges.append(interactionChange: event.rowID)
        }
    }

    public func snapshotTransactionDidCommit(db: Database) {
        AssertIsOnUIDatabaseObserverSerialQueue()

        let interactionChanges = pendingChanges.interactionChanges
        let collections = Self.committedCollectionsForPendingChanges(pendingChanges: pendingChanges, db: db)
        pendingChanges.reset()

        DispatchQueue.main.async {
            self.committedChanges.append(interactionChanges: interactionChanges)
            self.committedChanges.append(collections: collections)
        }
    }

    public func snapshotTransactionDidRollback(db: Database) {
        owsFailDebug("test this if we ever use it")
        AssertIsOnUIDatabaseObserverSerialQueue()
        pendingChanges.reset()
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

        defer {
            committedChanges.reset()
        }

        // We don't yet use lastError in this snapshot, but we might eventually.
        if let error = self.committedChanges.lastError {
            owsFailDebug("unknown error: \(error)")
            for delegate in snapshotDelegates {
                delegate.genericDatabaseSnapshotDidReset()
            }
            return
        }

        let collections = committedChanges.collections
        let interactionChanges = committedChanges.interactionChanges

        for delegate in snapshotDelegates {
            delegate.genericDatabaseSnapshotDidUpdate(updatedCollections: collections,
                                                      updatedInteractionRowIds: interactionChanges)
        }
    }

    public func databaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()

        for delegate in snapshotDelegates {
            delegate.genericDatabaseSnapshotDidUpdateExternally()
        }
    }
}
