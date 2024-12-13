//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public protocol DatabaseChangeDelegate: AnyObject {
    @MainActor
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges)
    @MainActor
    func databaseChangesDidUpdateExternally()
    @MainActor
    func databaseChangesDidReset()
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

func AssertHasDatabaseChangeObserverLock() {
    assert(DatabaseChangeObserverImpl.hasDatabaseChangeObserverLock)
}

// MARK: -

/// A singular ``TransactionObserver`` that collates and forwards observed
/// db changes to ``DatabaseChangeDelegate``s.
///
/// Do not use this protocol/class. Prefer to observe the database directly through
/// GRDB APIs. This type is maintained for legacy observers only.
public protocol DatabaseChangeObserver {

    func beginObserving(pool: DatabasePool) throws

    func stopObserving(pool: DatabasePool) throws

    /// Disable generic change observer events during a block that occurs within a write transaction.
    func disable<T>(tx: DBWriteTransaction, during: (DBWriteTransaction) throws -> T) rethrows -> T

    @MainActor
    func appendDatabaseChangeDelegate(_ databaseChangeDelegate: DatabaseChangeDelegate)

#if TESTABLE_BUILD
    func appendDatabaseWriteDelegate(_ delegate: DatabaseWriteDelegate)
#endif
}

public protocol SDSDatabaseChangeObserver: DatabaseChangeObserver {

    func updateIdMapping(thread: TSThread, transaction: GRDBWriteTransaction)
    func updateIdMapping(interaction: TSInteraction, transaction: GRDBWriteTransaction)

    func didTouch(interaction: TSInteraction, transaction: GRDBWriteTransaction)
    func didTouch(thread: TSThread, shouldUpdateChatListUi: Bool, transaction: GRDBWriteTransaction)
    func didTouch(storyMessage: StoryMessage, transaction: GRDBWriteTransaction)
}

public class DatabaseChangeObserverImpl: SDSDatabaseChangeObserver {
    public static let kMaxIncrementalRowChanges = 200

    private lazy var nonModelTables: Set<String> = Set([
        PendingReadReceiptRecord.databaseTableName
    ])

    // We protect DatabaseChangeObserver state with an UnfairLock.
    static var hasDatabaseChangeObserverLock: Bool {
        hasDatabaseChangeObserverLockOnCurrentThread
    }

    @ThreadBacked(key: "hasDatabaseChangeObserverLockOnCurrentThread", defaultValue: false)
    fileprivate static var hasDatabaseChangeObserverLockOnCurrentThread: Bool

    private static let databaseChangeObserverLock = UnfairLock()

    public class func serializedSync(block: () -> Void) {
        // UnfairLock is not recursive.
        // In some cases serializedSync() might be re-entrant.
        if hasDatabaseChangeObserverLockOnCurrentThread {
            owsFailDebug("Re-entrant synchronization.")
            block()
            return
        }

        databaseChangeObserverLock.withLock {
            owsAssertDebug(hasDatabaseChangeObserverLockOnCurrentThread == false)
            hasDatabaseChangeObserverLockOnCurrentThread = true
            owsAssertDebug(hasDatabaseChangeObserverLockOnCurrentThread == true)
            block()
            owsAssertDebug(hasDatabaseChangeObserverLockOnCurrentThread == true)
            hasDatabaseChangeObserverLockOnCurrentThread = false
            owsAssertDebug(hasDatabaseChangeObserverLockOnCurrentThread == false)
        }
    }

    @MainActor
    private var _databaseChangeDelegates: [Weak<DatabaseChangeDelegate>] = []

    @MainActor
    private func fetchAndPruneDatabaseChangeDelegates() -> [DatabaseChangeDelegate] {
        _databaseChangeDelegates.removeAll(where: { $0.value == nil })
        return _databaseChangeDelegates.compactMap(\.value)
    }

    @MainActor
    public func appendDatabaseChangeDelegate(_ databaseChangeDelegate: DatabaseChangeDelegate) {
        let append = { [weak self] in
            _ = self?._databaseChangeDelegates.append(Weak(value: databaseChangeDelegate))
        }
        if CurrentAppContext().isRunningTests {
            append()
        } else {
            // Never notify delegates until the app is ready.
            // This prevents us from shooting ourselves in the foot
            // and registering for database changes too early.
            assert(appReadiness.isAppReady)
            appReadiness.runNowOrWhenAppWillBecomeReady(append)
        }
    }

    #if TESTABLE_BUILD
    private var _databaseWriteDelegates: [Weak<DatabaseWriteDelegate>] = []
    private var databaseWriteDelegates: [DatabaseWriteDelegate] {
        return _databaseWriteDelegates.compactMap { $0.value }
    }

    public func appendDatabaseWriteDelegate(_ delegate: DatabaseWriteDelegate) {
        _databaseWriteDelegates = _databaseWriteDelegates.filter { $0.value != nil} + [Weak(value: delegate)]
    }
    #endif

    private var lastPublishUpdatesDate: Date?

    private var displayLink: CADisplayLink?
    private let displayLinkPreferredFramesPerSecond: Int = 20
    private var recentDisplayLinkDates = [Date]()

    fileprivate var pendingChanges = ObservedDatabaseChanges(concurrencyMode: .databaseChangeObserverSerialQueue)

    private static let committedChangesLock = UnfairLock()
    fileprivate var committedChanges = ObservedDatabaseChanges(concurrencyMode: .unfairLock)
    private var hasCommittedChanges: Bool {
        Self.committedChangesLock.withLock {
            !self.committedChanges.isEmpty
        }
    }

    private let appReadiness: AppReadiness

    public var transactionObserver: GRDB.TransactionObserver { self }

    init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveCrossProcessNotification),
                                               name: SDSDatabaseStorage.didReceiveCrossProcessNotificationActiveAsync,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.applicationStateDidChange),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationStateDidChange),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            DispatchQueue.main.async {
                self.ensureDisplayLink()
            }
        }
    }

    // MARK: - Disabling

    /// Should only be written to while holding the database write lock.
    private var isObserving = false

    public func beginObserving(pool: DatabasePool) throws {
        try pool.write { db in
            db.add(transactionObserver: self, extent: .observerLifetime)
            isObserving = true
        }
    }

    public func stopObserving(pool: DatabasePool) throws {
        try pool.write { db in
            db.remove(transactionObserver: self)
            isObserving = false
        }
    }

    public func disable<T>(tx: DBWriteTransaction, during block: (DBWriteTransaction) throws -> T) rethrows -> T {
        guard isObserving else {
            return try block(tx)
        }
        tx.databaseConnection.remove(transactionObserver: self.transactionObserver)
        defer {
            tx.databaseConnection.add(transactionObserver: self, extent: .observerLifetime)
            DispatchQueue.main.async { [weak self] in
                self?.ensureDisplayLink()
            }
        }
        return try block(tx)
    }

    // MARK: -

    private let isDisplayLinkActive = AtomicBool(false, lock: .sharedGlobal)
    private let willRequestDisplayLinkActive = AtomicBool(false, lock: .sharedGlobal)

    private func didModifyPendingChanges() {
        guard !isDisplayLinkActive.get(),
              willRequestDisplayLinkActive.tryToSetFlag() else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.ensureDisplayLink()
        }
    }

    private func ensureDisplayLink() {
        AssertIsOnMainThread()

        guard CurrentAppContext().hasUI else {
            // The NSE never does uiReads, we can skip the display link.
            //
            // TODO: Review.
            return
        }

        let shouldBeActive: Bool = {
            guard isObserving else {
                return false
            }
            let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction
            switch tsRegistrationState {
            case .transferringIncoming, .transferringLinkedOutgoing, .transferringPrimaryOutgoing:
                return false
            default:
                break
            }
            guard appReadiness.isAppReady else {
                return false
            }
            guard !CurrentAppContext().isInBackground() else {
                return false
            }
            if self.hasCommittedChanges {
                return true
            }
            var hasPendingChanges = false
            DatabaseChangeObserverImpl.serializedSync {
                hasPendingChanges = !self.pendingChanges.isEmpty
            }
            if hasPendingChanges {
                return true
            }
            return false
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
            recentDisplayLinkDates.removeAll()
        }
        isDisplayLinkActive.set(shouldBeActive)
    }

    @objc
    @MainActor
    private func displayLinkDidFire() {
        AssertIsOnMainThread()

        recentDisplayLinkDates.append(Date())

        publishUpdatesIfNecessary()
    }

    @objc
    func applicationStateDidChange(_ notification: Notification) {
        AssertIsOnMainThread()

        ensureDisplayLink()
    }

    @MainActor
    private lazy var didUpdateExternallyEvent: DebouncedEvent = {
        return DebouncedEvents.build(
            mode: .firstLast,
            maxFrequencySeconds: 3.0,
            onQueue: .asyncOnQueue(queue: .main),
            notifyBlock: { [weak self] in self?.fireDidUpdateExternally() }
        )
    }()

    @objc
    @MainActor
    private func didReceiveCrossProcessNotification(_ notification: Notification) {
        didUpdateExternallyEvent.requestNotify()
    }

    @MainActor
    private func fireDidUpdateExternally() {
        for delegate in fetchAndPruneDatabaseChangeDelegates() {
            delegate.databaseChangesDidUpdateExternally()
        }
    }
}

// MARK: -

extension DatabaseChangeObserverImpl: TransactionObserver {

    private func observes(eventWithTableName tableName: String) -> Bool {
        if tableName.hasPrefix(FullTextSearchIndexer.contentTableName) {
            return false
        }
        if tableName.hasPrefix(SearchableNameIndexerImpl.Constants.databaseTableName) {
            return false
        }
        if nonModelTables.contains(tableName) {
            // Ignore updates to non-model tables
            return false
        }
        if tableName == "grdb_migrations" {
            return false
        }
        return true
    }

    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        observes(eventWithTableName: eventKind.tableName)
    }

    private func observes(event: DatabaseEvent) -> Bool {
        observes(eventWithTableName: event.tableName)
    }

    // MARK: - SDSDatabaseChangeObserver

    public func updateIdMapping(thread: TSThread, transaction: GRDBWriteTransaction) {
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.insert(thread: thread)
        pendingChanges.insert(tableName: TSThread.table.tableName)

        didModifyPendingChanges()
    }

    public func updateIdMapping(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.insert(interaction: interaction)
        pendingChanges.insert(tableName: TSInteraction.table.tableName)

        didModifyPendingChanges()
    }

    public func didTouch(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.insert(interaction: interaction)
        pendingChanges.insert(tableName: TSInteraction.table.tableName)

        if !pendingChanges.threadUniqueIds.contains(interaction.uniqueThreadId) {
            let interactionThread: TSThread? = interaction.thread(tx: transaction.asAnyRead)
            if let thread = interactionThread {
                didTouch(thread: thread, transaction: transaction)
            } else {
                owsFailDebug("Could not load thread for interaction.")
            }
        }

        if isObserving {
            didModifyPendingChanges()
        }
    }

    /// See note on `shouldUpdateChatListUi` parameter in docs for ``TSGroupThread.updateWithGroupModel:shouldUpdateChatListUi:transaction``.
    public func didTouch(thread: TSThread, shouldUpdateChatListUi: Bool = true, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify its observers
        // in the expected way.
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.insert(thread: thread, shouldUpdateChatListUi: shouldUpdateChatListUi)
        pendingChanges.insert(tableName: TSThread.table.tableName)

        if isObserving {
            didModifyPendingChanges()
        }
    }

    public func didTouch(storyMessage: StoryMessage, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify its observers
        // in the expected way.
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.insert(storyMessage: storyMessage)
        pendingChanges.insert(tableName: StoryMessage.databaseTableName)

        if isObserving {
            didModifyPendingChanges()
        }
    }

    // Database observation operates like so:
    //
    // * This class (DatabaseChangeObserver) observes writes to the database
    //   and publishes them to its "database changes delegates" (usually
    //   per-view observers) updating the views in a controlled,
    //   consistent way.
    // * DatabaseChangeObserver observes all database _changes_ and _commits_.
    // * When a _change_ (modification of database content in a write transaction) occurs:
    //   * This might occur on any thread.
    //   * The changes are aggregated in pendingChanges.
    // * When a _commit_ occurs:
    //   * This might occur on any thread.
    //   * The changes are integrated from pendingChanges into committedChanges
    //   * An "publish updates" is enqueued. Updating views is expensive, so we throttle
    //     publishing of updates so that if many writes occur, views only receive a single
    //     "database did change" event, at the expense of some latency.
    // * When we "publish updates":
    //   * This is done on the main thread.
    //   * All "database change delegates" receive databaseChangesDidUpdate with the changes.
    public func databaseDidChange(with event: DatabaseEvent) {
        // Check before serializedSync() to avoid recursively obtaining the
        // unfairLock when touching.
        guard observes(event: event) else {
            return
        }

        DatabaseChangeObserverImpl.serializedSync {

            pendingChanges.insert(tableName: event.tableName)

            if event.tableName == CallLinkRecord.databaseTableName {
                pendingChanges.insert(tableName: event.tableName, rowId: event.rowID)
            }

            if event.tableName == InteractionRecord.databaseTableName {
                pendingChanges.insert(interactionRowId: event.rowID)
            } else if event.tableName == ThreadRecord.databaseTableName {
                pendingChanges.insert(threadRowId: event.rowID)
            } else if event.tableName == StoryMessage.databaseTableName {
                pendingChanges.insert(storyMessageRowId: event.rowID)
            }

            // We record certain deletions.
            if event.kind == .delete && event.tableName == InteractionRecord.databaseTableName {
                pendingChanges.insert(deletedInteractionRowId: event.rowID)
            }

            #if TESTABLE_BUILD
            for delegate in databaseWriteDelegates {
                delegate.databaseDidChange(with: event)
            }
            #endif
        }

        didModifyPendingChanges()
    }

    // See comment on databaseDidChange.
    public func databaseDidCommit(_ db: Database) {
        DatabaseChangeObserverImpl.serializedSync {
            let pendingChangesToCommit = self.pendingChanges
            self.pendingChanges = ObservedDatabaseChanges(concurrencyMode: .databaseChangeObserverSerialQueue)

            pendingChangesToCommit.finalizePublishedStateAndCopyToCommittedChanges(
                self.committedChanges,
                withLock: Self.committedChangesLock,
                db: db
            )

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

            self.ensureDisplayLink()
            // Try to publish updates immediately.
            self.publishUpdatesIfNecessary()
        }
    }

    // See comment on databaseDidChange.
    @MainActor
    private func publishUpdatesIfNecessary() {
        switch DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
        case .transferringIncoming, .transferringLinkedOutgoing, .transferringPrimaryOutgoing:
            Logger.info("Skipping publishing of updates; transfer in progress.")
            displayLink?.invalidate()
            return
        default:
            break
        }

        if let lastPublishUpdatesDate = self.lastPublishUpdatesDate {
            let secondsSinceLastUpdate = abs(lastPublishUpdatesDate.timeIntervalSinceNow)
            // Don't update UI more often than Nx/second.
            guard secondsSinceLastUpdate >= targetPublishingOfUpdatesInterval else {
                // Don't publish updates yet; we've published recently.
                return
            }
        }

        publishUpdates()
    }

    private var targetPublishingOfUpdatesInterval: Double {
        AssertIsOnMainThread()
        #if TESTABLE_BUILD
        // Don't wait to publish updates in tests
        // because some tests read immediately.
        if CurrentAppContext().isRunningTests { return 0 }
        #endif
        // We want the UI to feel snappy and responsive, which means
        // low latency in view updates.
        //
        // This means updating (and hence the views) as frequently
        // as possible.
        //
        // However, when the app is under heavy load, constantly
        // updating the views is expensive and causes CPU contention,
        // slowing down business logic. The outcome is that the app
        // feels less responsive.
        //
        // Therefore, the app should "back off" and slow the rate at
        // which it updates when it is under heavy load.
        //
        // We measure load using a heuristics: Can the display link
        // maintain its preferred frame rate?
        let maxWindowDuration: TimeInterval = 5 * kSecondInterval
        recentDisplayLinkDates = recentDisplayLinkDates.filter {
            abs($0.timeIntervalSinceNow) < maxWindowDuration
        }

        // These intervals control publishing of updates frequency.
        let fastUpdateInterval: TimeInterval = 1 / TimeInterval(20)
        let slowUpdateInterval: TimeInterval = 1 / TimeInterval(1)

        guard recentDisplayLinkDates.count > 1,
              let firstDisplayLinkDate = recentDisplayLinkDates.first,
              let lastDisplayLinkDate = recentDisplayLinkDates.last,
              firstDisplayLinkDate < lastDisplayLinkDate else {
            // If the display link hasn't been running long enough to have
            // two samples, use the fastest update interval.
            return fastUpdateInterval
        }
        let windowDuration = abs(lastDisplayLinkDate.timeIntervalSinceNow - firstDisplayLinkDate.timeIntervalSinceNow)
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

        // Under light load, we want the fastest update frequency.
        // Under heavy load, we want the slowest update frequency.
        let targetPublishingOfUpdatesInterval = alpha.lerp(fastUpdateInterval, slowUpdateInterval)
        return targetPublishingOfUpdatesInterval
    }

    // "Updating" entails publishing pending database changes to database change observers.
    // See comment on databaseDidChange.
    @MainActor
    private func publishUpdates() {
        let committedChanges = Self.committedChangesLock.withLock { () -> DatabaseChangesSnapshot in
            // Return the current committedChanges.
            let committedChanges = self.committedChanges
            // Create a new committedChanges instance for the next batch
            // of updates.
            self.committedChanges = ObservedDatabaseChanges(concurrencyMode: .unfairLock)
            return committedChanges.snapshot()
        }
        guard !committedChanges.isEmpty else {
            // If there's no new database changes, we don't need to publish updates.
            return
        }

        defer {
            ensureDisplayLink()
        }

        lastPublishUpdatesDate = Date()

        if let lastError = committedChanges.lastError {
            switch lastError {
            case DatabaseObserverError.changeTooLarge:
                // no assertionFailure, we expect this sometimes
                break
            default:
                owsFailDebug("unknown error: \(lastError)")
            }
            for delegate in fetchAndPruneDatabaseChangeDelegates() {
                delegate.databaseChangesDidReset()
            }
        } else {
            for delegate in fetchAndPruneDatabaseChangeDelegates() {
                delegate.databaseChangesDidUpdate(databaseChanges: committedChanges)
            }
        }
    }

    public func databaseDidRollback(_ db: Database) {
        DatabaseChangeObserverImpl.serializedSync {
            pendingChanges = ObservedDatabaseChanges(concurrencyMode: .databaseChangeObserverSerialQueue)

            #if TESTABLE_BUILD
            for delegate in databaseWriteDelegates {
                delegate.databaseDidRollback(db: db)
            }
            #endif
        }
    }
}
