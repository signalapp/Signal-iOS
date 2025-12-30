//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// In charge of deleting attachments off the backup cdn after they've been deleted locally (or otherwise orphaned).
public protocol OrphanedBackupAttachmentQueueRunner {

    /// Run all remote deletions, returning when finished. Supports cooperative cancellation.
    /// Should only be run after backup uploads have finished to avoid races.
    func runIfNeeded() async throws
}

public class OrphanedBackupAttachmentQueueRunnerImpl: OrphanedBackupAttachmentQueueRunner {

    private let appReadiness: AppReadiness
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        accountKeyStore: AccountKeyStore,
        appReadiness: AppReadiness,
        attachmentStore: AttachmentStore,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        listMediaManager: BackupListMediaManager,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
        tsAccountManager: TSAccountManager,
    ) {
        self.appReadiness = appReadiness
        self.tsAccountManager = tsAccountManager
        let taskRunner = TaskRunner(
            accountKeyStore: accountKeyStore,
            attachmentStore: attachmentStore,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            db: db,
            listMediaManager: listMediaManager,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            tsAccountManager: tsAccountManager,
        )
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: 8,
            dateProvider: dateProvider,
            db: db,
            runner: taskRunner,
        )
    }

    public func runIfNeeded() async throws {
        try await appReadiness.waitForAppReady()
        try Task.checkCancellation()
        guard tsAccountManager.localIdentifiersWithMaybeSneakyTransaction != nil else {
            return
        }
        try await taskQueue.loadAndRunTasks()
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let accountKeyStore: AccountKeyStore
        private let attachmentStore: AttachmentStore
        private let backupRequestManager: BackupRequestManager
        private let backupSettingsStore: BackupSettingsStore
        private let db: any DB
        private let listMediaManager: BackupListMediaManager
        private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        init(
            accountKeyStore: AccountKeyStore,
            attachmentStore: AttachmentStore,
            backupRequestManager: BackupRequestManager,
            backupSettingsStore: BackupSettingsStore,
            db: any DB,
            listMediaManager: BackupListMediaManager,
            orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
            tsAccountManager: TSAccountManager,
        ) {
            self.accountKeyStore = accountKeyStore
            self.attachmentStore = attachmentStore
            self.backupRequestManager = backupRequestManager
            self.backupSettingsStore = backupSettingsStore
            self.db = db
            self.listMediaManager = listMediaManager
            self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
            self.tsAccountManager = tsAccountManager

            self.store = TaskStore(orphanedBackupAttachmentStore: orphanedBackupAttachmentStore)
        }

        private actor ErrorCounts {
            var counts = [TaskRecord.IDType: Int]()

            func updateCount(_ id: TaskRecord.IDType) -> Int {
                let count = (counts[id] ?? 0) + 1
                counts[id] = count
                return count
            }
        }

        private let errorCounts = ErrorCounts()

        func runTask(record: Store.Record, loader: TaskQueueLoader<TaskRunner>) async -> TaskRecordResult {
            let (
                localAci,
                registrationState,
                mediaRootBackupKey,
                needsListMedia,
            ) = db.read { tx in
                return (
                    tsAccountManager.localIdentifiers(tx: tx)?.aci,
                    tsAccountManager.registrationState(tx: tx),
                    accountKeyStore.getMediaRootBackupKey(tx: tx),
                    self.listMediaManager.getNeedsQueryListMedia(tx: tx),
                )
            }

            switch registrationState {
            case
                .unregistered,
                .reregistering,
                .deregistered,
                .transferringIncoming,
                .transferringPrimaryOutgoing,
                .transferred:
                // These states are potentially temporary. Return a retryable error
                // but cancel the task.
                Logger.info("Stopping when unregistered")
                let error = OWSRetryableError()
                try? await loader.stop(reason: error)
                return .retryableError(error)
            case
                .relinking,
                .delinked,
                .transferringLinkedOutgoing,
                .provisioned:
                // Linked devices never issue these delete requests.
                // Cancel the task so we never run it again.
                return .cancelled
            case .registered:
                break
            }

            guard let localAci else {
                let error = OWSAssertionError("Deleting without being registered")
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }

            guard let mediaRootBackupKey else {
                let error = OWSAssertionError("Deleting without being registered")
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }

            if needsListMedia {
                // If we need to list media, quit out early so we can do that.
                try? await loader.stop(reason: NeedsListMediaError())
                return .retryableError(NeedsListMediaError())
            }

            let mediaId: Data

            if let recordMediaId = record.record.mediaId {
                mediaId = recordMediaId
            } else if let type = record.record.type, let mediaName = record.record.mediaName {
                let mediaNameToUse: String
                switch type {
                case .fullsize:
                    mediaNameToUse = mediaName
                case .thumbnail:
                    mediaNameToUse = AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName)
                }

                do {
                    mediaId = try mediaRootBackupKey.mediaEncryptionMetadata(
                        mediaName: mediaNameToUse,
                        // Doesn't matter what we use, we just want the mediaId.
                        type: .outerLayerFullsizeOrThumbnail,
                    ).mediaId
                } catch let error {
                    Logger.error("Failed to generate media IDs")
                    return .unretryableError(error)
                }
            } else {
                return .unretryableError(OWSAssertionError("Invalid record"))
            }

            let backupAuth: BackupServiceAuth
            do {
                backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                    for: mediaRootBackupKey,
                    localAci: localAci,
                    auth: .implicit(),
                )
            } catch let error {
                try? await loader.stop(reason: error)
                return .unretryableError(error)
            }

            do {
                try await backupRequestManager.deleteMediaObjects(
                    objects: [BackupArchive.Request.DeleteMediaTarget(
                        cdn: record.record.cdnNumber,
                        mediaId: mediaId,
                    )],
                    auth: backupAuth,
                )
            } catch let error {
                if error.isNetworkFailureOrTimeout {
                    let errorCount = await errorCounts.updateCount(record.id)
                    if error.isRetryable, errorCount < Constants.maxRetryableErrorCount {
                        return .retryableError(error)
                    } else {
                        return .unretryableError(error)
                    }
                } else {
                    return .unretryableError(error)
                }
            }

            return .success
        }

        func didSucceed(record: Store.Record, tx: DBWriteTransaction) throws {
            Logger.info("Finished deleting backup attachment \(record.id)")

            // Any time we successfully delete anything on remote cdn, optimistically wipe
            // the local state saying we've consumed all media tier quota; we will set it
            // again if the server tells us we're still out of space on next upload attempt.
            backupSettingsStore.setHasConsumedMediaTierCapacity(false, tx: tx)
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            Logger.warn("Failed deleting backup attachment \(record.id), isRetryable: \(isRetryable), error: \(error)")
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) throws {
            Logger.info("Cancelled deleting backup attachment \(record.id)")
        }
    }

    // MARK: - TaskRecordStore

    struct TaskRecord: SignalServiceKit.TaskRecord {
        let id: OrphanedBackupAttachment.IDType
        let record: OrphanedBackupAttachment
    }

    class TaskStore: TaskRecordStore {

        private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore

        init(orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore) {
            self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            return try orphanedBackupAttachmentStore.peek(count: count, tx: tx).map { record in
                return TaskRecord(id: record.id!, record: record)
            }
        }

        func removeRecord(_ record: TaskRecord, tx: DBWriteTransaction) throws {
            try orphanedBackupAttachmentStore.remove(record.record, tx: tx)
        }
    }

    private enum Constants {
        static let maxRetryableErrorCount = 2
    }
}

#if TESTABLE_BUILD

open class OrphanedBackupAttachmentQueueRunnerMock: OrphanedBackupAttachmentQueueRunner {

    public init() {}

    open func runIfNeeded() async throws {
        // Do nothing
    }
}

#endif
