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
    private let backupSettingsStore: BackupSettingsStore
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
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        tsAccountManager: TSAccountManager,
    ) {
        self.backupIdManager = backupIdManager
        self.backupSettingsStore = backupSettingsStore
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
    /// locally, and the returned `Task` tracks disabling them remotely.
    ///
    /// - Throws `NotRegisteredError` before disabling if the user is not registered.
    func disableBackups(tx: DBWriteTransaction) throws(NotRegisteredError) -> DisableRemotelyState {
        logger.info("Disabling Backups...")

        guard tsAccountManager.localIdentifiers(tx: tx) != nil else {
            logger.info("Can't disable Backups, not registered!")
            throw NotRegisteredError()
        }

        backupSettingsStore.setBackupPlan(.disabled, tx: tx)
        kvStore.setBool(true, key: StoreKeys.attemptingDisableRemotely, transaction: tx)

        logger.info("Disabled Backups locally. Disabling remotely...")
        return .inProgress(disableRemotelyIfNecessaryTask.run())
    }

    /// Attempts to remotely disable Backups, if necessary. For example, a
    /// previous launch may have attempted but failed to remotely disable
    /// Backups.
    func disableRemotelyIfNecessary() async {
        // If we don't need to disable remotely, this will complete almost
        // instantly and wipe itself.
        try? await disableRemotelyIfNecessaryTask.run().value
    }

    func currentDisableRemotelyState(tx: DBReadTransaction) -> DisableRemotelyState? {
        if kvStore.hasValue(StoreKeys.remoteDisablingFailed, transaction: tx) {
            return .previouslyFailed
        } else if let task = disableRemotelyIfNecessaryTask.isCurrentlyRunning() {
            return .inProgress(task)
        } else {
            return nil
        }
    }

    // MARK: -

    func forgetAnyDisableRemotelyFailures(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.remoteDisablingFailed, transaction: tx)
    }

    // MARK: -

    private func _disableRemotelyIfNecessaryWithIndefiniteNetworkRetries() async throws -> Bool {
        return try await Retry.performWithBackoff(
            maxAttempts: .max,
            maxAverageBackoff: 2 * .minute,
            isRetryable: { $0.isNetworkFailureOrTimeout || ($0 as? OWSHTTPError)?.isRetryable == true },
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
            let disabledLocally = switch backupSettingsStore.backupPlan(tx: tx) {
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
            kvStore.removeValue(forKey: StoreKeys.attemptingDisableRemotely, transaction: tx)
        }

        return true
    }
}
