//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Reponsible for "disabling Backups": making the relevant API calls and
/// managing state.
class BackupDisablingManager {
    struct NotRegisteredError: Error {}

    private enum StoreKeys {
        static let attemptingDisableRemotely = "attemptingDisableRemotely"
        static let remoteDisablingFailed = "remoteDisablingFailed"
    }

    private let backupIdManager: BackupIdManager
    private let backupPlanManager: BackupPlanManager
    private let db: DB
    private let kvStore: KeyValueStore
    private let logger: PrefixedLogger
    private let taskQueue: ConcurrentTaskQueue
    private let tsAccountManager: TSAccountManager

    /// Tracks async work to disable remotely, if necessary. Calls to `.run()`
    /// will (almost-)insta-complete if disabling remotely is not necessary.
    private var disableRemotelyIfNecessaryTask: DebouncedTask<Void>!

    init(
        backupIdManager: BackupIdManager,
        backupPlanManager: BackupPlanManager,
        db: DB,
        tsAccountManager: TSAccountManager,
    ) {
        self.backupIdManager = backupIdManager
        self.backupPlanManager = backupPlanManager
        self.db = db
        self.kvStore = KeyValueStore(collection: "BackupDisablingManager")
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)
        self.tsAccountManager = tsAccountManager

        self.disableRemotelyIfNecessaryTask = DebouncedTask { [weak self] in
            guard let self else { return }

            do {
                if try await _disableRemotelyIfNecessaryWithIndefiniteNetworkRetries() {
                    logger.info("Disabled Backups remotely.")
                }
            } catch {
                await db.awaitableWrite { tx in
                    self.kvStore.setBool(true, key: StoreKeys.remoteDisablingFailed, transaction: tx)
                }

                logger.error("Failed to disable Backups remotely! \(error)")
                throw error
            }
        }
    }

    // MARK: -

    enum DisableRemotelyState {
        case inProgress(Task<Void, Error>)
        case previouslyFailed
    }

    /// Disable Backups for the current user. Backups are immediately disabled
    /// locally, with disabling remotely kicked off asynchronously.
    ///
    /// Callers should call `currentDisableRemotelyState` after calling this
    /// method to track the progress of disabling remotely.
    func startDisablingBackups() async throws {
        logger.info("Disabling Backups...")

        try await db.awaitableWriteWithRollbackIfThrows { tx in
            if tsAccountManager.localIdentifiers(tx: tx) == nil {
                logger.info("Can't disable Backups, not registered!")
                throw NotRegisteredError()
            }

            try backupPlanManager.setBackupPlan(.disabled, tx: tx)

            kvStore.setBool(true, key: StoreKeys.attemptingDisableRemotely, transaction: tx)

            tx.addSyncCompletion { [self] in
                logger.info("Disabled Backups locally. Disabling remotely...")
                _ = disableRemotelyIfNecessaryTask.run()
            }
        }
    }

    /// Attempts to remotely disable Backups, if necessary. For example, a
    /// previous launch may have attempted but failed to remotely disable
    /// Backups.
    func disableRemotelyIfNecessary() async throws {
        // If we don't need to disable remotely, this will insta-complete.
        try await disableRemotelyIfNecessaryTask.run().value
    }

    func currentDisableRemotelyState(tx: DBReadTransaction) -> DisableRemotelyState? {
        if let task = disableRemotelyIfNecessaryTask.isCurrentlyRunning() {
            return .inProgress(task)
        }

        switch backupPlanManager.backupPlan(tx: tx) {
        case .disabled:
            if kvStore.hasValue(StoreKeys.remoteDisablingFailed, transaction: tx) {
                return .previouslyFailed
            }
        case .free, .paid, .paidExpiringSoon:
            break
        }

        return nil
    }

    // MARK: -

    private func _disableRemotelyIfNecessaryWithIndefiniteNetworkRetries() async throws -> Bool {
        return try await Retry.performWithBackoff(
            maxAttempts: .max,
            maxAverageBackoff: 2 * .minute,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
        ) {
            return try await taskQueue.run {
                try await _disableRemotelyIfNecessary()
            }
        }
    }

    /// - Returns
    /// A boolean indicating if disabling remotely was necessary.
    private func _disableRemotelyIfNecessary() async throws -> Bool {
        let localIdentifiers: LocalIdentifiers? = try db.read { tx in
            let disabledLocally = switch backupPlanManager.backupPlan(tx: tx) {
            case .disabled: true
            case .free, .paid, .paidExpiringSoon: false
            }
            let attemptingDisableRemotely = kvStore.hasValue(StoreKeys.attemptingDisableRemotely, transaction: tx)

            guard disabledLocally && attemptingDisableRemotely else {
                return nil
            }

            if let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) {
                return localIdentifiers
            } else {
                throw NotRegisteredError()
            }
        }

        guard let localIdentifiers else {
            // We no longer need to disable remotely. Bail!
            return false
        }

        try await backupIdManager.deleteBackupId(
            localIdentifiers: localIdentifiers,
            auth: .implicit()
        )

        await db.awaitableWrite { tx in
            kvStore.removeValue(forKey: StoreKeys.remoteDisablingFailed, transaction: tx)
            kvStore.removeValue(forKey: StoreKeys.attemptingDisableRemotely, transaction: tx)
        }

        return true
    }
}
