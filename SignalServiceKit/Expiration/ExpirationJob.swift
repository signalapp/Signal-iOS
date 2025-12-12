//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Abstract base class for jobs that need to delete elements as those elements
/// "expire" while the app is running.
///
/// Implementations should override the `open` methods below, pursuant to their
/// documentation.
///
/// When new expiring elements are saved, callers should call ``restart()`` to
/// tell the `ExpirationJob` that the "next-expiring element" may have changed.
open class ExpirationJob<ExpiringElement> {
    struct TestHooks {
        let onWillDelay: (ExpirationJob) -> Void
        let onDidStop: (ExpirationJob) -> Void
    }

    private let dateProvider: DateProvider
    private let db: DB
    private let logger: PrefixedLogger
    private let minIntervalBetweenDeletes: TimeInterval
    private let testHooks: TestHooks?

    private struct State {
        var notificationObservers: [NotificationCenter.Observer] = []

        var delayValidityToken: UInt = 0
        var runLoopTask: Task<Void, Never>?
        var nextExpirationDelayTask: Task<Void, Never>?
    }
    private let state = AtomicValue(State(), lock: .init())

    public init(
        dateProvider: @escaping DateProvider,
        db: DB,
        logger: PrefixedLogger,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.logger = logger
        self.minIntervalBetweenDeletes = 1
        self.testHooks = nil
    }

#if TESTABLE_BUILD
    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        logger: PrefixedLogger,
        minIntervalBetweenDeletes: TimeInterval,
        testHooks: TestHooks,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.logger = logger
        self.minIntervalBetweenDeletes = minIntervalBetweenDeletes
        self.testHooks = testHooks
    }
#endif

    deinit {
        state.get().notificationObservers
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func addNotificationObservers(_ state: inout State) {
        owsPrecondition(state.notificationObservers.isEmpty)

        state.notificationObservers = [
            NotificationCenter.default.addObserver(
                name: .OWSApplicationDidBecomeActive,
                block: { [weak self] _ in
                    self?.start()
                },
            ),
            NotificationCenter.default.addObserver(
                name: .OWSApplicationWillResignActive,
                block: { [weak self] _ in
                    self?.stop()
                },
            ),
            NotificationCenter.default.addObserver(
                name: UIApplication.significantTimeChangeNotification,
                block: { [weak self] _ in
                    self?.restart()
                },
            )
        ]
    }

    // MARK: -

    /// Kick off this expiration job, which then runs indefinitely. Callers are
    /// expected to do this manually once per process lifetime.
    public final func start() {
        state.update { _state in
            if _state.notificationObservers.isEmpty {
                addNotificationObservers(&_state)
            }

            _state.runLoopTask = Task { await runLoop() }
        }
    }

    /// "Restart" a running job, such that it can detect potential new expiring
    /// elements. Callers should do this any time the underlying store of
    /// `ExpiringElement` changes such that expiration status may be affected.
    ///
    /// For example, for the disappearing messages job, this should be called
    /// whenever a message's "expiration timer" starts or may have changed.
    public final func restart() {
        state.update { _state in
            _state.delayValidityToken += 1
            _state.nextExpirationDelayTask?.cancel()
        }
    }

    /// Stop a running job. Callers are not expected to do this manually. Once
    /// this has been called, it is safe to ``start()`` this job again.
    public final func stop() {
        state.update { _state in
            _state.runLoopTask?.cancel()
            _state.nextExpirationDelayTask?.cancel()
        }
    }

    // MARK: -

    /// Returns the next element that will expire, regardless of whether that
    /// element is currently expired.
    open func nextExpiringElement(tx: DBReadTransaction) -> ExpiringElement? {
        owsFail("Must be overridden by subclasses!")
    }

    /// Returns the expiration date of the given element.
    open func expirationDate(ofElement element: ExpiringElement) -> Date {
        owsFail("Must be overridden by subclasses!")
    }

    /// Deletes the given element, which is guaranteed to have expired when this
    /// is called.
    open func deleteExpiredElement(_ element: ExpiringElement, tx: DBWriteTransaction) {
        owsFail("Must be overridden by subclasses!")
    }

    private func runLoop() async {
        let backgroundTask = OWSBackgroundTask(label: logger.prefix)
        defer { backgroundTask.end() }

        while !Task.isCancelled {
            await deleteExpiredElements()

            let delayValidityToken = state.get().delayValidityToken
            let nextExpirationDate: Date = db.read { tx in
                guard let nextExpiringElement = nextExpiringElement(tx: tx) else {
                    return .distantFuture
                }

                return expirationDate(ofElement: nextExpiringElement)
            }

            let nextExpirationDelayTask: Task<Void, Never> = state.update { _state in
                let now = dateProvider()
                var nextExpirationDelay = nextExpirationDate.timeIntervalSince(now)

                if _state.delayValidityToken != delayValidityToken {
                    // If the token has changed, we can't trust the delay we
                    // just computed. Use a minimum delay instead.
                    nextExpirationDelay = 0
                }

                let nextExpirationDelayTask = Task {
                    _ = try? await Task.sleep(nanoseconds: nextExpirationDelay.clampedNanoseconds)
                }
                _state.nextExpirationDelayTask = nextExpirationDelayTask
                return nextExpirationDelayTask
            }

            await withTaskGroup { taskGroup in
                taskGroup.addTask {
                    await nextExpirationDelayTask.value
                }
                taskGroup.addTask { [minIntervalBetweenDeletes] in
                    try? await Task.sleep(nanoseconds: minIntervalBetweenDeletes.clampedNanoseconds)
                }

                testHooks?.onWillDelay(self)
                await taskGroup.waitForAll()
            }
        }

        testHooks?.onDidStop(self)
    }

    private func deleteExpiredElements() async {
        let deletedCount = await TimeGatedBatch.processAllAsync(db: db) { tx in
            if Task.isCancelled {
                // We're cancelled: we'll get to any remaining elements later.
                return 0
            }

            if
                let nextExpiringElement = nextExpiringElement(tx: tx),
                dateProvider() >= expirationDate(ofElement: nextExpiringElement)
            {
                // Expired element: delete it and keep iterating.
                deleteExpiredElement(nextExpiringElement, tx: tx)
                return 1
            } else {
                // Nothing expired to delete: stop iterating.
                return 0
            }
        }

        if deletedCount > 0 {
            logger.info("Deleted \(deletedCount) elements.")
        }
    }
}
