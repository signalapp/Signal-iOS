//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Reponsible for "disabling Backups": making the relevant API calls and
/// managing state.
class BackupDisablingManager {
    private enum StoreKeys {
        static let remoteDisablingFailed = "remoteDisablingFailed"
    }

    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupIdManager: BackupIdManager
    private let backupPlanManager: BackupPlanManager
    private let db: DB
    private let kvStore: KeyValueStore
    private let logger: PrefixedLogger
    private let tsAccountManager: TSAccountManager

    /// Tracks async work to disable remotely, if necessary. Calls to `.run()`
    /// will (almost-)insta-complete if disabling remotely is not necessary.
    private var disableRemotelyIfNecessaryTask: DebouncedTask<Void>!

    init(
        backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager,
        backupIdManager: BackupIdManager,
        backupPlanManager: BackupPlanManager,
        db: DB,
        tsAccountManager: TSAccountManager,
    ) {
        self.backupAttachmentDownloadQueueStatusManager = backupAttachmentDownloadQueueStatusManager
        self.backupIdManager = backupIdManager
        self.backupPlanManager = backupPlanManager
        self.db = db
        self.kvStore = KeyValueStore(collection: "BackupDisablingManager")
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.tsAccountManager = tsAccountManager

        self.disableRemotelyIfNecessaryTask = DebouncedTask { [weak self] in
            guard let self else { return }
            await _disableRemotelyIfNecessary()
        }
    }

    // MARK: -

    /// Disable Backups for the current user. `BackupPlan` is immediately set to
    /// `.disabling` locally, with disabling-remotely kicked off asynchronously.
    ///
    /// - Note
    /// Emptying the download queue, either by completing or skipping downloads
    /// of offloaded media, is a prerequisite to disabling Backups.
    ///
    /// - Returns
    /// The current status of downloading offloaded media. To learn the result
    /// of disabling remotely, callers should wait for `BackupPlan` to become
    /// `.disabled` and then consult ``disableRemotelyFailed(tx:)``.
    func startDisablingBackups() async -> BackupAttachmentDownloadQueueStatus {
        logger.info("Disabling Backups...")

        do {
            try await db.awaitableWriteWithRollbackIfThrows { tx in
                try backupPlanManager.setBackupPlan(.disabling, tx: tx)
            }

            logger.info("Backups set locally as disabling. Starting async disabling work...")
            _ = disableRemotelyIfNecessaryTask.run()
        } catch {
            logger.error("Failed to mark Backups disabling locally! \(error)")
        }

        // We may have just made the download queue non-empty. Ensure we wait
        // for the status manager to start observing, so its reported status
        // picks up that fact.
        return await backupAttachmentDownloadQueueStatusManager.beginObservingIfNecessary()
    }

    /// Attempts to remotely disable Backups, if necessary. For example, a
    /// previous launch may have attempted but failed to remotely disable
    /// Backups.
    func disableRemotelyIfNecessary() async {
        // If we don't need to disable remotely, this will insta-complete.
        await disableRemotelyIfNecessaryTask.run().value
    }

    /// Whether a previous remote-disabling attempt failed terminally.
    func disableRemotelyFailed(tx: DBReadTransaction) -> Bool {
        switch backupPlanManager.backupPlan(tx: tx) {
        case .disabled:
            return kvStore.hasValue(StoreKeys.remoteDisablingFailed, transaction: tx)
        case .disabling, .free, .paid, .paidExpiringSoon:
            return false
        }
    }

    // MARK: -

    /// Disables remotely, if necessary. Network errors are retried-with-backoff
    /// indefinitely.
    private func _disableRemotelyIfNecessary() async {
        let needsDisablingRemotely = db.read { tx in
            switch backupPlanManager.backupPlan(tx: tx) {
            case .disabling: true
            case .disabled, .free, .paid, .paidExpiringSoon: false
            }
        }

        guard needsDisablingRemotely else {
            return
        }

        logger.info("Waiting for downloads before disabling...")
        await _waitForBackupAttachmentDownloads()
        logger.info("Done waiting for downloads. Disabling Backups remotely...")

        guard let localIdentifiers = db.read(block: { tx in
            tsAccountManager.localIdentifiers(tx: tx)
        }) else {
            logger.warn("Cannot disable remotely: not registered!")
            return
        }

        let successfullyDisabledRemotely: Bool
        do {
            try await _disableRemotelyWithIndefiniteNetworkRetries(localIdentifiers: localIdentifiers)

            logger.info("Successfully disabled Backups remotely!")
            successfullyDisabledRemotely = true
        } catch {
            logger.error("Failed to disable Backups remotely! \(error)")
            successfullyDisabledRemotely = false
        }

        do {
            try await db.awaitableWriteWithRollbackIfThrows { tx in
                if successfullyDisabledRemotely {
                    kvStore.removeValue(forKey: StoreKeys.remoteDisablingFailed, transaction: tx)
                } else {
                    kvStore.setBool(true, key: StoreKeys.remoteDisablingFailed, transaction: tx)
                }

                try backupPlanManager.setBackupPlan(.disabled, tx: tx)
            }

            logger.info("Successfully disabled Backups locally!")
        } catch {
            logger.error("Failed to mark Backups disabled locally! \(error)")
        }
    }

    private func _waitForBackupAttachmentDownloads() async {
        func countsAsComplete(_ status: BackupAttachmentDownloadQueueStatus) -> Bool {
            switch status {
            case .suspended, .empty, .notRegisteredAndReady:
                return true
            case .running, .noWifiReachability, .noReachability, .lowBattery, .lowDiskSpace:
                return false
            }
        }

        if countsAsComplete(await backupAttachmentDownloadQueueStatusManager.beginObservingIfNecessary()) {
            return
        }

        for await _ in NotificationCenter.default.notifications(named: .backupAttachmentDownloadQueueStatusDidChange) {
            if countsAsComplete(await backupAttachmentDownloadQueueStatusManager.currentStatus()) {
                break
            }
        }
    }

    private func _disableRemotelyWithIndefiniteNetworkRetries(
        localIdentifiers: LocalIdentifiers,
    ) async throws {
        try await Retry.performWithBackoff(
            maxAttempts: .max,
            maxAverageBackoff: 2 * .minute,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
        ) {
            try await backupIdManager.deleteBackupId(
                localIdentifiers: localIdentifiers,
                auth: .implicit()
            )
        }
    }
}
