//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct CronContext {
    public var chatConnectionManager: any ChatConnectionManager
    public var tsAccountManager: any TSAccountManager

    public init(
        chatConnectionManager: any ChatConnectionManager,
        tsAccountManager: any TSAccountManager,
    ) {
        self.chatConnectionManager = chatConnectionManager
        self.tsAccountManager = tsAccountManager
    }
}

private let dateStore = NewKeyValueStore(collection: "Cron")

struct CronStore {
    private let uniqueKey: Cron.UniqueKey

    init(uniqueKey: Cron.UniqueKey) {
        self.uniqueKey = uniqueKey
    }

    /// The most recent completion date (or `.distantPast`).
    func mostRecentDate(tx: DBReadTransaction) -> Date {
        return dateStore.fetchValue(
            Date.self,
            forKey: self.uniqueKey.rawValue,
            tx: tx,
        ) ?? .distantPast
    }

    /// Marks the task as "complete".
    ///
    /// - Parameter jitter: The maxmimum amount of random jitter added
    /// to/subtracted from `now`. Helps distribute load/avoid spikes.
    func setMostRecentDate(_ now: Date, jitter: TimeInterval, tx: DBWriteTransaction) {
        dateStore.writeValue(
            now.addingTimeInterval(TimeInterval.random(in: -jitter...jitter)),
            forKey: self.uniqueKey.rawValue,
            tx: tx,
        )
    }
}

public class Cron {
    private let appVersion: AppVersionNumber4
    private let db: any DB
    private let metadataStore: NewKeyValueStore
    private let jobs: AtomicValue<[(CronContext) async -> Void]>

    public static let jitterFactor: Double = 20

    /// Unique keys that identify Cron jobs.
    ///
    /// All state related to these keys is cleared when the app's version number
    /// changes. These are therefore safe to add/remove/rename without migrating
    /// anything that's been written to disk. (This statement is not true for
    /// local builds, but it's true for all TestFlight/App Store builds.)
    public enum UniqueKey: String {
        case checkUsername
        case cleanUpMessageSendLog
        case cleanUpOrphanedData
        case cleanUpViewOnceMessages
        case fetchDevices
        case fetchEmojiSearch
        case fetchLocalProfile
        case fetchMegaphones
        case fetchSenderCertificates
        case fetchStaleGroup
        case fetchStaleProfiles
        case fetchStorageService
        case fetchSubscriptionConfig
        case refreshBackup
        case updateAttributes
    }

    init(
        appVersion: AppVersionNumber4,
        db: any DB,
    ) {
        self.appVersion = appVersion
        self.db = db
        self.metadataStore = NewKeyValueStore(collection: "CronM")
        self.jobs = AtomicValue([], lock: .init())
    }

    /// Schedules `operation` to run periodically.
    ///
    /// The `operation` will be run every `approximateInterval` seconds or so.
    /// It may be run more frequently than `approximateInterval` seconds, and
    /// therefore `operation`s must be safe to invoke at shorter intervals.
    ///
    /// Guarantees:
    ///
    /// - When `mustBe...` values are true, the job "waits" until the conditions
    /// are met before invoking `operation`. For example, if `mustBeConnected`
    /// is true, the job will wait until the web socket is connected before
    /// invoking `operation`.
    ///
    /// - The `operation` will be re-run whenever the app's version number
    /// changes. This helps ensure that bugs fixed directly in Cron jobs are
    /// mitigated quickly in new versions, but it also ensures indirect bug
    /// fixes are mitigated quickly. (If you fix a bug on purpose, you can trust
    /// that users who update will apply the fix immediately; if you fix a bug
    /// without realizing it, users who update will also apply it immediately.)
    ///
    /// - The `operation` is integrated with the UIBackgroundTask
    /// infrastructure; a background task assertion will be held whenever
    /// `operation` is executing, and `operation` will be canceled when
    /// background execution time expires.
    ///
    /// - Parameter uniqueKey: The identifier for a job that's used to store the
    /// time at which the job was most recently executed.
    ///
    /// - Parameter approximateInterval: The suggested interval between
    /// invocations of `operation`. It may run more quickly (e.g., when you
    /// update the app) or more slowly (e.g., you didn't launch the app for a
    /// week). The Cron system also imposes random jitter of ±5%.
    ///
    /// - Parameter mustBeRegistered: If true, `operation` won't be invoked
    /// until the user is registered.
    ///
    /// - Parameter mustBeConnected: If true, `operation` won't be invoked until
    /// the user is connected.
    ///
    /// - Parameter isRetryable: Whether or not an error thrown by `operation`
    /// should be retried "quickly". If true, `operation` will be invoked
    /// repeatedly with exponential backoff, up to a maximum average backoff of
    /// `approximateInterval`. If false, this attempt will be marked complete,
    /// and the next attempt won't start until after `approximateInterval`.
    public func schedulePeriodically<E>(
        uniqueKey: UniqueKey,
        approximateInterval: TimeInterval,
        mustBeRegistered: Bool,
        mustBeConnected: Bool,
        isRetryable: @escaping (E) -> Bool = { $0.isRetryable },
        operation: @escaping () async throws(E) -> Void,
    ) {
        let store = CronStore(uniqueKey: uniqueKey)
        scheduleFrequently(
            mustBeRegistered: mustBeRegistered,
            mustBeConnected: mustBeConnected,
            maxAverageBackoff: approximateInterval,
            isRetryable: isRetryable,
            operation: { [db] () async throws(E) -> Bool in
                let mostRecentDate = db.read(block: store.mostRecentDate(tx:))
                let earliestNextDate = mostRecentDate.addingTimeInterval(approximateInterval)
                if Date() < earliestNextDate {
                    return false
                }
                Logger.info("job \(uniqueKey) starting")
                try await operation()
                return true
            },
            handleResult: { [db] result in
                switch result {
                case .failure(is NotRegisteredError), .success(false), .failure(is CancellationError):
                    // A requirement (e.g., mustBeRegistered) wasn't met, it's too early to run
                    // again, or we were canceled while running. Don't set any state so that we
                    // run again at the next opportunity.
                    break
                case .success(true), .failure:
                    // We ran or hit a terminal error while trying to run; mark the job as
                    // completed so that we wait for `approximateInterval` before retrying.
                    Logger.info("job \(uniqueKey) reached terminal result: \(result)")
                    await db.awaitableWrite { tx in
                        store.setMostRecentDate(Date(), jitter: approximateInterval / Self.jitterFactor, tx: tx)
                    }
                }
            },
        )
    }

    /// Schedules `operation` to run "frequently".
    ///
    /// - Warning: Operations scheduled via this mechanism are executed
    /// extremely frequently and must implement their own logic to check whether
    /// or not it's necessary to execute. They should turn into no-ops most of
    /// the time. Most callers should prefer `schedulePeriodically`.
    ///
    /// "Frequently" means that `operation` is executed every time the app
    /// launches, every time the app enters the foreground, every time the
    /// notification service is triggered, and every time the user registers. In
    /// the future, it may also mean that `operation` is executed during
    /// background app refresh and "content-available" pushes.
    ///
    /// This method is similar to `Retry.performWithBackoff` and exposes many of
    /// the same parameters. However, whereas `Retry.performWithBackoff` stops
    /// entirely after encountering a non-`isRetryable` error, this method
    /// restarts automatically after the next "frequent" event.
    ///
    /// The `operation` is integrated with the UIBackgroundTask infrastructure;
    /// a background task assertion will be held whenever `operation` is
    /// executing, and `operation` will be canceled when background execution
    /// time expires.
    ///
    /// This method is a generalized version of `schedulePeriodically` that may
    /// be useful for callers who want to implement more complex triggers.
    ///
    /// - Parameter mustBeRegistered: If true, `operation` won't be invoked
    /// until the user is registered.
    ///
    /// - Parameter mustBeConnected: If true, `operation` won't be invoked until
    /// the user is connected.
    ///
    /// - Parameter minAverageBackoff: See `Retry.performWithBackoff`.
    ///
    /// - Parameter maxAverageBackoff: See `Retry.performWithBackoff`.
    ///
    /// - Parameter isRetryable: Whether or not an error thrown by `operation`
    /// should be retried "quickly". If true, `operation` will be invoked
    /// repeatedly with exponential backoff. If false, this attempt will stop,
    /// `handleResult` will be invoked, and the next attempt won't start until
    /// the next "frequent" trigger.
    ///
    /// - Parameter handleResult: Invoked when an "attempt" (started after a
    /// "frequent" event) reaches a terminal state. A "terminal state" is any
    /// outcome other than `operation` throwing an `isRetryable` error (e.g.,
    /// `operation` running to completion or being canceled while waiting for
    /// exponential backoff after an `isRetryable` error). The `Result` is `any
    /// Error` to handle `CancellationError`s (from `Retry` and waiting for the
    /// network) and `NotRegisteredError`s that may be thrown.
    public func scheduleFrequently<T, E>(
        mustBeRegistered: Bool,
        mustBeConnected: Bool,
        minAverageBackoff: TimeInterval = 2,
        maxAverageBackoff: TimeInterval = .infinity,
        isRetryable: @escaping (E) -> Bool = { $0.isRetryable },
        operation: @escaping () async throws(E) -> T,
        handleResult: @escaping (Result<T, any Error>) async -> Void,
    ) {
        self.jobs.update {
            $0.append({ ctx async -> Void in
                let attemptResult = await Self.runOuterOperationAttempt(
                    mustBeRegistered: mustBeRegistered,
                    mustBeConnected: mustBeConnected,
                    minAverageBackoff: minAverageBackoff,
                    maxAverageBackoff: maxAverageBackoff,
                    isRetryable: isRetryable,
                    operation: operation,
                    ctx: ctx,
                )
                await handleResult(attemptResult)
            })
        }
    }

    /// Runs an "outer" attempt.
    ///
    /// An "outer" attempt may invoke `operation` multiple times. It's triggered
    /// by a "frequent" event (e.g., foregrounding the app). It uses
    /// Retry.performWithBackoff to execute `operation` until it succeeds or
    /// throws a non-`isRetryable` error.
    private static func runOuterOperationAttempt<T, E>(
        mustBeRegistered: Bool,
        mustBeConnected: Bool,
        minAverageBackoff: TimeInterval,
        maxAverageBackoff: TimeInterval,
        isRetryable: (E) -> Bool,
        operation: () async throws(E) -> T,
        ctx: CronContext,
    ) async -> Result<T, any Error> {
        do {
            return try await Retry.performWithBackoff(
                maxAttempts: .max,
                minAverageBackoff: minAverageBackoff,
                maxAverageBackoff: maxAverageBackoff,
                isRetryable: isRetryable,
                block: { () throws(E) -> Result<T, any Error> in
                    return try await runInnerOperationAttempt(
                        mustBeRegistered: mustBeRegistered,
                        mustBeConnected: mustBeConnected,
                        operation: operation,
                        ctx: ctx,
                    )
                },
            )
        } catch {
            // We may have gotten a CancellationError from Retry, or we may have gotten
            // a non-`isRetryable` error. These are all terminal failures for this
            // attempt; we pass those to `handleResult` and stop executing until the
            // next time we're triggered.
            return .failure(error)
        }
    }

    /// Runs an "inner" attempt.
    ///
    /// An "inner" attempt is a single invocation of `operation`. If "mustBe..."
    /// preconditions aren't satisfied, this method may throw an error before
    /// `operation` is invoked. All errors are immediately rethrown.
    private static func runInnerOperationAttempt<T, E>(
        mustBeRegistered: Bool,
        mustBeConnected: Bool,
        operation: () async throws(E) -> T,
        ctx: CronContext,
    ) async throws(E) -> Result<T, any Error> {
        // Before each attempt, wait until the network is available.
        do throws(CancellationError) {
            if mustBeConnected {
                if mustBeRegistered {
                    try await ctx.chatConnectionManager.waitForIdentifiedConnectionToOpen()
                } else {
                    try await ctx.chatConnectionManager.waitForUnidentifiedConnectionToOpen()
                }
            }
        } catch {
            return .failure(error)
        }

        // Before each attempt, check if we're registered.
        if mustBeRegistered, !ctx.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
            return .failure(NotRegisteredError())
        }

        return .success(try await operation())
    }

    private func checkForNewVersion() async {
        let appVersionKey = "AppVersion"

        let mostRecentAppVersion = self.db.read { tx in
            return self.metadataStore.fetchValue(String.self, forKey: appVersionKey, tx: tx)
        }
        if mostRecentAppVersion != self.appVersion.wrappedValue.rawValue {
            await self.db.awaitableWrite { tx in
                self.resetMostRecentDates(tx: tx)
                self.metadataStore.writeValue(self.appVersion.wrappedValue.rawValue, forKey: appVersionKey, tx: tx)
            }
        }
    }

    public func resetMostRecentDates(tx: DBWriteTransaction) {
        dateStore.removeAll(tx: tx)
    }

    public func runOnce(ctx: CronContext) async {
        await self.checkForNewVersion()
        await withTaskGroup { taskGroup in
            for job in self.jobs.get() {
                taskGroup.addTask { await job(ctx) }
            }
            await taskGroup.waitForAll()
        }
    }
}
