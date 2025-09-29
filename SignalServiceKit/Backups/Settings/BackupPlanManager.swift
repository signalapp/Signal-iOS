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
    ///
    /// - Important
    /// Callers should use a `DB` method that rolls-back-if-throws to get the
    /// `tx` for calling this API, to avoid state being partially set.
    func setBackupPlan(
        fromStorageService backupLevel: LibSignalClient.BackupLevel?,
        tx: DBWriteTransaction
    ) throws

    /// Set the current `BackupPlan`.
    ///
    /// - Important
    /// Callers should use a `DB` method that rolls-back-if-throws to get the
    /// `tx` for calling this API, to avoid state being partially set.
    func setBackupPlan(_ plan: BackupPlan, tx: DBWriteTransaction) throws
}

extension Notification.Name {
    public static let backupPlanChanged = Notification.Name("BackupSettings.backupPlanChanged")
}

// MARK: -

final class BackupPlanManagerImpl: BackupPlanManager {

    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let tsAccountManager: TSAccountManager

    init(
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        tsAccountManager: TSAccountManager,
    ) {
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    func backupPlan(tx: DBReadTransaction) -> BackupPlan {
        return backupSettingsStore.backupPlan(tx: tx)
    }

    // MARK: -

    func setBackupPlan(fromStorageService backupLevel: BackupLevel?, tx: DBWriteTransaction) throws {
        guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice == false else {
            owsFailDebug("Attempting to set backupPlan from Storage Service, but not a linked device!")
            return
        }

        switch backupLevel {
        case nil:
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
            try configureDownloadsForDisablingBackups(tx: tx)
        case .free:
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        case .paid:
            // Linked devices don't support optimizeLocalStorage; default off.
            backupSettingsStore.setBackupPlan(.paid(optimizeLocalStorage: false), tx: tx)
        }
    }

    // MARK: -

    func setBackupPlan(_ newBackupPlan: BackupPlan, tx: DBWriteTransaction) throws {
        let oldBackupPlan = backupPlan(tx: tx)
        let isBackupPlanChanging = oldBackupPlan != newBackupPlan

        // Bail early on unexpected state transitions, before we persist state
        // we later regret.
        try validateBackupPlanStateTransition(
            oldBackupPlan: oldBackupPlan,
            newBackupPlan: newBackupPlan
        )

        backupSettingsStore.setBackupPlan(newBackupPlan, tx: tx)

        if isBackupPlanChanging {
            try configureDownloadsForBackupPlanChange(
                oldPlan: oldBackupPlan,
                newPlan: newBackupPlan,
                tx: tx
            )

            tx.addSyncCompletion {
                NotificationCenter.default.post(name: .backupPlanChanged, object: nil)
            }
        }
    }

    // MARK: -

    private func configureDownloadsForBackupPlanChange(
        oldPlan: BackupPlan,
        newPlan: BackupPlan,
        tx: DBWriteTransaction,
    ) throws {
        // Linked devices don't care about state changes; they keep downloading
        // whatever got enqueued at link'n'sync time.
        // (They also don't support storage optimization so that's moot.)
        guard tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            return
        }

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
            throw OWSAssertionError("Unexpected BackupPlan transition: \(oldPlan) -> \(newPlan)")
        case (.free, .disabling):
            // While in free tier, we may have been continuing downloads
            // from when you were previously paid tier. But that was nice
            // to have; now that we're disabling backups cancel them all.
            try backupAttachmentDownloadStore.markAllReadyIneligible(tx: tx)
            try backupAttachmentDownloadStore.deleteAllDone(tx: tx)
        case
            let (.paid(optimizeLocalStorage), .disabling),
            let (.paidExpiringSoon(optimizeLocalStorage), .disabling),
            let (.paidAsTester(optimizeLocalStorage), .disabling):
            try backupAttachmentDownloadStore.deleteAllDone(tx: tx)
            // Unsuspend; this is the user opt-in to trigger downloads.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
            if optimizeLocalStorage {
                // If we had optimize enabled, make anything ineligible (offloaded
                // attachments) now eligible.
                try backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            }
        case (_, .disabled):
            try configureDownloadsForDisablingBackups(tx: tx)

        case (.disabled, .free):
            try backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            // Suspend the queue so the user has to explicitly opt-in to download.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)

        case
            let (.disabled, .paid(optimizeStorage)),
            let (.disabled, .paidExpiringSoon(optimizeStorage)),
            let (.disabled, .paidAsTester(optimizeStorage)):
            try backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            // Suspend the queue so the user has to explicitly opt-in to download.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
            if optimizeStorage {
                // Unclear how you would go straight from disabled to optimize
                // enabled, but just go through the motions of both state changes
                // as if they'd happened independently.
                try configureDownloadsForDidEnableOptimizeStorage(tx: tx)
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
                try configureDownloadsForDidDisableOptimizeStorage(tx: tx)
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
                try configureDownloadsForDidEnableOptimizeStorage(tx: tx)
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
                try configureDownloadsForDidEnableOptimizeStorage(tx: tx)
            } else {
                try configureDownloadsForDidDisableOptimizeStorage(tx: tx)
            }
        }
    }

    private func configureDownloadsForDisablingBackups(tx: DBWriteTransaction) throws {
        // When we disable, we mark everything ineligible and delete all
        // done rows. If we ever re-enable, we will mark those rows
        // ready again.
        try backupAttachmentDownloadStore.deleteAllDone(tx: tx)
        try backupAttachmentDownloadStore.markAllReadyIneligible(tx: tx)
        // This doesn't _really_ do anything, since we don't run the queue
        // when disabled anyway, but may as well suspend.
        backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
    }

    private func configureDownloadsForDidEnableOptimizeStorage(tx: DBWriteTransaction) throws {
        // When we turn on optimization, make all media tier fullsize downloads
        // from the queue that are past the optimization threshold ineligible.
        // If we downloaded them we'd offload them immediately anyway.
        // This isn't 100% necessary; after all something 29 days old today will be
        // 30 days old tomorrow, so the queue runner will gracefully handle old
        // downloads at run-time anyway. But its more efficient to do in bulk.
        let threshold = dateProvider().ows_millisecondsSince1970 - Attachment.offloadingThresholdMs
        try backupAttachmentDownloadStore.markAllMediaTierFullsizeDownloadsIneligible(
            olderThan: threshold,
            tx: tx
        )
        // Un-suspend; when optimization is enabled we always auto-download
        // the stuff that is eligible (newer attachments).
        backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
        // Reset the progress counter.
        try backupAttachmentDownloadStore.deleteAllDone(tx: tx)
    }

    private func configureDownloadsForDidDisableOptimizeStorage(tx: DBWriteTransaction) throws {
        // When we turn _off_ optimization, we want to make ready all the media tier downloads,
        // but suspend the queue so we don't immediately start downloading.
        try backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
        // Suspend the queue; the user has to explicitly opt in to downloads
        // after optimization is disabled.
        backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)

        // Reset the download banner so we show it again if the user dismissed.
        backupAttachmentDownloadStore.resetDidDismissDownloadCompleteBanner(tx: tx)
    }

    // MARK: -

    private func validateBackupPlanStateTransition(
        oldBackupPlan: BackupPlan,
        newBackupPlan: BackupPlan,
    ) throws {
        var illegalStateTransition: Bool = false

        switch oldBackupPlan {
        case .disabled:
            switch newBackupPlan {
            case .disabled, .free, .paid, .paidExpiringSoon, .paidAsTester:
                break
            case .disabling:
                // We're already disabled; how are we starting disabling again?
                illegalStateTransition = true
            }
        case .disabling:
            switch newBackupPlan {
            case .disabled, .disabling:
                break
            case .free, .paid, .paidExpiringSoon, .paidAsTester:
                // Shouldn't be able to "enable" while we're disabling!
                illegalStateTransition = true
            }
        case .free, .paid, .paidExpiringSoon, .paidAsTester:
            switch newBackupPlan {
            case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
                break
            case .disabled:
                // Should've moved through .disabling first!
                illegalStateTransition = true
            }
        }

        if illegalStateTransition {
            throw OWSAssertionError("Unexpected illegal BackupPlan state transition: \(oldBackupPlan) -> \(newBackupPlan).")
        }
    }
}

// MARK: -

#if TESTABLE_BUILD

final class MockBackupPlanManager: BackupPlanManager {
    var backupPlanMock: BackupPlan?
    func backupPlan(tx: DBReadTransaction) -> BackupPlan {
        backupPlanMock ?? .disabled
    }

    func setBackupPlan(fromStorageService backupLevel: BackupLevel?, tx: DBWriteTransaction) {
        owsFail("Not implemented!")
    }

    func setBackupPlan(_ plan: BackupPlan, tx: DBWriteTransaction) throws {
        backupPlanMock = plan
    }
}

#endif
