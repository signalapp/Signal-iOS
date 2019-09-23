//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

/// Anything 
public protocol DatabaseSnapshotDelegate: AnyObject {

    // MARK: - Transaction Lifecycle

    /// Called on the DatabaseSnapshotSerial queue durign the transaction
    /// so the DatabaseSnapshotDelegate can accrue information about changes
    /// as they occur.

    func snapshotTransactionDidChange(with event: DatabaseEvent)
    func snapshotTransactionDidCommit(db: Database)
    func snapshotTransactionDidRollback(db: Database)

    // MARK: - Snapshot LifeCycle (Post Commit)

    /// Called on the Main Thread after the transaction has committed

    func databaseSnapshotWillUpdate()
    func databaseSnapshotDidUpdate()
    func databaseSnapshotDidUpdateExternally()
}

enum DatabaseObserverError: Error {
    case changeTooLarge
}

@objc
public class AtomicBool: NSObject {
    private var value: Bool

    @objc
    public required init(_ value: Bool) {
        self.value = value
    }

    // All instances can share a single queue.
    private static let serialQueue = DispatchQueue(label: "AtomicBool")

    @objc
    public func get() -> Bool {
        return AtomicBool.serialQueue.sync {
            return self.value
        }
    }

    @objc
    public func set(_ value: Bool) {
        return AtomicBool.serialQueue.sync {
            self.value = value
        }
    }
}

func AssertIsOnUIDatabaseObserverSerialQueue() {
    assert(UIDatabaseObserver.isOnUIDatabaseObserverSerialQueue)
}

@objc
public class UIDatabaseObserver: NSObject {

    public static let kMaxIncrementalRowChanges = 200

    // tldr; Instead, of protecting UIDatabaseObserver state with a nested DispatchQueue,
    // which would break GRDB's SchedulingWatchDog, we use objc_sync
    //
    // Longer version:
    // Our snapshot observers manage state, which must not be accessed concurrently.
    // Using a serial DispatchQueue would seem straight forward, but...
    //
    // Some of our snapshot observers read from the database *while* accessing this
    // state. Note that reading from the db must be done on GRDB's DispatchQueue.
    private static var _isOnUIDatabaseObserverSerialQueue = AtomicBool(false)

    static var isOnUIDatabaseObserverSerialQueue: Bool {
        return _isOnUIDatabaseObserverSerialQueue.get()
    }

    public class func serializedSync(block: () -> Void) {
        objc_sync_enter(self)
        assert(!_isOnUIDatabaseObserverSerialQueue.get())
        _isOnUIDatabaseObserverSerialQueue.set(true)
        block()
        _isOnUIDatabaseObserverSerialQueue.set(false)
        objc_sync_exit(self)
    }

    private var _snapshotDelegates: [Weak<DatabaseSnapshotDelegate>] = []
    private var snapshotDelegates: [DatabaseSnapshotDelegate] {
        return _snapshotDelegates.compactMap { $0.value }
    }

    public func appendSnapshotDelegate(_ snapshotDelegate: DatabaseSnapshotDelegate) {
        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
    }

    let pool: DatabasePool

    var isRunningCheckpoint = false
    var needsTruncatingCheckpoint = false
    let checkPointQueue = DispatchQueue(label: "checkpointQueue")

    internal var latestSnapshot: DatabaseSnapshot {
        didSet {
            AssertIsOnMainThread()
        }
    }

    init(pool: DatabasePool) throws {
        self.pool = pool
        self.latestSnapshot = try pool.makeSnapshot()
        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveCrossProcessNotification),
                                               name: SDSDatabaseStorage.didReceiveCrossProcessNotification,
                                               object: nil)
    }

    @objc
    func didReceiveCrossProcessNotification(_ notification: Notification) {
        AssertIsOnMainThread()
        Logger.verbose("")

        for delegate in snapshotDelegates {
            delegate.databaseSnapshotDidUpdateExternally()
        }
    }
}

extension UIDatabaseObserver: TransactionObserver {

    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        guard !eventKind.tableName.hasPrefix(GRDBFullTextSearchFinder.databaseTableName) else {
            // Ignore updates to the GRDB FTS table(s)
            return false
        }

        return true
    }

    public func databaseDidChange(with event: DatabaseEvent) {
        UIDatabaseObserver.serializedSync {
            for snapshotDelegate in snapshotDelegates {
                snapshotDelegate.snapshotTransactionDidChange(with: event)
            }
        }
    }

    public func databaseDidCommit(_ db: Database) {
        UIDatabaseObserver.serializedSync {
            for snapshotDelegate in snapshotDelegates {
                snapshotDelegate.snapshotTransactionDidCommit(db: db)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Logger.verbose("databaseSnapshotWillUpdate")
            for delegate in self.snapshotDelegates {
                delegate.databaseSnapshotWillUpdate()
            }

            self.latestSnapshot.read { db in
                do {
                    try self.fastForwardDatabaseSnapshot(db: db)
                } catch {
                    owsFailDebug("\(error)")
                }
            }

            Logger.verbose("databaseSnapshotDidUpdate")
            for delegate in self.snapshotDelegates {
                delegate.databaseSnapshotDidUpdate()
            }
        }
    }

    public func databaseDidRollback(_ db: Database) {
        UIDatabaseObserver.serializedSync {
            for snapshotDelegate in snapshotDelegates {
                snapshotDelegate.snapshotTransactionDidRollback(db: db)
            }
        }
    }

    // Currently GRDB offers no built in way to fast-forward a
    // database snapshot.
    // See: https://github.com/groue/GRDB.swift/issues/619
    func fastForwardDatabaseSnapshot(db: Database) throws {
        // [1] end the old transaction from the old db state
        try db.commit()

        // [2] Checkpoint the WAL
        // Checkpointing is the process of moving data from the WAL back into the main database file.
        // Without it, the WAL will grow indefinitely.
        //
        // Checkpointing has several flavors, including `passive` which opportunistically checkpoints
        // what it can without requiring blocking of reads or writes.
        //
        // SQLite's default auto-checkpointing uses `passive` checkpointing, but because our
        // DatabaseSnapshot maintains a long running read transaction, passive checkpointing can
        // never successfully truncate the WAL (because there is at least the one read transaction
        // using it).
        //
        // The only time the long-lived read transaction is *not* reading the database is
        // *right here*, between committing the last transaction and starting the next one.
        //
        // Solution:
        //   Under normal load, when the WAL is not known to be large, prefer the lighter weight
        //   passive checkpoint, and do it async to further minimize main thread impact.
        //   When the WAL is known to be large however, we synchronously checkpoint and truncate
        //   the WAL before resuming the snapshot read transaction.
        let needsTruncatingCheckpoint = checkPointQueue.sync {
            return self.needsTruncatingCheckpoint
        }

        if needsTruncatingCheckpoint {
            Logger.info("running truncating checkpoint.")
            try pool.writeWithoutTransaction { db in
                try checkpointWal(db: db, mode: .truncate)
            }
        } else {
            pool.asyncWriteWithoutTransaction { db in
                do {
                    try self.checkpointWal(db: db, mode: .passive)
                } catch {
                    owsFailDebug("error \(error)")
                }
            }
        }

        // [3] open a new transaction from the current db state
        try db.beginTransaction(.deferred)

        // [4] do *any* read to acquire non-deferred read lock
        _ = try Row.fetchCursor(db, sql: "SELECT rootpage FROM sqlite_master LIMIT 1").next()
    }

    func checkpointWal(db: Database, mode: Database.CheckpointMode) throws {
        var walSizePages: Int32 = 0
        var pagesCheckpointed: Int32 = 0

        checkPointQueue.sync {
            guard !isRunningCheckpoint else {
                return
            }
            isRunningCheckpoint = true
        }

        let code = sqlite3_wal_checkpoint_v2(db.sqliteConnection, nil, mode.rawValue, &walSizePages, &pagesCheckpointed)
        // Logger.verbose("checkpoint mode: \(mode), walSizePages: \(walSizePages),  pagesCheckpointed:\(pagesCheckpointed)")
        guard code == SQLITE_OK else {
            throw OWSAssertionError("checkpoint sql error with code: \(code)")
        }

        let maxWalFileSizeBytes = 2 * 1024 * 1024
        let pageSize = 4 * 1024
        let maxWalPages = maxWalFileSizeBytes / pageSize
        needsTruncatingCheckpoint = walSizePages > maxWalPages

        checkPointQueue.sync {
            isRunningCheckpoint = false
        }
    }
}
