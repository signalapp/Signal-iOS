//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Reponsible for "disabling Backups": making the relevant API calls and
/// managing state.
public final class BackupDisablingManager {
    /// Side-effects of disabling Backups as relates to the user's AEP.
    public enum AEPSideEffect {
        /// Store the given new AEP once disabling is complete.
        case rotate(newAEP: AccountEntropyPool)
    }

    private enum StoreKeys {
        static let aepBeingRotated = "aepBeingRotated"
        static let remoteDisablingFailed = "remoteDisablingFailed"
    }

    private let accountEntropyPoolManager: AccountEntropyPoolManager
    private let authCredentialStore: AuthCredentialStore
    private let backupAttachmentCoordinator: BackupAttachmentCoordinator
    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupCDNCredentialStore: BackupCDNCredentialStore
    private let backupKeyService: BackupKeyService
    private let backupPlanManager: BackupPlanManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let kvStore: KeyValueStore
    private let logger: PrefixedLogger
    private let taskQueue: ConcurrentTaskQueue
    private let tsAccountManager: TSAccountManager

    init(
        accountEntropyPoolManager: AccountEntropyPoolManager,
        authCredentialStore: AuthCredentialStore,
        backupAttachmentCoordinator: BackupAttachmentCoordinator,
        backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager,
        backupCDNCredentialStore: BackupCDNCredentialStore,
        backupKeyService: BackupKeyService,
        backupPlanManager: BackupPlanManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountEntropyPoolManager = accountEntropyPoolManager
        self.authCredentialStore = authCredentialStore
        self.backupAttachmentCoordinator = backupAttachmentCoordinator
        self.backupAttachmentDownloadQueueStatusManager = backupAttachmentDownloadQueueStatusManager
        self.backupCDNCredentialStore = backupCDNCredentialStore
        self.backupKeyService = backupKeyService
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
    /// - Parameter aepSideEffect
    /// The desired side-effect of disabling Backups on the user's AEP, if any.
    ///
    /// - Returns
    /// The current status of downloading offloaded media. To learn the result
    /// of disabling remotely, callers should wait for `BackupPlan` to become
    /// `.disabled` and then consult ``disableRemotelyFailed(tx:)``.
    public func startDisablingBackups(
        aepSideEffect: AEPSideEffect?,
    ) async -> BackupAttachmentDownloadQueueStatus {
        logger.info("Disabling Backups...")

        await db.awaitableWrite { tx in
            switch backupPlanManager.backupPlan(tx: tx) {
            case .disabling:
                owsFail("Unexpectedly attempted to start disabling, but already disabling!")
            case .disabled, .free, .paid, .paidExpiringSoon, .paidAsTester:
                break
            }

            backupPlanManager.setBackupPlan(.disabling, tx: tx)

            switch aepSideEffect {
            case nil:
                break
            case .rotate(let newAEP):
                // Persist the new AEP in this class' KVStore temporarily.
                // Once we're done disabling, we'll save it officially.
                kvStore.setString(newAEP.rawString, key: StoreKeys.aepBeingRotated, transaction: tx)
            }
        }

        logger.info("Backups set locally as disabling. Starting async disabling work...")
        Task {
            await disableRemotelyIfNecessary()
        }

        // We may have just made the download queue non-empty. Ensure we wait
        // for the status manager to start observing, so its reported status
        // picks up that fact. Kick off thumbnails async; fullsize returns here.
        Task { [backupAttachmentDownloadQueueStatusManager] in
            await backupAttachmentDownloadQueueStatusManager.beginObservingIfNecessary(for: .thumbnail)
        }
        return await backupAttachmentDownloadQueueStatusManager.beginObservingIfNecessary(for: .fullsize)
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
                try await backupAttachmentCoordinator.queryListMediaIfNeeded()
            }

            logger.info("Done waiting for list-media.")
        } catch {
            logger.error("Failed to list-media! \(error)")
            // Continue anyway – this isn't a retryable network error, and we
            // really want to make sure we disable Backups.
        }

        let successfullyDisabledRemotely: Bool
        do {
            let (localIdentifiers, isRegisteredPrimaryDevice) = db.read { tx in
                return (
                    tsAccountManager.localIdentifiers(tx: tx),
                    tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
                )
            }

            if let localIdentifiers, isRegisteredPrimaryDevice {
                logger.info("Disabling Backups remotely...")
                try await Retry.performWithIndefiniteNetworkRetries {
                    try await backupKeyService.deleteBackupKey(
                        localIdentifiers: localIdentifiers,
                        auth: .implicit(),
                    )
                }

                logger.info("Successfully disabled Backups remotely!")
                successfullyDisabledRemotely = true
            } else {
                logger.warn("Cannot disable Backups while unregistered!")
                successfullyDisabledRemotely = false
            }
        } catch {
            logger.error("Failed to disable Backups remotely! \(error)")
            successfullyDisabledRemotely = false
        }

        await db.awaitableWrite { tx in
            if successfullyDisabledRemotely {
                kvStore.removeValue(forKey: StoreKeys.remoteDisablingFailed, transaction: tx)
            } else {
                kvStore.setBool(true, key: StoreKeys.remoteDisablingFailed, transaction: tx)
            }

            backupPlanManager.setBackupPlan(.disabled, tx: tx)

            // Wipe these, which are now outdated.
            backupSettingsStore.resetLastBackupDetails(tx: tx)
            backupSettingsStore.resetShouldAllowBackupUploadsOnCellular(tx: tx)

            // With Backups disabled, these credentials are no longer valid
            // and are no longer safe to use.
            authCredentialStore.removeAllBackupAuthCredentials(tx: tx)
            backupCDNCredentialStore.wipe(tx: tx)

            if let aepBeingRotatedString = kvStore.getString(StoreKeys.aepBeingRotated, transaction: tx) {
                logger.warn("Rotating AEP after disabling Backups!")

                accountEntropyPoolManager.setAccountEntropyPool(
                    newAccountEntropyPool: try! AccountEntropyPool(key: aepBeingRotatedString),
                    disablePIN: false,
                    tx: tx,
                )
            }
        }

        logger.info("Successfully disabled Backups locally!")
    }

    private func _waitForBackupAttachmentDownloads() async {
        func countsAsComplete(_ status: BackupAttachmentDownloadQueueStatus) -> Bool {
            switch status {
            case .suspended, .empty, .notRegisteredAndReady:
                return true
            case .running, .noWifiReachability, .noReachability, .lowBattery, .lowPowerMode, .lowDiskSpace, .appBackgrounded:
                return false
            }
        }

        if countsAsComplete(await backupAttachmentDownloadQueueStatusManager.beginObservingIfNecessary(for: .fullsize)) {
            return
        }

        for await _ in NotificationCenter.default.notifications(named: .backupAttachmentDownloadQueueStatusDidChange(mode: .fullsize)) {
            if countsAsComplete(await backupAttachmentDownloadQueueStatusManager.currentStatus(for: .fullsize)) {
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
