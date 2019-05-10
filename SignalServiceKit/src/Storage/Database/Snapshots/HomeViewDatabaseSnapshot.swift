//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

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
    private var _pendingThreadChanges: Set<RowId> = Set()
    private var pendingThreadChanges: Set<RowId> {
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

    private func threadUniqueIds(forRowIds rowIds: Set<RowId>, db: Database) throws -> Set<String> {
        guard rowIds.count > 0 else {
            return Set()
        }

        guard rowIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        let commaSeparatedRowIds = rowIds.map { String($0) }.joined(separator: ", ")
        let rowIdsSQL = "(\(commaSeparatedRowIds))"

        let sql = """
        SELECT \(columnForThread: .uniqueId)
        FROM \(ThreadRecord.databaseTableName)
        WHERE rowid IN \(rowIdsSQL)
        """

        let threadUniqueIds = try String.fetchAll(db, sql: sql)
        return Set(threadUniqueIds)
    }
}

extension HomeViewDatabaseObserver: TransactionObserver {

    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        return eventKind.tableName == ThreadRecord.databaseTableName
    }

    public func databaseDidChange(with event: DatabaseEvent) {
        Logger.verbose("")
        UIDatabaseObserver.serialQueue.sync {
            _ = pendingThreadChanges.insert(event.rowID)
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
        UIDatabaseObserver.serialQueue.sync {
            pendingThreadChanges = Set()
        }
    }
}

extension HomeViewDatabaseObserver: DatabaseSnapshotDelegate {
    public func databaseSnapshotSourceDidCommit(db: Database) {
        AssertIsOnUIDatabaseObserverSerialQueue()
        do {
            let pendingThreadChanges = self.pendingThreadChanges
            self.pendingThreadChanges = Set()

            let committedThreadChanges = try threadUniqueIds(forRowIds: pendingThreadChanges, db: db)
            DispatchQueue.main.async {
                self.committedThreadChanges = committedThreadChanges
            }
        } catch {
            DispatchQueue.main.async {
                self.committedThreadChanges = nil
            }
        }
    }

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
