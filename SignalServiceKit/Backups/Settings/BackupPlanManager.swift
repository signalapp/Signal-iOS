//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public protocol BackupPlanManager {
    /// See ``BackupSettingsStore/backupPlan(tx:)``. API passed-through for
    /// convenience of callers using this type.
    func backupPlan(tx: DBReadTransaction) -> BackupPlan

    /// Set the current `BackupPlan` via data from Storage Service.
    ///
    /// - Important
    /// Must only be called on linked devices!
    func setBackupPlan(
        fromStorageService backupLevel: LibSignalClient.BackupLevel?,
        tx: DBWriteTransaction,
    )

    /// Set the current `BackupPlan`.
    ///
    /// - Important
    /// Must only be called on primary devices!
    func setBackupPlan(_ plan: BackupPlan, tx: DBWriteTransaction)
}

extension Notification.Name {
    public static let backupPlanChanged = Notification.Name("BackupSettings.backupPlanChanged")
}

// MARK: -

class BackupPlanManagerImpl: BackupPlanManager {

    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let logger: PrefixedLogger
    private let tsAccountManager: TSAccountManager

    init(
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        tsAccountManager: TSAccountManager,
    ) {
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    func backupPlan(tx: DBReadTransaction) -> BackupPlan {
        return backupSettingsStore.backupPlan(tx: tx)
    }

    // MARK: -

    func setBackupPlan(fromStorageService backupLevel: BackupLevel?, tx: DBWriteTransaction) {
        guard
            let registeredState = try? tsAccountManager.registeredState(tx: tx),
            !registeredState.isPrimary
        else {
            owsFailDebug("Attempting to set backupPlan from Storage Service, but not a linked device!")
            return
        }

        switch backupLevel {
        case nil:
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
            configureDownloadsForDisablingBackups(tx: tx)
        case .free:
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        case .paid:
            // Linked devices don't support optimizeLocalStorage; default off.
            backupSettingsStore.setBackupPlan(.paid(optimizeLocalStorage: false), tx: tx)
        }
    }

    // MARK: -

    func setBackupPlan(_ newBackupPlan: BackupPlan, tx: DBWriteTransaction) {
        let oldBackupPlan = backupPlan(tx: tx)

        logger.info("Setting BackupPlan! \(oldBackupPlan) -> \(newBackupPlan)")

        backupSettingsStore.setBackupPlan(newBackupPlan, tx: tx)

        backupAttachmentUploadProgress.backupPlanDidChange(
            oldBackupPlan: oldBackupPlan,
            newBackupPlan: newBackupPlan,
            tx: tx,
        )

        rotateUploadEraIfNecessary(
            oldBackupPlan: oldBackupPlan,
            newBackupPlan: newBackupPlan,
            tx: tx,
        )

        configureDownloadsForBackupPlanChange(
            oldPlan: oldBackupPlan,
            newPlan: newBackupPlan,
            tx: tx,
        )

        switch newBackupPlan {
        case .disabled, .disabling, .free:
            // Media tier capacity is only a paid tier concept; reset our local
            // knowledge of having run out of space when we become non-paid tier.
            // If we become paid tier again, we will rediscover that we are out
            // of space when we try and upload and get an error from the server.
            backupSettingsStore.setHasConsumedMediaTierCapacity(false, tx: tx)
        case .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        if oldBackupPlan != newBackupPlan {
            tx.addSyncCompletion {
                NotificationCenter.default.post(name: .backupPlanChanged, object: nil)
            }
        }
    }

    // MARK: -

    private func rotateUploadEraIfNecessary(
        oldBackupPlan: BackupPlan,
        newBackupPlan: BackupPlan,
        tx: DBWriteTransaction,
    ) {
        func isPaidPlan(_ backupPlan: BackupPlan) -> Bool {
            switch backupPlan {
            case .disabled, .disabling, .free: false
            case .paid, .paidExpiringSoon, .paidAsTester: true
            }
        }

        if !isPaidPlan(oldBackupPlan), isPaidPlan(newBackupPlan) {
            // If we're becoming a paid-tier user, we should rotate the upload
            // era to ensure we run a list-media and discover any necessary
            // uploads.
            backupAttachmentUploadEraStore.rotateUploadEra(tx: tx)
        }
    }

    // MARK: -

    private func configureDownloadsForBackupPlanChange(
        oldPlan: BackupPlan,
        newPlan: BackupPlan,
        tx: DBWriteTransaction,
    ) {
        switch (oldPlan, newPlan) {
        case
            (.disabling, .disabling),
            (.disabled, .disabled),
            (.free, .free):
            // No change.
            return

        case
            (.disabling, .free),
            (.disabling, .paid),
            (.disabling, .paidExpiringSoon),
            (.disabling, .paidAsTester),
            (.disabled, .disabling):
            owsFailDebug("Unexpected BackupPlan transition: \(oldPlan) -> \(newPlan)")
            return

        case (.free, .disabling):
            // While in free tier, we may have been continuing downloads
            // from when you were previously paid tier. But that was nice
            // to have; now that we're disabling backups cancel them all.
            Logger.info("Configuring downloads for disabling free backups")
            backupAttachmentDownloadStore.markAllReadyIneligible(tx: tx)
            backupAttachmentDownloadStore.deleteAllDone(tx: tx)

        case
            let (.paid(optimizeLocalStorage), .disabling),
            let (.paidExpiringSoon(optimizeLocalStorage), .disabling),
            let (.paidAsTester(optimizeLocalStorage), .disabling):
            Logger.info("Configuring downloads for disabling paid backups")
            backupAttachmentDownloadStore.deleteAllDone(tx: tx)
            // Unsuspend; this is the user opt-in to trigger downloads.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
            if optimizeLocalStorage {
                // If we had optimize enabled, make anything ineligible (offloaded
                // attachments) now eligible.
                backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            }

        case (_, .disabled):
            configureDownloadsForDisablingBackups(tx: tx)

        case (.disabled, .free):
            backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            // Suspend the queue so the user has to explicitly opt-in to download.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)

        case
            let (.disabled, .paid(optimizeStorage)),
            let (.disabled, .paidExpiringSoon(optimizeStorage)),
            let (.disabled, .paidAsTester(optimizeStorage)):
            backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            // Suspend the queue so the user has to explicitly opt-in to download.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
            if optimizeStorage {
                // Unclear how you would go straight from disabled to optimize
                // enabled, but just go through the motions of both state changes
                // as if they'd happened independently.
                configureDownloadsForDidEnableOptimizeStorage(tx: tx)
            }

        case
            let (.paid(wasOptimizeLocalStorageEnabled), .free),
            let (.paidExpiringSoon(wasOptimizeLocalStorageEnabled), .free),
            let (.paidAsTester(wasOptimizeLocalStorageEnabled), .free):
            // We explicitly do nothing going from paid to free; we want to continue
            // any downloads that were already running (so we take advantage of the
            // media tier cdn TTL being longer than paid subscription lifetime) but
            // also not schedule (or un-suspend) if we weren't already downloading.
            // But if optimization was on, its now implicitly off, so handle that.
            if wasOptimizeLocalStorageEnabled {
                configureDownloadsForDidDisableOptimizeStorage(tx: tx)
            }

        case
            let (.free, .paid(optimizeStorage)),
            let (.free, .paidExpiringSoon(optimizeStorage)),
            let (.free, .paidAsTester(optimizeStorage)):
            // We explicitly do nothing when going from free to paid; any state
            // changes that will happen will be triggered by list media request
            // handling which will always run at the start of a new upload era.
            // But if we somehow went straight from free to optimize enabled,
            // handle that state transition.
            if optimizeStorage {
                owsFailDebug("Going from free or disabled directly to optimize enabled shouldn't be allowed?")
                configureDownloadsForDidEnableOptimizeStorage(tx: tx)
            }

        case
            // Downloads don't care if expiring soon or not
            let (.paid(oldOptimize), .paid(newOptimize)),
            let (.paid(oldOptimize), .paidExpiringSoon(newOptimize)),
            let (.paid(oldOptimize), .paidAsTester(newOptimize)),
            let (.paidExpiringSoon(oldOptimize), .paid(newOptimize)),
            let (.paidExpiringSoon(oldOptimize), .paidExpiringSoon(newOptimize)),
            let (.paidExpiringSoon(oldOptimize), .paidAsTester(newOptimize)),
            let (.paidAsTester(oldOptimize), .paid(newOptimize)),
            let (.paidAsTester(oldOptimize), .paidExpiringSoon(newOptimize)),
            let (.paidAsTester(oldOptimize), .paidAsTester(newOptimize)):
            if oldOptimize == newOptimize {
                // Nothing changed.
                break
            } else if newOptimize {
                configureDownloadsForDidEnableOptimizeStorage(tx: tx)
            } else {
                configureDownloadsForDidDisableOptimizeStorage(tx: tx)
            }
        }
    }

    private func configureDownloadsForDisablingBackups(tx: DBWriteTransaction) {
        Logger.info("Configuring downloads for disabled backups")
        // When we disable, we mark everything ineligible and delete all
        // done rows. If we ever re-enable, we will mark those rows
        // ready again.
        backupAttachmentDownloadStore.deleteAllDone(tx: tx)
        backupAttachmentDownloadStore.markAllReadyIneligible(tx: tx)
        // This doesn't _really_ do anything, since we don't run the queue
        // when disabled anyway, but may as well suspend.
        backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
    }

    private func configureDownloadsForDidEnableOptimizeStorage(tx: DBWriteTransaction) {
        Logger.info("Configuring downloads for optimize enabled")
        // When we turn on optimization, make all media tier fullsize downloads
        // from the queue that are past the optimization threshold ineligible.
        // If we downloaded them we'd offload them immediately anyway.
        // This isn't 100% necessary; after all something 29 days old today will be
        // 30 days old tomorrow, so the queue runner will gracefully handle old
        // downloads at run-time anyway. But its more efficient to do in bulk.
        let threshold = dateProvider().ows_millisecondsSince1970 - Attachment.offloadingThresholdMs
        backupAttachmentDownloadStore.markAllMediaTierFullsizeDownloadsIneligible(
            olderThan: threshold,
            tx: tx,
        )
        // Un-suspend; when optimization is enabled we always auto-download
        // the stuff that is eligible (newer attachments).
        backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
        // Reset the progress counter.
        backupAttachmentDownloadStore.deleteAllDone(tx: tx)
    }

    private func configureDownloadsForDidDisableOptimizeStorage(tx: DBWriteTransaction) {
        Logger.info("Configuring downloads for optimize disabled")
        // When we turn _off_ optimization, we want to make ready all the media tier downloads,
        // but suspend the queue so we don't immediately start downloading.
        backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
        // Suspend the queue; the user has to explicitly opt in to downloads
        // after optimization is disabled.
        backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)

        // Reset the download banner so we show it again if the user dismissed.
        backupAttachmentDownloadStore.resetDidDismissDownloadCompleteBanner(tx: tx)
    }
}

// MARK: -

#if TESTABLE_BUILD

class MockBackupPlanManager: BackupPlanManager {
    var backupPlanMock: BackupPlan?
    func backupPlan(tx: DBReadTransaction) -> BackupPlan {
        backupPlanMock ?? .disabled
    }

    func setBackupPlan(fromStorageService backupLevel: BackupLevel?, tx: DBWriteTransaction) {
        owsFail("Not implemented!")
    }

    func setBackupPlan(_ plan: BackupPlan, tx: DBWriteTransaction) {
        backupPlanMock = plan
    }
}

#endif
