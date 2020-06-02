//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

func AssertIsOnUIDatabaseObserverSerialQueue() {
    assert(UIDatabaseObserver.isOnUIDatabaseObserverSerialQueue)
}

@objc
public class UIDatabaseObserver: NSObject {

    public static let kMaxIncrementalRowChanges = 200

    private lazy var nonModelTables: Set<String> = Set([MediaGalleryRecord.databaseTableName, PendingReadReceiptRecord.databaseTableName])

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

    // Toggle to skip expensive observations resulting
    // from a `touch`. Useful for large migrations.
    // Should only be accessed within UIDatabaseObserver.serializedSync
    public static var skipTouchObservations: Bool = false

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

    internal var latestSnapshot: DatabaseSnapshot {
        didSet {
            AssertIsOnMainThread()
        }
    }

    private static let debounceSnapshotUpdates = true
    private static let snapshotCoordinationQueue = DispatchQueue(label: "UIDatabaseObserver")
    private var hasPendingSnapshotUpdate = false
    private var lastSnapshotUpdateDate: Date?

    // This property should only be accessed on the main thread.
    private var lastCheckpointDate: Date?

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
        guard !eventKind.tableName.hasPrefix(GRDBFullTextSearchFinder.contentTableName) else {
            // Ignore updates to the GRDB FTS table(s)
            return false
        }

        guard !nonModelTables.contains(eventKind.tableName) else {
            // Ignore updates to non-model tables
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

        if Self.debounceSnapshotUpdates {
            Self.snapshotCoordinationQueue.sync {
                guard !self.hasPendingSnapshotUpdate else {
                    // If there's already a pending snapshot, abort.
                    return
                }

                // Enqueue a pending snapshot.
                self.hasPendingSnapshotUpdate = true

                if let lastSnapshotUpdateDate = self.lastSnapshotUpdateDate {
                    let secondsSinceLastUpdate = abs(lastSnapshotUpdateDate.timeIntervalSinceNow)
                    // Don't update UI more often than 4x/second.
                    let maxUpdateFrequencySeconds: TimeInterval = 0.25
                    let delaySeconds = maxUpdateFrequencySeconds - secondsSinceLastUpdate
                    if delaySeconds > 0 {
                        Logger.verbose("Updating db snapshot after: \(delaySeconds).")
                        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delaySeconds) { [weak self] in
                            self?.updateSnapshot()
                        }
                        return
                    }
                }
                // Update snapshot ASAP.
                Logger.verbose("Updating db snapshot ASAP.")
                DispatchQueue.main.async { [weak self] in
                    self?.updateSnapshot()
                }
            }
        } else {
            // Update snapshot ASAP.
            Logger.verbose("Updating db snapshot ASAP.")
            DispatchQueue.main.async { [weak self] in
                self?.updateSnapshot()
            }
        }
    }

    private func updateSnapshot() {
        AssertIsOnMainThread()

        if Self.debounceSnapshotUpdates {
            Self.snapshotCoordinationQueue.sync {
                assert(self.hasPendingSnapshotUpdate)
                self.hasPendingSnapshotUpdate = false
                self.lastSnapshotUpdateDate = Date()
            }
        }

        Logger.verbose("databaseSnapshotWillUpdate")
        for delegate in snapshotDelegates {
            delegate.databaseSnapshotWillUpdate()
        }

        latestSnapshot.read { db in
            do {
                try self.fastForwardDatabaseSnapshot(db: db)
            } catch {
                owsFailDebug("\(error)")
            }
        }

        Logger.verbose("databaseSnapshotDidUpdate")
        for delegate in snapshotDelegates {
            delegate.databaseSnapshotDidUpdate()
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
        AssertIsOnMainThread()
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
        //   Perform an explicit passive checkpoint sync after every write.
        //   It will probably not succeed often in truncating the database, but
        //   we only need it to succeed periodically. This might have an
        //   unacceptable perf cost, and it might not succeed often enough.
        //
        //   We periodically try to perform a restart checkpoint which
        //   can limit WAL size when truncation isn't possible.
        let shouldTryToCheckpoint = { () -> Bool in
            guard !TSAccountManager.sharedInstance().isTransferInProgress else {
                return false
            }
            guard let lastCheckpointDate = lastCheckpointDate else {
                return true
            }
            let maxCheckpointFrequency: TimeInterval = 0.1
            guard abs(lastCheckpointDate.timeIntervalSinceNow) >= maxCheckpointFrequency else {
                Logger.verbose("Skipping checkpoint due to frequency")
                return false
            }
            return true
        }()
        if shouldTryToCheckpoint {
            // Run restart checkpoints after 1/N of writes.
            let restartCheckpointFraction: UInt32 = 30
            let shouldDoRestartCheckpoint = arc4random_uniform(restartCheckpointFraction) == 0
            do {
                let mode: Database.CheckpointMode = shouldDoRestartCheckpoint ? .restart : .passive
                try self.checkpoint(mode: mode)
            } catch {
                owsFailDebug("error \(error)")
            }
            lastCheckpointDate = Date()
        }

        // [3] open a new transaction from the current db state
        try db.beginTransaction(.deferred)

        // [4] do *any* read to acquire non-deferred read lock
        _ = try Row.fetchCursor(db, sql: "SELECT rootpage FROM sqlite_master LIMIT 1").next()
    }

    private static let isRunningCheckpoint = AtomicBool(false)

    func checkpoint(mode: Database.CheckpointMode) throws {
        do {
            try UIDatabaseObserver.isRunningCheckpoint.transition(from: false, to: true)
        } catch {
            Logger.warn("Skipping checkpoint; already running checkpoint.")
            return
        }
        defer {
            UIDatabaseObserver.isRunningCheckpoint.set(false)
        }

        let result = try GRDBDatabaseStorageAdapter.checkpoint(pool: pool, mode: mode)

        let pageSize: Int32 = 4 * 1024
        let walFileSizeBytes = result.walSizePages * pageSize
        let maxWalFileSizeBytes = 4 * 1024 * 1024
        if walFileSizeBytes > maxWalFileSizeBytes {
            Logger.info("walFileSizeBytes: \(walFileSizeBytes).")
            Logger.info("walSizePages: \(result.walSizePages), pagesCheckpointed: \(result.pagesCheckpointed).")
        } else {
            Logger.verbose("walSizePages: \(result.walSizePages), pagesCheckpointed: \(result.pagesCheckpointed).")
        }
    }
}
