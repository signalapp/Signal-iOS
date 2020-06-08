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

    private let pool: DatabasePool
    private let checkpointingQueue: DatabaseQueue?

    internal var latestSnapshot: DatabaseSnapshot {
        didSet {
            AssertIsOnMainThread()
        }
    }

    private let hasPendingSnapshotUpdate = AtomicBool(false)
    private var lastSnapshotUpdateDate: Date?

    // This property should only be accessed on the main thread.
    private var lastCheckpointDate: Date?

    private var displayLink: CADisplayLink?

    init(pool: DatabasePool, checkpointingQueue: DatabaseQueue?) throws {
        self.pool = pool
        self.checkpointingQueue = checkpointingQueue
        self.latestSnapshot = try pool.makeSnapshot()

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveCrossProcessNotification),
                                               name: SDSDatabaseStorage.didReceiveCrossProcessNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.applicationStateDidChange),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationStateDidChange),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            self.ensureDisplayLink()
        }
    }

    private func ensureDisplayLink() {
        guard CurrentAppContext().hasUI else {
            // The NSE never does uiReads, we can skip the display link.
            return
        }

        let shouldBeActive: Bool = {
            guard AppReadiness.isAppReady() else {
                return false
            }
            guard !CurrentAppContext().isInBackground() else {
                return false
            }
            return true
        }()

        if shouldBeActive {
            if let displayLink = displayLink {
                displayLink.isPaused = false
            } else {
                let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
                link.preferredFramesPerSecond = 60
                link.add(to: .main, forMode: .default)
                assert(!link.isPaused)
                displayLink = link
            }
        } else {
            displayLink?.isPaused = true
        }
    }

    @objc
    func displayLinkDidFire() {
        AssertIsOnMainThread()

        updateSnapshotIfNecessary()
    }

    @objc
    func applicationStateDidChange(_ notification: Notification) {
        AssertIsOnMainThread()

        ensureDisplayLink()
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

    // Database observation operates like so:
    //
    // * This class (UIDatabaseObserver) works closely with its "snapshot delegates"
    //   (per-view snapshots/observers) to update the views in controlled, consistent way.
    // * UIDatabaseObserver observes all database _changes_ and _commits_.
    // * When a _change_ occurs:
    //   * This is done off the main thread.
    //   * UIDatabaseObserver informs all "snapshot delegates" of changes using snapshotTransactionDidChange.
    //   * The "snapshot delegates" aggregate the changes.
    // * When a _commit_ occurs:
    //   * This is done off the main thread.
    //   * UIDatabaseObserver informs all "snapshot delegates" to commit their _changes_ using snapshotTransactionDidCommit.
    //     The "snapshot delegates" commit changes internally using DispatchQueue.main.async().
    //   * UIDatabaseObserver enqueues a "snapshot update" using DispatchQueue.main.async().
    // * When a "snapshot update" is performed:
    //   * This is done on the main thread.
    //   * UIDatabaseObserver informs all "snapshot delegates" of the update using databaseSnapshotWillUpdate.
    //   * UIDatabaseObserver updates the database snapshot.
    //   * UIDatabaseObserver informs all "snapshot delegates" of the update using databaseSnapshotDidUpdate.
    public func databaseDidChange(with event: DatabaseEvent) {
        UIDatabaseObserver.serializedSync {
            for snapshotDelegate in snapshotDelegates {
                snapshotDelegate.snapshotTransactionDidChange(with: event)
            }
        }
    }

    // See comment on databaseDidChange.
    public func databaseDidCommit(_ db: Database) {
        UIDatabaseObserver.serializedSync {
            for snapshotDelegate in snapshotDelegates {
                snapshotDelegate.snapshotTransactionDidCommit(db: db)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            // Enqueue the update.
            self.hasPendingSnapshotUpdate.set(true)
            // Try to update immediately.
            self.updateSnapshotIfNecessary()
        }
    }

    // See comment on databaseDidChange.
    private func updateSnapshotIfNecessary() {
        AssertIsOnMainThread()

        if let lastSnapshotUpdateDate = self.lastSnapshotUpdateDate {
            let secondsSinceLastUpdate = abs(lastSnapshotUpdateDate.timeIntervalSinceNow)
            // Don't update UI more often than Nx/second.
            let maxUpdatesPerSecond: UInt = 10
            let maxUpdateFrequencySeconds: TimeInterval = 1 / TimeInterval(maxUpdatesPerSecond)
            guard secondsSinceLastUpdate >= maxUpdateFrequencySeconds else {
                // Don't update the snapshot yet; we've updated the snapshot recently.
                Logger.verbose("Delaying snapshot update")
                return
            }
        }

        do {
            // We only want to update the snapshot if we the flag needs to be cleared.
            // This will throw AtomicError.invalidTransition if that flag isn't set.
            try hasPendingSnapshotUpdate.transition(from: true, to: false)
        } catch {
            switch error {
            case AtomicError.invalidTransition:
                // If there's no new database changes, we don't need to update the snapshot.
                break
            default:
                owsFailDebug("Error: \(error)")
            }
            return
        }

        // Update the snapshot now.
        lastSnapshotUpdateDate = Date()
        updateSnapshot()
    }

    // See comment on databaseDidChange.
    private func updateSnapshot() {
        AssertIsOnMainThread()

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
        checkpointIfNecessary()

        // [3] open a new transaction from the current db state
        try db.beginTransaction(.deferred)

        // [4] do *any* read to acquire non-deferred read lock
        _ = try Row.fetchCursor(db, sql: "SELECT rootpage FROM sqlite_master LIMIT 1").next()
    }

    private func checkpointIfNecessary() {
        AssertIsOnMainThread()

        guard let checkpointingQueue = checkpointingQueue else {
            // We only checkpoint in the main app;
            // checkpointingQueue will not be set in the app extensions.
            assert(!CurrentAppContext().isMainApp)
            return
        }
        assert(CurrentAppContext().isMainApp)

        // Checkpointing is the process of integrating the WAL into the main database file.
        // Without it, the WAL will grow indefinitely. A large WAL affects read performance.
        //
        // Checkpointing has several flavors: passive, full, restart, truncate.
        //
        // * Passive checkpoints abort immediately if there are any database
        //   readers or writers. This makes them "cheap" in the sense that
        //   they won't block the main thread for long.
        //   However they only integrate WAL contents, they don't "restart" or
        //   "truncate" so they don't inherently limit WAL growth. We use them
        //   because they're cheap and they help our other checkpoints cheaper
        //   by ensuring that most of the WAL is integrated at any given time.
        // * Full/Restart/Truncate checkpoints will block using the busy-handler.
        //   We use truncate checkpoints since they truncate the WAL file.
        //   See GRDBStorage.buildConfiguration for our busy-handler (aka busyMode callback).
        //   It aborts after ~50ms.
        //   These checkpoints are more expensive and will block the main thread
        //   while they do their work but will limit WAL growth.
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
        //
        // * Perform passive checkpoints often to ensure WAL contents are mostly integrated
        //   at any given time.
        // * Perform truncate checkpoints sometimes to limit WAL size.
        // * Limit checkpoint frequency by time so that heavy write activity won't bog down
        //   the main thread.
        // * Perform checkpoints using a dedicated GRDB DatabaseQueue so that checkpoints
        //   don't block on writes. GRDB DatabasePool serializes writes on a queue that
        //   doesn't honor the busy mode. This also makes the checkpoints very likely to succeed.
        //
        // See: https://www.sqlite.org/c3ref/wal_checkpoint_v2.html
        // See: https://www.sqlite.org/wal.html
        let shouldTryToCheckpoint = { () -> Bool in
            guard !TSAccountManager.sharedInstance().isTransferInProgress else {
                return false
            }

            guard let lastCheckpointDate = self.lastCheckpointDate else {
                return true
            }
            let maxCheckpointFrequency: TimeInterval = 0.25
            guard abs(lastCheckpointDate.timeIntervalSinceNow) >= maxCheckpointFrequency else {
                Logger.verbose("Skipping checkpoint due to frequency")
                return false
            }
            return true
        }()
        guard shouldTryToCheckpoint else {
            return
        }

        // Run truncate checkpoints after 1/N of writes.
        let shouldDoTruncateCheckpoint = arc4random_uniform(10) == 0
        let mode: Database.CheckpointMode = shouldDoTruncateCheckpoint ? .truncate : .passive
        do {
            try checkpoint(mode: mode,
                           checkpointingQueue: checkpointingQueue)
        } catch {
            owsFailDebug("error \(error)")
        }
        lastCheckpointDate = Date()
    }

    func checkpoint(mode: Database.CheckpointMode,
                    checkpointingQueue: DatabaseQueue) throws {
        AssertIsOnMainThread()

        let result = try GRDBDatabaseStorageAdapter.checkpoint(checkpointingQueue: checkpointingQueue, mode: mode)

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
