//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Reponsible for "disabling Backups": making the relevant API calls and
/// managing state.
final class BackupDisablingManager {
    /// Side-effects of disabling Backups as relates to the user's AEP.
    enum AEPSideEffect {
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
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupCDNCredentialStore: BackupCDNCredentialStore
    private let backupExportJobStore: BackupExportJobStore
    private let backupKeyService: BackupKeyService
    private let backupListMediaManager: BackupListMediaManager
    private let backupPlanManager: BackupPlanManager
    private let backupSettingsStore: BackupSettingsStore
    private let clvBackupExportProgressViewStore: CLVBackupExportProgressView.Store
    private let db: DB
    private let kvStore: NewKeyValueStore
    private let logger: PrefixedLogger
    private let taskQueue: ConcurrentTaskQueue
    private let tsAccountManager: TSAccountManager

    init(
        accountEntropyPoolManager: AccountEntropyPoolManager,
        authCredentialStore: AuthCredentialStore,
        backupAttachmentCoordinator: BackupAttachmentCoordinator,
        backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupCDNCredentialStore: BackupCDNCredentialStore,
        backupExportJobStore: BackupExportJobStore,
        backupKeyService: BackupKeyService,
        backupListMediaManager: BackupListMediaManager,
        backupPlanManager: BackupPlanManager,
        backupSettingsStore: BackupSettingsStore,
        clvBackupExportProgressViewStore: CLVBackupExportProgressView.Store,
        db: DB,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountEntropyPoolManager = accountEntropyPoolManager
        self.authCredentialStore = authCredentialStore
        self.backupAttachmentCoordinator = backupAttachmentCoordinator
        self.backupAttachmentDownloadQueueStatusManager = backupAttachmentDownloadQueueStatusManager
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupCDNCredentialStore = backupCDNCredentialStore
        self.backupExportJobStore = backupExportJobStore
        self.backupKeyService = backupKeyService
        self.backupListMediaManager = backupListMediaManager
        self.backupPlanManager = backupPlanManager
        self.backupSettingsStore = backupSettingsStore
        self.clvBackupExportProgressViewStore = clvBackupExportProgressViewStore
        self.db = db
        self.kvStore = NewKeyValueStore(collection: "BackupDisablingManager")
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
    func startDisablingBackups(
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
                kvStore.writeValue(newAEP.rawString, forKey: StoreKeys.aepBeingRotated, tx: tx)
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
    func disableRemotelyIfNecessary() async {
        await taskQueue.runWithoutTaskCancellationHandler {
            await _disableRemotelyIfNecessary()
        }
    }

    /// Whether a previous remote-disabling attempt failed terminally.
    func disableRemotelyFailed(tx: DBReadTransaction) -> Bool {
        switch backupPlanManager.backupPlan(tx: tx) {
        case .disabled:
            return kvStore.fetchValue(Bool.self, forKey: StoreKeys.remoteDisablingFailed, tx: tx) != nil
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

        let successfullyDisabledRemotely: Bool
        do {
            let registeredState = try? tsAccountManager.registeredStateWithMaybeSneakyTransaction()

            if let registeredState, registeredState.isPrimary {
                logger.info("Disabling Backups remotely...")
                try await Retry.performWithIndefiniteNetworkRetries {
                    try await backupKeyService.deleteBackupKey(
                        localIdentifiers: registeredState.localIdentifiers,
                        auth: .implicit(),
                        logger: logger,
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
                kvStore.removeValue(forKey: StoreKeys.remoteDisablingFailed, tx: tx)
            } else {
                kvStore.writeValue(true, forKey: StoreKeys.remoteDisablingFailed, tx: tx)
            }

            backupPlanManager.setBackupPlan(.disabled, tx: tx)

            // Wipe these, which are now outdated.
            backupSettingsStore.resetLastBackupDetails(tx: tx)
            backupSettingsStore.resetShouldAllowBackupUploadsOnCellular(tx: tx)
            backupExportJobStore.wipe(tx: tx)
            backupListMediaManager.wipe(tx: tx)

            // Reset the Backups banners, in case we later reenable Backups.
            clvBackupExportProgressViewStore.setIsHidden(false, tx: tx)
            backupAttachmentDownloadStore.resetDidDismissDownloadCompleteBanner(tx: tx)

            // With Backups disabled, these credentials are no longer valid
            // and are no longer safe to use.
            authCredentialStore.removeAllBackupAuthCredentials(tx: tx)
            backupCDNCredentialStore.wipe(tx: tx)

            if let aepBeingRotatedString = kvStore.fetchValue(String.self, forKey: StoreKeys.aepBeingRotated, tx: tx) {
                logger.warn("Rotating AEP after disabling Backups!")

                do {
                    try accountEntropyPoolManager.setAccountEntropyPool(
                        newAccountEntropyPool: try! AccountEntropyPool(key: aepBeingRotatedString),
                        tx: tx,
                    )
                } catch {
                    owsFailDebug("Failed to set AEP after disabling Backups: \(error)")
                    return
                }
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
