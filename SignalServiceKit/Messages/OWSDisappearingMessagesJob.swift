//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public final class OWSDisappearingMessagesJob: NSObject {

    private static let serialQueue = DispatchQueue(label: "org.signal.disappearing-messages", autoreleaseFrequency: .workItem)

    // TODO: Rename to databaseStorage when this type no longer extends NSObject
    private let myDatabaseStorage: SDSDatabaseStorage
    private var applicationDidBecomeActiveObserver: (any NSObjectProtocol)!
    private var applicationWillResignActiveObserver: (any NSObjectProtocol)!

    @MainActor
    private var hasStarted: Bool = false

    @MainActor
    private var nextDisappearanceTimer: Timer?

    @MainActor
    private var nextDisappearanceDate: Date?

    @MainActor
    private var fallbackTimer: Timer?

    private let appReadiness: AppReadiness

    init(appReadiness: AppReadiness, databaseStorage: SDSDatabaseStorage) {
        self.appReadiness = appReadiness
        self.myDatabaseStorage = databaseStorage

        super.init()

        SwiftSingletons.register(self)

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { @MainActor in
            self.fallbackTimer = .scheduledTimer(withTimeInterval: 5 * kMinuteInterval, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }

                // scheduledTimer promises to call this block on the current runloop which was main actor so this should also be MainActor
                MainActor.assumeIsolated {
                    self.fallbackTimerDidFire()
                }
            }
        }

        self.applicationDidBecomeActiveObserver = NotificationCenter.default.addObserver(forName: .OWSApplicationDidBecomeActive, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.applicationDidBecomeActive()
            }
        }
        self.applicationWillResignActiveObserver = NotificationCenter.default.addObserver(forName: .OWSApplicationWillResignActive, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.applicationWillResignActive()
            }
        }
    }

    deinit {
        fallbackTimer?.invalidate()
        nextDisappearanceTimer?.invalidate()
        NotificationCenter.default.removeObserver(applicationDidBecomeActiveObserver!)
        NotificationCenter.default.removeObserver(applicationWillResignActiveObserver!)
    }

    @objc(startAnyExpirationForMessage:expirationStartedAt:transaction:)
    func startAnyExpiration(for message: TSMessage, expirationStartedAt: UInt64, transaction: SDSAnyWriteTransaction) {
        guard message.shouldStartExpireTimer() else { return }

        // Don't clobber if multiple actions simultaneously triggered expiration.
        if message.expireStartedAt == 0 || message.expireStartedAt > expirationStartedAt {
            message.updateWithExpireStarted(at: expirationStartedAt, transaction: transaction)
        }

        transaction.addAsyncCompletionOffMain { [self] in
            // Necessary that the async expiration run happens *after* the message is saved with it's new
            // expiration configuration.
            scheduleRun(by: message.expiresAt)
        }
    }

    /// - Parameter timestamp: milliseconds since the unix epoch
    func scheduleRun(by timestamp: UInt64) {
        scheduleRun(by: Date(millisecondsSince1970: timestamp))
    }

    private func scheduleRun(by date: Date) {
        DispatchQueue.main.async { [self] in
            // Don't schedule run when inactive or not in main app.
            guard CurrentAppContext().isMainAppAndActive else { return }

            // Don't run more often than once per second.
            let kMinDelaySeconds: TimeInterval = 1.0
            let delaySeconds = max(kMinDelaySeconds, date.timeIntervalSinceNow)
            let newTimerScheduleDate = Date(timeIntervalSinceNow: delaySeconds)

            // don't do anything if this timer would be later than the next one
            guard nextDisappearanceDate == nil || nextDisappearanceDate! > newTimerScheduleDate else {
                return
            }

            // Update Schedule
            resetNextDisapperanceTimer()
            nextDisappearanceDate = newTimerScheduleDate
            nextDisappearanceTimer = .scheduledTimer(withTimeInterval: delaySeconds, repeats: false) { [weak self] _ in
                // scheduledTimer promises to call this block on the current runloop which was main actor so this should also be MainActor
                MainActor.assumeIsolated {
                    self?.disapperanceTimerDidFire()
                }
            }
        }
    }

    /// Clean up any messages that expired since last launch immediately
    /// and continue cleaning in the background.
    public func startIfNecessary() {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [self] in
            guard !hasStarted else { return }
            guard !Self.isDatabaseCorrupted() else { return }
            hasStarted = true
            Self.serialQueue.async { [self] in
                cleanUpMessagesWhichFailedToStartExpiringWithSneakyTransaction()
                _ = runLoop()
            }
        }
    }

    #if TESTABLE_BUILD
    func syncPassForTests() {
        Self.serialQueue.sync {
            _ = self.runLoop()
        }
    }
    #endif

    @MainActor
    private func resetNextDisapperanceTimer() {
        nextDisappearanceTimer?.invalidate()
        nextDisappearanceTimer = nil
        nextDisappearanceDate = nil
    }

    // MARK: - Run Loop

    /// deletes any expired messages and schedules the next run.
    private func runLoop() -> Int {
        dispatchPrecondition(condition: .onQueue(Self.serialQueue))
        let backgroundTask = OWSBackgroundTask(label: "\(#fileID)/\(#function)")
        defer { backgroundTask.end() }

        var deletedCount = 0
        do {
            deletedCount += try deleteAllExpiredMessages()
            deletedCount += try deleteAllExpiredStories()
        } catch {
            owsFailDebug("Couldn't delete expired messages/stories: \(error)")
        }

        let nextExpirationAt = myDatabaseStorage.read { tx in
            return [
                DisappearingMessagesFinder().nextExpirationTimestamp(transaction: tx),
                StoryManager.nextExpirationTimestamp(transaction: tx)
            ].compacted().min()
        }
        if let nextExpirationAt {
            scheduleRun(by: nextExpirationAt)
        }

        return deletedCount
    }

    // MARK: - Application Lifecycle Callbacks

    @MainActor
    private func applicationDidBecomeActive() {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Self.serialQueue.async {
                _ = self.runLoop()
            }
        }
    }

    @MainActor
    private func applicationWillResignActive() {
        resetNextDisapperanceTimer()
    }

    // MARK: - Timer Callbacks

    @MainActor
    private func disapperanceTimerDidFire() {
        guard CurrentAppContext().isMainAppAndActive else {
            // Don't schedule run when inactive or not in main app.
            owsFailDebug("Disappearing messages job timer fired while main app inactive.")
            return
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { @MainActor in
            self.resetNextDisapperanceTimer()
            Self.serialQueue.async {
                _ = self.runLoop()
            }
        }
    }

    @MainActor
    private func fallbackTimerDidFire() {
        guard CurrentAppContext().isMainAppAndActive else {
            return
        }

        // converted from objc...
        // apparently recently means within the last second; although not having one set is apparently also true
        let recentlyScheduledDisappearanceTimer = fabs(self.nextDisappearanceDate?.timeIntervalSinceNow ?? 0.0) < 1.0

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            Self.serialQueue.async {
                let deletedCount = self.runLoop()

                // Normally deletions should happen via the disappearanceTimer, to make sure that they're prompt.
                // So, if we're deleting something via this fallback timer, something may have gone wrong. The
                // exception is if we're in close proximity to the disappearanceTimer, in which case a race condition
                // is inevitable.
                if !recentlyScheduledDisappearanceTimer && deletedCount > 0 {
                    owsFailDebug("unexpectedly deleted disappearing messages via fallback timer.")
                }
            }
        }
    }

    /// Is the database corrupted? If so, we don't want to start the job.
    ///
    /// This is most likely to happen outside the main app, like in an extension, where we might not
    /// check for corruption before marking the app ready.
    private static func isDatabaseCorrupted() -> Bool {
        return DatabaseCorruptionState(userDefaults: CurrentAppContext().appUserDefaults())
            .status
            .isCorrupted
    }

    private enum Constants {
        static let fetchCount = 50
    }

    private func deleteAllExpiredMessages() throws -> Int {
        let db = DependenciesBridge.shared.db
        let count = try TimeGatedBatch.processAll(db: db) { tx in try deleteSomeExpiredMessages(tx: tx) }
        if count > 0 { Logger.info("Deleted \(count) expired messages") }
        return count
    }

    private func deleteSomeExpiredMessages(tx: DBWriteTransaction) throws -> Int {
        let sdsTx = SDSDB.shimOnlyBridge(tx)
        let now = Date.ows_millisecondTimestamp()
        let rowIds = try InteractionFinder.fetchSomeExpiredMessageRowIds(now: now, limit: Constants.fetchCount, tx: sdsTx)
        for rowId in rowIds {
            guard let message = InteractionFinder.fetch(rowId: rowId, transaction: sdsTx) else {
                // We likely hit a database error that's not exposed to us. It's important
                // that we stop in this case to avoid infinite loops.
                throw OWSAssertionError("Couldn't fetch message that must exist.")
            }
            DependenciesBridge.shared.interactionDeleteManager
                .delete(message, sideEffects: .default(), tx: tx)
        }
        return rowIds.count
    }

    private func deleteAllExpiredStories() throws -> Int {
        let db = DependenciesBridge.shared.db
        let count = try TimeGatedBatch.processAll(db: db) { tx in try deleteSomeExpiredStories(tx: tx) }
        if count > 0 { Logger.info("Deleted \(count) expired stories") }
        return count
    }

    private func deleteSomeExpiredStories(tx: DBWriteTransaction) throws -> Int {
        let tx = SDSDB.shimOnlyBridge(tx)
        let now = Date.ows_millisecondTimestamp()
        let storyMessages = try StoryFinder.fetchSomeExpiredStories(now: now, limit: Constants.fetchCount, tx: tx)
        for storyMessage in storyMessages {
            storyMessage.anyRemove(transaction: tx)
        }
        return storyMessages.count
    }

    private func cleanUpMessagesWhichFailedToStartExpiringWithSneakyTransaction() {
        myDatabaseStorage.write { tx in
            let messageIds = DisappearingMessagesFinder().fetchAllMessageUniqueIdsWhichFailedToStartExpiring(tx: tx)
            for messageId in messageIds {
                guard let message = TSMessage.anyFetchMessage(uniqueId: messageId, transaction: tx) else {
                    owsFailDebug("Missing message.")
                    continue
                }
                // We don't know when it was actually read, so assume it was read as soon as it was received.
                let readTimeBestGuess = message.receivedAtTimestamp
                startAnyExpiration(for: message, expirationStartedAt: readTimeBestGuess, transaction: tx)
            }
        }
    }
}
