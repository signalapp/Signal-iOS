//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

@objc
public protocol DatabaseChangeDelegate: AnyObject {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges)
    func databaseChangesDidUpdateExternally()
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
    assert(DatabaseChangeObserver.hasDatabaseChangeObserverLock)
}

// MARK: -

@objc
public class DatabaseChangeObserver: NSObject {
    public static let kMaxIncrementalRowChanges = 200

    private lazy var nonModelTables: Set<String> = Set([
        MediaGalleryRecord.databaseTableName,
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

    private var _databaseChangeDelegates: [Weak<DatabaseChangeDelegate>] = []
    private var databaseChangeDelegates: [DatabaseChangeDelegate] {
        return _databaseChangeDelegates.compactMap { $0.value }
    }

    func appendDatabaseChangeDelegate(_ databaseChangeDelegate: DatabaseChangeDelegate) {
        let append = { [weak self] in
            guard let self = self else {
                return
            }
            self._databaseChangeDelegates = self._databaseChangeDelegates.filter { $0.value != nil} + [Weak(value: databaseChangeDelegate)]
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

    #if TESTABLE_BUILD
    private var _databaseWriteDelegates: [Weak<DatabaseWriteDelegate>] = []
    private var databaseWriteDelegates: [DatabaseWriteDelegate] {
        return _databaseWriteDelegates.compactMap { $0.value }
    }

    func appendDatabaseWriteDelegate(_ delegate: DatabaseWriteDelegate) {
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

    required override init() {
        super.init()

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

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            DispatchQueue.main.async {
                self.ensureDisplayLink()
            }
        }
    }

    private let isDisplayLinkActive = AtomicBool(false)
    private let willRequestDisplayLinkActive = AtomicBool(false)

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
            guard AppReadiness.isAppReady, !tsAccountManager.isTransferInProgress else {
                return false
            }
            guard !CurrentAppContext().isInBackground() else {
                return false
            }
            if self.hasCommittedChanges {
                return true
            }
            var hasPendingChanges = false
            DatabaseChangeObserver.serializedSync {
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
    func displayLinkDidFire() {
        AssertIsOnMainThread()

        recentDisplayLinkDates.append(Date())

        publishUpdatesIfNecessary()
    }

    @objc
    func applicationStateDidChange(_ notification: Notification) {
        AssertIsOnMainThread()

        ensureDisplayLink()
    }

    private lazy var didUpdateExternallyEvent: DebouncedEvent = {
        AssertIsOnMainThread()

        return DebouncedEvents.build(mode: .firstLast,
                                     maxFrequencySeconds: 3.0,
                                     onQueue: .asyncOnQueue(queue: .main)) { [weak self] in
            guard let self = self else { return }
            self.fireDidUpdateExternally()
        }
    }()

    @objc
    func didReceiveCrossProcessNotification(_ notification: Notification) {
        AssertIsOnMainThread()
        Logger.verbose("")

        didUpdateExternallyEvent.requestNotify()
    }

    private func fireDidUpdateExternally() {
        AssertIsOnMainThread()
        Logger.verbose("")

        for delegate in databaseChangeDelegates {
            delegate.databaseChangesDidUpdateExternally()
        }
    }
}

// MARK: -

extension DatabaseChangeObserver: TransactionObserver {

    private func observes(eventWithTableName tableName: String) -> Bool {
        guard !tableName.hasPrefix(GRDBFullTextSearchFinder.contentTableName) else {
            return false
        }
        guard !nonModelTables.contains(tableName) else {
            // Ignore updates to non-model tables
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

    // This should only be called by DatabaseStorage.
    func updateIdMapping(thread: TSThread, transaction: GRDBWriteTransaction) {
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.append(thread: thread)
        pendingChanges.append(tableName: TSThread.table.tableName)

        didModifyPendingChanges()
    }

    // This should only be called by DatabaseStorage.
    func updateIdMapping(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.append(interaction: interaction)
        pendingChanges.append(tableName: TSInteraction.table.tableName)

        didModifyPendingChanges()
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.append(interaction: interaction)
        pendingChanges.append(tableName: TSInteraction.table.tableName)

        if !pendingChanges.threadUniqueIds.contains(interaction.uniqueThreadId) {
            let interactionThread: TSThread? = interaction.thread(tx: transaction.asAnyRead)
            if let thread = interactionThread {
                didTouch(thread: thread, transaction: transaction)
            } else {
                owsFailDebug("Could not load thread for interaction.")
            }
        }

        didModifyPendingChanges()
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(thread: TSThread, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.append(thread: thread)
        pendingChanges.append(tableName: TSThread.table.tableName)

        didModifyPendingChanges()
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(storyMessage: StoryMessage, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify its observers
        // in the expected way.
        AssertHasDatabaseChangeObserverLock()

        pendingChanges.append(storyMessage: storyMessage)
        pendingChanges.append(tableName: StoryMessage.databaseTableName)

        didModifyPendingChanges()
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

        DatabaseChangeObserver.serializedSync {

            pendingChanges.append(tableName: event.tableName)

            if event.tableName == InteractionRecord.databaseTableName {
                pendingChanges.append(interactionRowId: event.rowID)
            } else if event.tableName == ThreadRecord.databaseTableName {
                pendingChanges.append(threadRowId: event.rowID)
            } else if event.tableName == StoryMessage.databaseTableName {
                pendingChanges.append(storyMessageRowId: event.rowID)
            }

            // We record certain deletions.
            if event.kind == .delete && event.tableName == InteractionRecord.databaseTableName {
                pendingChanges.append(deletedInteractionRowId: event.rowID)
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
        DatabaseChangeObserver.serializedSync {
            let pendingChangesToCommit = self.pendingChanges
            self.pendingChanges = ObservedDatabaseChanges(concurrencyMode: .databaseChangeObserverSerialQueue)

            do {
                // finalizePublishedState() finalizes the state we're about to
                // copy.
                try pendingChangesToCommit.finalizePublishedState(db: db)

                let interactionUniqueIds = pendingChangesToCommit.interactionUniqueIds
                let threadUniqueIds = pendingChangesToCommit.threadUniqueIds
                let storyMessageUniqueIds = pendingChangesToCommit.storyMessageUniqueIds
                let storyMessageRowIds = pendingChangesToCommit.storyMessageRowIds
                let interactionDeletedUniqueIds = pendingChangesToCommit.interactionDeletedUniqueIds
                let storyMessageDeletedUniqueIds = pendingChangesToCommit.storyMessageDeletedUniqueIds
                let collections = pendingChangesToCommit.collections
                let tableNames = pendingChangesToCommit.tableNames

                Self.committedChangesLock.withLock {
                    self.committedChanges.append(interactionUniqueIds: interactionUniqueIds)
                    self.committedChanges.append(threadUniqueIds: threadUniqueIds)
                    self.committedChanges.append(storyMessageUniqueIds: storyMessageUniqueIds)
                    self.committedChanges.append(storyMessageRowIds: storyMessageRowIds)
                    self.committedChanges.append(interactionDeletedUniqueIds: interactionDeletedUniqueIds)
                    self.committedChanges.append(storyMessageDeletedUniqueIds: storyMessageDeletedUniqueIds)
                    self.committedChanges.append(collections: collections)
                    self.committedChanges.append(tableNames: tableNames)
                }
            } catch {
                Self.committedChangesLock.withLock {
                    self.committedChanges.setLastError(error)
                }
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

            self.ensureDisplayLink()
            // Try to publish updates immediately.
            self.publishUpdatesIfNecessary()
        }
    }

    // See comment on databaseDidChange.
    private func publishUpdatesIfNecessary() {
        AssertIsOnMainThread()

        guard !tsAccountManager.isTransferInProgress else {
            Logger.info("Skipping publishing of updates; transfer in progress.")
            displayLink?.invalidate()
            return
        }

        if let lastPublishUpdatesDate = self.lastPublishUpdatesDate {
            let secondsSinceLastUpdate = abs(lastPublishUpdatesDate.timeIntervalSinceNow)
            // Don't update UI more often than Nx/second.
            guard secondsSinceLastUpdate >= targetPublishingOfUpdatesInterval else {
                // Don't publish updates yet; we've published recently.
                return
            }
        }

        publishUpdates(shouldPublishIfEmpty: false)
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

    // NOTE: This should only be used in exceptional circumstances,
    // e.g. after reloading the database due to a device transfer.
    func publishUpdatesImmediately() {
        AssertIsOnMainThread()

        publishUpdates(shouldPublishIfEmpty: true)
    }

    // "Updating" entails publishing pending database changes to database change observers.
    // See comment on databaseDidChange.
    private func publishUpdates(shouldPublishIfEmpty: Bool) {
        AssertIsOnMainThread()

        let committedChanges = Self.committedChangesLock.withLock { () -> ObservedDatabaseChanges in
            // Return the current committedChanges.
            let committedChanges = self.committedChanges
            // Create a new committedChanges instance for the next batch
            // of updates.
            self.committedChanges = ObservedDatabaseChanges(concurrencyMode: .unfairLock)
            return committedChanges
        }
        guard !committedChanges.isEmpty ||
                shouldPublishIfEmpty else {
            // If there's no new database changes, we don't need to publish updates.
            return
        }

        defer {
            ensureDisplayLink()
        }

        lastPublishUpdatesDate = Date()

        Logger.verbose("databaseChangesDidUpdate")

        if let lastError = committedChanges.lastError {
            switch lastError {
            case DatabaseObserverError.changeTooLarge:
                // no assertionFailure, we expect this sometimes
                break
            default:
                owsFailDebug("unknown error: \(lastError)")
            }
            for delegate in self.databaseChangeDelegates {
                delegate.databaseChangesDidReset()
            }
        } else {
            for delegate in databaseChangeDelegates {
                delegate.databaseChangesDidUpdate(databaseChanges: committedChanges)
            }
        }
    }

    public func databaseDidRollback(_ db: Database) {
        owsFailDebug("TODO: test this if we ever use it.")

        DatabaseChangeObserver.serializedSync {
            pendingChanges = ObservedDatabaseChanges(concurrencyMode: .databaseChangeObserverSerialQueue)

            #if TESTABLE_BUILD
            for delegate in databaseWriteDelegates {
                delegate.databaseDidRollback(db: db)
            }
            #endif
        }
    }
}
