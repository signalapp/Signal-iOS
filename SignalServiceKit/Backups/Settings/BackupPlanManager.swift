//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol BackupPlanManager {
    /// See ``BackupSettingsStore/backupPlan(tx:)``. API passed-through for
    /// convenience of callers using this type.
    func backupPlan(tx: DBReadTransaction) -> BackupPlan

    /// Set the current `BackupPlan`.
    ///
    /// - Important
    /// This API has side effects, such as setting ancillary state in addition
    /// to the `BackupPlan`. Callers should use a `DB` method that
    /// rolls-back-if-throws to get the `tx` for calling this API, to avoid
    /// state being partially set.
    func setBackupPlan(_ plan: BackupPlan, tx: DBWriteTransaction) throws
}

extension Notification.Name {
    public static let backupPlanChanged = Notification.Name("BackupSettings.backupPlanChanged")
}

// MARK: -

class BackupPlanManagerImpl: BackupPlanManager {

    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    private let backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner
    private let backupSettingsStore: BackupSettingsStore

    init(
        backupAttachmentDownloadManager: BackupAttachmentDownloadManager,
        backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner,
        backupSettingsStore: BackupSettingsStore
    ) {
        self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
        self.backupAttachmentUploadQueueRunner = backupAttachmentUploadQueueRunner
        self.backupSettingsStore = backupSettingsStore
    }

    // MARK: -

    func backupPlan(tx: DBReadTransaction) -> BackupPlan {
        return backupSettingsStore.backupPlan(tx: tx)
    }

    func setBackupPlan(_ newBackupPlan: BackupPlan, tx: DBWriteTransaction) throws {
        let oldBackupPlan = backupPlan(tx: tx)
        let isBackupPlanChanging = oldBackupPlan != newBackupPlan

        backupSettingsStore.setBackupPlan(newBackupPlan, tx: tx)

        if isBackupPlanChanging {
            try backupAttachmentDownloadManager.backupPlanDidChange(
                from: oldBackupPlan,
                to: newBackupPlan,
                tx: tx
            )

            switch newBackupPlan {
            case .paid, .paidExpiringSoon:
                backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
            case .disabled, .free:
                break
            }

            tx.addSyncCompletion {
                NotificationCenter.default.post(name: .backupPlanChanged, object: nil)
            }
        }
    }
}
