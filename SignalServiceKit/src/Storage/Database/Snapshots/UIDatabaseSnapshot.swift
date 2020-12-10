//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public protocol UIDatabaseSnapshotDelegate: AnyObject {
    func uiDatabaseSnapshotWillUpdate()
    func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges)
    func uiDatabaseSnapshotDidUpdateExternally()
    func uiDatabaseSnapshotDidReset()
}

// MARK: -

#if TESTABLE_BUILD
public protocol DatabaseWriteDelegate: AnyObject {
    func databaseDidChange(with event: DatabaseEvent)
    func databaseDidCommit(db: Database)
    func databaseDidRollback(db: Database)
}
#endif

// MARK: -

enum DatabaseObserverError: Error {
    case changeTooLarge
}

// MARK: -

func AssertHasUIDatabaseObserverLock() {
    assert(UIDatabaseObserver.hasUIDatabaseObserverLock)
}

// MARK: -

@objc
public class UIDatabaseObserver: NSObject {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return .shared()
    }

    // MARK: -

    @objc
    public static let didUpdateUIDatabaseSnapshotNotification = Notification.Name("didUpdateUIDatabaseSnapshot")

    @objc
    public static let databaseDidCommitInteractionChangeNotification = Notification.Name("databaseDidCommitInteractionChangeNotification")

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
    private static var _hasUIDatabaseObserverLock = AtomicBool(false)

    static var hasUIDatabaseObserverLock: Bool {
        return _hasUIDatabaseObserverLock.get()
    }

    // Toggle to skip expensive observations resulting
    // from a `touch`. Useful for large migrations.
    // Should only be accessed within UIDatabaseObserver.serializedSync
    public static var skipTouchObservations: Bool = false

    private static let uiDatabaseObserverLock = UnfairLock()

    public class func serializedSync(block: () -> Void) {
        uiDatabaseObserverLock.withLock {
            assert(!_hasUIDatabaseObserverLock.get())
            _hasUIDatabaseObserverLock.set(true)
            block()
            _hasUIDatabaseObserverLock.set(false)
        }
    }

    private var _snapshotDelegates: [Weak<UIDatabaseSnapshotDelegate>] = []
    private var snapshotDelegates: [UIDatabaseSnapshotDelegate] {
        return _snapshotDelegates.compactMap { $0.value }
    }

    func appendSnapshotDelegate(_ snapshotDelegate: UIDatabaseSnapshotDelegate) {
        let append = { [weak self] in
            guard let self = self else {
                return
            }
            self._snapshotDelegates = self._snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
        }
        if CurrentAppContext().isRunningTests {
            append()
        } else {
            // Never notify delegates until the app is ready.
            // This prevents us from shooting ourselves in the foot
            // and registering for database changes too early.
            assert(AppReadiness.isAppReady)
            AppReadiness.runNowOrWhenAppWillBecomeReady(append)
        }
    }

    // Block which will be called after all pending (committed) db changes
    // have been flushed.
    func add(snapshotFlushBlock: @escaping ObservedDatabaseChanges.CompletionBlock) {
        UIDatabaseObserver.serializedSync {
            pendingChanges.add(completionBlock: snapshotFlushBlock)
        }
    }

    #if TESTABLE_BUILD
    private var _databaseWriteDelegates: [Weak<DatabaseWriteDelegate>] = []
    private var databaseWriteDelegates: [DatabaseWriteDelegate] {
        return _databaseWriteDelegates.compactMap { $0.value }
    }

    func appendDatabaseWriteDelegate(_ delegate: DatabaseWriteDelegate) {
        _databaseWriteDelegates = _databaseWriteDelegates.filter { $0.value != nil} + [Weak(value: delegate)]
    }
    #endif

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
    private let displayLinkPreferredFramesPerSecond: Int = 20
    private var recentDisplayLinkDates = [Date]()

    fileprivate var pendingChanges = ObservedDatabaseChanges(concurrencyMode: .uiDatabaseObserverSerialQueue)
    fileprivate var committedChanges = ObservedDatabaseChanges(concurrencyMode: .mainThread)

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
        AssertIsOnMainThread()

        guard CurrentAppContext().hasUI else {
            // The NSE never does uiReads, we can skip the display link.
            return
        }

        let shouldBeActive: Bool = {
            guard AppReadiness.isAppReady else {
                return false
            }
            guard !CurrentAppContext().isInBackground() else {
                return false
            }
            guard self.hasPendingSnapshotUpdate.get() else {
                return false
            }
            return true
        }()

        if shouldBeActive {
            if let displayLink = displayLink {
                displayLink.isPaused = false
            } else {
                let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
                link.preferredFramesPerSecond = displayLinkPreferredFramesPerSecond
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

        recentDisplayLinkDates.append(Date())

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
            delegate.uiDatabaseSnapshotDidUpdateExternally()
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

    // This should only be called by DatabaseStorage.
    func updateIdMapping(thread: TSThread, transaction: GRDBWriteTransaction) {
        AssertHasUIDatabaseObserverLock()

        pendingChanges.append(thread: thread)
        pendingChanges.append(tableName: TSThread.table.tableName)
    }

    // This should only be called by DatabaseStorage.
    func updateIdMapping(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        AssertHasUIDatabaseObserverLock()

        pendingChanges.append(interaction: interaction)
        pendingChanges.append(tableName: TSInteraction.table.tableName)
    }

    // This should only be called by DatabaseStorage.
    func updateIdMapping(attachment: TSAttachment, transaction: GRDBWriteTransaction) {
        AssertHasUIDatabaseObserverLock()

        pendingChanges.append(attachment: attachment)
        pendingChanges.append(tableName: TSAttachment.table.tableName)
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        AssertHasUIDatabaseObserverLock()

        pendingChanges.append(interaction: interaction)
        pendingChanges.append(tableName: TSInteraction.table.tableName)

        if !pendingChanges.threadUniqueIds.contains(interaction.uniqueThreadId) {
            let interactionThread: TSThread? = interaction.thread(transaction: transaction.asAnyRead)
            if let thread = interactionThread {
                didTouch(thread: thread, transaction: transaction)
            } else {
                owsFailDebug("Could not load thread for interaction.")
            }
        }
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(thread: TSThread, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertHasUIDatabaseObserverLock()

        pendingChanges.append(thread: thread)
        pendingChanges.append(tableName: TSThread.table.tableName)
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

            pendingChanges.append(tableName: event.tableName)

            if event.tableName == InteractionRecord.databaseTableName {
                pendingChanges.append(interactionRowId: event.rowID)
            } else if event.tableName == ThreadRecord.databaseTableName {
                pendingChanges.append(threadRowId: event.rowID)
            } else if event.tableName == AttachmentRecord.databaseTableName {
                pendingChanges.append(attachmentRowId: event.rowID)
            }

            // We record certain deletions.
            if event.kind == .delete && event.tableName == AttachmentRecord.databaseTableName {
                pendingChanges.append(deletedAttachmentRowId: event.rowID)
            } else if event.kind == .delete && event.tableName == InteractionRecord.databaseTableName {
                pendingChanges.append(deletedInteractionRowId: event.rowID)
            }

            #if TESTABLE_BUILD
            for delegate in databaseWriteDelegates {
                delegate.databaseDidChange(with: event)
            }
            #endif
        }
    }

    // See comment on databaseDidChange.
    public func databaseDidCommit(_ db: Database) {
        UIDatabaseObserver.serializedSync {
            let pendingChangesToCommit = self.pendingChanges
            self.pendingChanges = ObservedDatabaseChanges(concurrencyMode: .uiDatabaseObserverSerialQueue)

            do {
                // finalizePublishedState() finalizes the state we're about to
                // copy.
                try pendingChangesToCommit.finalizePublishedState(db: db)

                let interactionUniqueIds = pendingChangesToCommit.interactionUniqueIds
                let threadUniqueIds = pendingChangesToCommit.threadUniqueIds
                let attachmentUniqueIds = pendingChangesToCommit.attachmentUniqueIds
                let interactionDeletedUniqueIds = pendingChangesToCommit.interactionDeletedUniqueIds
                let attachmentDeletedUniqueIds = pendingChangesToCommit.attachmentDeletedUniqueIds
                let collections = pendingChangesToCommit.collections
                let completionBlocks = pendingChangesToCommit.completionBlocks

                DispatchQueue.main.async {
                    self.committedChanges.append(interactionUniqueIds: interactionUniqueIds)
                    self.committedChanges.append(threadUniqueIds: threadUniqueIds)
                    self.committedChanges.append(attachmentUniqueIds: attachmentUniqueIds)
                    self.committedChanges.append(interactionDeletedUniqueIds: interactionDeletedUniqueIds)
                    self.committedChanges.append(attachmentDeletedUniqueIds: attachmentDeletedUniqueIds)
                    self.committedChanges.append(collections: collections)
                    self.committedChanges.append(completionBlocks: completionBlocks)
                }
            } catch {
                DispatchQueue.main.async {
                    self.committedChanges.setLastError(error)
                }
            }

            let didModifyInteractions = pendingChangesToCommit.tableNames.contains(InteractionRecord.databaseTableName)
            if didModifyInteractions {
                NotificationCenter.default.postNotificationNameAsync(Self.databaseDidCommitInteractionChangeNotification, object: nil)
            }

            #if TESTABLE_BUILD
            for delegate in databaseWriteDelegates {
                delegate.databaseDidCommit(db: db)
            }
            #endif
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            // Enqueue the update.
            self.hasPendingSnapshotUpdate.set(true)
            self.ensureDisplayLink()
            // Try to update immediately.
            self.updateSnapshotIfNecessary()
        }
    }

    // See comment on databaseDidChange.
    private func updateSnapshotIfNecessary() {
        AssertIsOnMainThread()

        guard !tsAccountManager.isTransferInProgress else {
            Logger.info("Skipping snapshot update; transfer in progress.")
            return
        }

        if let lastSnapshotUpdateDate = self.lastSnapshotUpdateDate {
            let secondsSinceLastUpdate = abs(lastSnapshotUpdateDate.timeIntervalSinceNow)
            // Don't update UI more often than Nx/second.
            guard secondsSinceLastUpdate >= targetUpdateInterval else {
                // Don't update the snapshot yet; we've updated the snapshot recently.
                return
            }
        }

        // We only want to update the snapshot if the flag is set.
        guard hasPendingSnapshotUpdate.tryToClearFlag() else {
            // If there's no new database changes, we don't need to update the snapshot.
            return
        }
        ensureDisplayLink()

        // Update the snapshot now.
        updateSnapshot()
    }

    private var targetUpdateInterval: Double {
        AssertIsOnMainThread()
        #if TESTABLE_BUILD
        // Don't wait before updating snapshots in tests
        // because some tests checks snapshots immediately
        if CurrentAppContext().isRunningTests { return 0 }
        #endif
        // We want the UI to feel snappy and responsive, which means
        // low latency in view updates.
        //
        // This means updating the database snapshot (and hence the
        // views) as frequently as possible.
        //
        // However, when the app is under heavy load, constantly
        // updating the views is expensive and causes CPU contention,
        // slowing down business logic. The outcome is that the app
        // feels less responsive.
        //
        // Therefore, the app should "back off" and slow the rate at
        // which it updates database snapshots when it is under
        // heavy load.
        //
        // We measure load using a heuristics: Can the display link
        // maintain its preferred frame rate?
        let windowDuration: TimeInterval = 5 * kSecondInterval
        recentDisplayLinkDates = recentDisplayLinkDates.filter {
            abs($0.timeIntervalSinceNow) < windowDuration
        }

        let recentDisplayLinkFrequency: Double = Double(recentDisplayLinkDates.count) / windowDuration
        // Under light load, the display link should fire at its preferred frame rate.
        let lightDisplayLinkFrequency: Double = Double(self.displayLinkPreferredFramesPerSecond)
        // We consider heavy load to be the display link firing at half of its preferred frame rate.
        let heavyDisplayLinkFrequency: Double = Double(self.displayLinkPreferredFramesPerSecond / 2)
        // Alpha represents the unit load, 0 <= x <= 1.
        // 0 = light load.
        // 1 = heavy load.
        let displayLinkAlpha: Double = recentDisplayLinkFrequency.inverseLerp(lightDisplayLinkFrequency,
                                                                              heavyDisplayLinkFrequency,
                                                                              shouldClamp: true)

        // Select the alpha of our chosen heuristic.
        let alpha: Double = displayLinkAlpha

        // These intervals control update frequency.
        let fastUpdateInterval: TimeInterval = 1 / TimeInterval(5)
        let slowUpdateInterval: TimeInterval = 1 / TimeInterval(1)
        // Under light load, we want the fastest update frequency.
        // Under heavy load, we want the slowest update frequency.
        let targetUpdateInterval = alpha.lerp(fastUpdateInterval, slowUpdateInterval)
        return targetUpdateInterval
    }

    // NOTE: This should only be used in exceptional circumstances,
    // e.g. after reloading the database due to a device transfer.
    func forceUpdateSnapshot() {
        AssertIsOnMainThread()

        Logger.info("")

        updateSnapshot(canCheckpoint: false)
    }

    // See comment on databaseDidChange.
    private func updateSnapshot(canCheckpoint: Bool = true) {
        AssertIsOnMainThread()

        lastSnapshotUpdateDate = Date()

        Logger.verbose("databaseSnapshotWillUpdate")
        for delegate in snapshotDelegates {
            delegate.uiDatabaseSnapshotWillUpdate()
        }

        latestSnapshot.read { db in
            do {
                try self.fastForwardDatabaseSnapshot(db: db, canCheckpoint: canCheckpoint)
            } catch {
                owsFailDebug("\(error)")
            }
        }

        // We post this notification sync so that the read model caches
        // can discard their contents.
        NotificationCenter.default.post(name: Self.didUpdateUIDatabaseSnapshotNotification, object: nil)

        defer {
            committedChanges = ObservedDatabaseChanges(concurrencyMode: .mainThread)
        }

        Logger.verbose("databaseSnapshotDidUpdate")

        if let lastError = committedChanges.lastError {
            switch lastError {
            case DatabaseObserverError.changeTooLarge:
                // no assertionFailure, we expect this sometimes
                break
            default:
                owsFailDebug("unknown error: \(lastError)")
            }
            for delegate in self.snapshotDelegates {
                delegate.uiDatabaseSnapshotDidReset()
            }
        } else {
            for delegate in snapshotDelegates {
                delegate.uiDatabaseSnapshotDidUpdate(databaseChanges: committedChanges)
            }
        }

        for completionBlock in committedChanges.completionBlocks {
            completionBlock()
        }
    }

    public func databaseDidRollback(_ db: Database) {
        owsFailDebug("TODO: test this if we ever use it.")
        // TODO: Make sure snapshot flush blocks work correctly in this case.

        UIDatabaseObserver.serializedSync {
            pendingChanges = ObservedDatabaseChanges(concurrencyMode: .uiDatabaseObserverSerialQueue)

            #if TESTABLE_BUILD
            for delegate in databaseWriteDelegates {
                delegate.databaseDidRollback(db: db)
            }
            #endif
        }
    }

    // Currently GRDB offers no built in way to fast-forward a
    // database snapshot.
    // See: https://github.com/groue/GRDB.swift/issues/619
    func fastForwardDatabaseSnapshot(db: Database, canCheckpoint: Bool = true) throws {
        AssertIsOnMainThread()

        // [1] end the old transaction from the old db state
        try db.commit()

        // [2] Checkpoint the WAL
        if canCheckpoint {
            checkpointIfNecessary()
        }

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
            guard !tsAccountManager.isTransferInProgress else {
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
