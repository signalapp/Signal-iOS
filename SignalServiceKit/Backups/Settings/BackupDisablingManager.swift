//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Reponsible for "disabling Backups": making the relevant API calls and
/// managing state.
public final class BackupDisablingManager {
    private enum StoreKeys {
        static let remoteDisablingFailed = "remoteDisablingFailed"
    }

    private let authCredentialStore: AuthCredentialStore
    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupCDNCredentialStore: BackupCDNCredentialStore
    private let backupIdManager: BackupIdManager
    private let backupListMediaManager: BackupListMediaManager
    private let backupPlanManager: BackupPlanManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let kvStore: KeyValueStore
    private let logger: PrefixedLogger
    private let taskQueue: ConcurrentTaskQueue
    private let tsAccountManager: TSAccountManager

    init(
        authCredentialStore: AuthCredentialStore,
        backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager,
        backupCDNCredentialStore: BackupCDNCredentialStore,
        backupIdManager: BackupIdManager,
        backupListMediaManager: BackupListMediaManager,
        backupPlanManager: BackupPlanManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        tsAccountManager: TSAccountManager,
    ) {
        self.authCredentialStore = authCredentialStore
        self.backupAttachmentDownloadQueueStatusManager = backupAttachmentDownloadQueueStatusManager
        self.backupCDNCredentialStore = backupCDNCredentialStore
        self.backupIdManager = backupIdManager
        self.backupListMediaManager = backupListMediaManager
        self.backupPlanManager = backupPlanManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.kvStore = KeyValueStore(collection: "BackupDisablingManager")
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)
        self.tsAccountManager = tsAccountManager
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
    public func startDisablingBackups() async -> BackupAttachmentDownloadQueueStatus {
        logger.info("Disabling Backups...")

        do {
            try await db.awaitableWriteWithRollbackIfThrows { tx in
                try backupPlanManager.setBackupPlan(.disabling, tx: tx)
            }

            logger.info("Backups set locally as disabling. Starting async disabling work...")
            Task {
                await disableRemotelyIfNecessary()
            }
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
    public func disableRemotelyIfNecessary() async {
        await taskQueue.runWithoutTaskCancellationHandler {
            await _disableRemotelyIfNecessary()
        }
    }

    /// Whether a previous remote-disabling attempt failed terminally.
    public func disableRemotelyFailed(tx: DBReadTransaction) -> Bool {
        switch backupPlanManager.backupPlan(tx: tx) {
        case .disabled:
            return kvStore.hasValue(StoreKeys.remoteDisablingFailed, transaction: tx)
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
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
            case .disabled, .free, .paid, .paidExpiringSoon, .paidAsTester: false
            }
        }

        guard needsDisablingRemotely else {
            return
        }

        logger.info("Waiting for downloads before disabling...")
        await _waitForBackupAttachmentDownloads()
        logger.info("Done waiting for downloads.")

        do {
            // If we skipped downloads, it's possible we're still in the middle
            // of a list-media operation. If so, we don't want to delete stuff
            // out from under it.
            logger.info("Waiting for list-media before disabling...")

            try await Retry.performWithIndefiniteNetworkRetries {
                try await backupListMediaManager.queryListMediaIfNeeded()
            }

            logger.info("Done waiting for list-media.")
        } catch {
            logger.error("Failed to list-media! \(error)")
            // Continue anyway – this isn't a retryable network error, and we
            // really want to make sure we disable Backups.
        }

        guard let localIdentifiers = db.read(block: { tx in
            tsAccountManager.localIdentifiers(tx: tx)
        }) else {
            logger.warn("Cannot disable remotely: not registered!")
            return
        }

        let successfullyDisabledRemotely: Bool
        do {
            logger.info("Disabling Backups remotely...")
            try await Retry.performWithIndefiniteNetworkRetries {
                try await backupIdManager.deleteBackupId(
                    localIdentifiers: localIdentifiers,
                    auth: .implicit()
                )
            }

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

                // Wipe these, which are now outdated.
                backupSettingsStore.resetLastBackupDate(tx: tx)
                backupSettingsStore.resetLastBackupSizeBytes(tx: tx)
                backupSettingsStore.resetShouldAllowBackupUploadsOnCellular(tx: tx)

                // With Backups disabled, these credentials are no longer valid
                // and are no longer safe to use.
                authCredentialStore.removeAllBackupAuthCredentials(tx: tx)
                backupCDNCredentialStore.wipe(tx: tx)
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
}

// MARK: -

private extension Retry {
    static func performWithIndefiniteNetworkRetries(block: () async throws -> Void) async throws {
        try await Retry.performWithBackoff(
            maxAttempts: .max,
            maxAverageBackoff: 2 * .minute,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
        ) {
            try await block()
        }
    }
}
