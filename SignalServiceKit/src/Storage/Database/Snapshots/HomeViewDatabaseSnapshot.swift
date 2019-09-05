//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public protocol HomeViewDatabaseSnapshotDelegate: AnyObject {
    func homeViewDatabaseSnapshotWillUpdate()
    func homeViewDatabaseSnapshotDidUpdate(updatedThreadIds: Set<String>)
    func homeViewDatabaseSnapshotDidUpdateExternally()
    func homeViewDatabaseSnapshotDidReset()
}

@objc
public class HomeViewDatabaseObserver: NSObject {

    private var _snapshotDelegates: [Weak<HomeViewDatabaseSnapshotDelegate>] = []
    private var snapshotDelegates: [HomeViewDatabaseSnapshotDelegate] {
        AssertIsOnMainThread()
        return _snapshotDelegates.compactMap { $0.value }
    }

    @objc
    public func appendSnapshotDelegate(_ snapshotDelegate: HomeViewDatabaseSnapshotDelegate) {
        AssertIsOnMainThread()
        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
    }

    private typealias RowId = Int64
    private struct CollectionChanges {
        var rowIds: Set<RowId> = Set()
        var uniqueIds: Set<String> = Set()
    }
    private var _pendingThreadChanges = CollectionChanges()
    private var pendingThreadChanges: CollectionChanges {
        get {
            AssertIsOnUIDatabaseObserverSerialQueue()
            return _pendingThreadChanges
        }
        set {
            AssertIsOnUIDatabaseObserverSerialQueue()
            _pendingThreadChanges = newValue
        }
    }

    private typealias ThreadUniqueId = String
    private var _committedThreadChanges: Set<ThreadUniqueId>?
    private var committedThreadChanges: Set<ThreadUniqueId>? {
        get {
            AssertIsOnMainThread()
            return _committedThreadChanges
        }

        set {
            AssertIsOnMainThread()
            _committedThreadChanges = newValue
        }
    }

    private func threadUniqueIds(forChanges changes: CollectionChanges, db: Database) throws -> Set<String> {
        guard changes.rowIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        guard changes.uniqueIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        guard changes.rowIds.count > 0 else {
            return changes.uniqueIds
        }

        let commaSeparatedRowIds = changes.rowIds.map { String($0) }.joined(separator: ", ")
        let rowIdsSQL = "(\(commaSeparatedRowIds))"

        let sql = """
        SELECT \(threadColumn: .uniqueId)
        FROM \(ThreadRecord.databaseTableName)
        WHERE rowid IN \(rowIdsSQL)
        """

        let fetchedUniqueIds = try String.fetchAll(db, sql: sql)
        let result = changes.uniqueIds.union(fetchedUniqueIds)

        guard result.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        return result
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(thread: TSThread, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()
        let rowId = RowId(thread.rowId)
        pendingThreadChanges.rowIds.insert(rowId)
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(threadId: String, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()
        pendingThreadChanges.uniqueIds.insert(threadId)
    }
}

extension HomeViewDatabaseObserver: DatabaseSnapshotDelegate {

    // MARK: - Transaction Lifecycle

    public func snapshotTransactionDidChange(with event: DatabaseEvent) {
        AssertIsOnUIDatabaseObserverSerialQueue()
        if event.tableName == ThreadRecord.databaseTableName {
            _ = pendingThreadChanges.rowIds.insert(event.rowID)
        }
    }

    public func snapshotTransactionDidCommit(db: Database) {
        AssertIsOnUIDatabaseObserverSerialQueue()
        do {
            let pendingThreadChanges = self.pendingThreadChanges
            self.pendingThreadChanges = CollectionChanges()

            let committedThreadChanges = try threadUniqueIds(forChanges: pendingThreadChanges, db: db)
            DispatchQueue.main.async {
                self.committedThreadChanges = committedThreadChanges
            }
        } catch {
            DispatchQueue.main.async {
                self.committedThreadChanges = nil
            }
        }
    }

    public func snapshotTransactionDidRollback(db: Database) {
        owsFailDebug("test this if we ever use it")
        AssertIsOnUIDatabaseObserverSerialQueue()
        pendingThreadChanges = CollectionChanges()
    }

    // MARK: - Snapshot LifeCycle (Post Commit)

    public func databaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
        for delegate in snapshotDelegates {
            delegate.homeViewDatabaseSnapshotWillUpdate()
        }
    }

    public func databaseSnapshotDidUpdate() {
        AssertIsOnMainThread()
        do {
            guard let commitedThreadChanges = self.committedThreadChanges else {
                throw OWSErrorMakeAssertionError("committedThreadChanges was unexpectedly nil")
            }
            self.committedThreadChanges = nil

            for delegate in snapshotDelegates {
                delegate.homeViewDatabaseSnapshotDidUpdate(updatedThreadIds: commitedThreadChanges)
            }
        } catch DatabaseObserverError.changeTooLarge {
            for delegate in snapshotDelegates {
                delegate.homeViewDatabaseSnapshotDidReset()
            }
        } catch {
            owsFailDebug("unknown error: \(error)")
            for delegate in snapshotDelegates {
                delegate.homeViewDatabaseSnapshotDidReset()
            }
        }
    }

    public func databaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        for delegate in snapshotDelegates {
            delegate.homeViewDatabaseSnapshotDidUpdateExternally()
        }
    }
}
