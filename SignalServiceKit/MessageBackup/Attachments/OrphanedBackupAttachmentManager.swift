//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// In charge of deleting attachments off the backup cdn after they've been deleted locally (or otherwise orphaned).
public protocol OrphanedBackupAttachmentManager {}

public class OrphanedBackupAttachmentManagerImpl: OrphanedBackupAttachmentManager {

    private let appReadiness: AppReadiness
    private let db: any DB
    private let tableObserver: TableObserver
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        appReadiness: AppReadiness,
        attachmentStore: AttachmentStore,
        db: any DB,
        messageBackupKeyMaterial: MessageBackupKeyMaterial,
        messageBackupRequestManager: MessageBackupRequestManager,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
        tsAccountManager: TSAccountManager
    ) {
        self.appReadiness = appReadiness
        self.db = db
        self.tsAccountManager = tsAccountManager
        let taskRunner = TaskRunner(
            attachmentStore: attachmentStore,
            db: db,
            messageBackupKeyMaterial: messageBackupKeyMaterial,
            messageBackupRequestManager: messageBackupRequestManager,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            tsAccountManager: tsAccountManager
        )
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: 1, /* one at a time, speed isn't critical */
            db: db,
            runner: taskRunner
        )
        // Avoid handing self to tableObserver both to limit its API
        // surface and avoid retain cycles.
        var runIfNeeded: (() -> Void)?
        self.tableObserver = TableObserver {
            runIfNeeded?()
        }
        runIfNeeded = { [weak self] in
            self?.runIfNeeded()
        }

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.runIfNeeded()
            self?.startObserving()
        }
    }

    private func runIfNeeded() {
        guard appReadiness.isAppReady else {
            return
        }
        guard tsAccountManager.localIdentifiersWithMaybeSneakyTransaction != nil else {
            return
        }
        Task {
            try await taskQueue.loadAndRunTasks()
        }
    }

    // MARK: - Observation

    private func startObserving() {
        db.add(transactionObserver: tableObserver)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didUpdateRegistrationState),
            name: .registrationStateDidChange,
            object: nil
        )
    }

    @objc
    private func didUpdateRegistrationState() {
        runIfNeeded()
    }

    private class TableObserver: TransactionObserver {

        private let runIfNeeded: () -> Void

        init(runIfNeeded: @escaping () -> Void) {
            self.runIfNeeded = runIfNeeded
        }

        func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
            switch eventKind {
            case .insert:
                return eventKind.tableName == OrphanedBackupAttachment.databaseTableName
            case .delete, .update:
                return false
            }
        }

        /// `observes(eventsOfKind:)` filtering _only_ applies to `databaseDidChange`,  _not_ `databaseDidCommit`.
        /// We want to filter, but only want to _do_ anything after the changes commit.
        /// Use this bool to track when the filter is passed (didChange) so we know whether to do anything on didCommit .
        private var shouldRunOnNextCommit = false

        func databaseDidChange(with event: DatabaseEvent) {
            shouldRunOnNextCommit = true
        }

        func databaseDidCommit(_ db: GRDB.Database) {
            guard shouldRunOnNextCommit else {
                return
            }
            shouldRunOnNextCommit = false

            // When we get a matching event, run the next task _after_ committing.
            // The task queue should pick up whatever new row(s) got added to the table.
            // This is harmless if the queue is already running tasks.
            runIfNeeded()
        }

        func databaseDidRollback(_ db: GRDB.Database) {}
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let attachmentStore: AttachmentStore
        private let db: any DB
        private let messageBackupKeyMaterial: MessageBackupKeyMaterial
        private let messageBackupRequestManager: MessageBackupRequestManager
        private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        init(
            attachmentStore: AttachmentStore,
            db: any DB,
            messageBackupKeyMaterial: MessageBackupKeyMaterial,
            messageBackupRequestManager: MessageBackupRequestManager,
            orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
            tsAccountManager: TSAccountManager
        ) {
            self.attachmentStore = attachmentStore
            self.db = db
            self.messageBackupKeyMaterial = messageBackupKeyMaterial
            self.messageBackupRequestManager = messageBackupRequestManager
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
            let (localAci, attachment) = db.read { tx in
                let attachment: Attachment?
                if let mediaName = record.record.mediaName {
                    attachment = attachmentStore.fetchAttachment(mediaName: mediaName, tx: tx)
                } else {
                    attachment = nil
                }

                return (
                    tsAccountManager.localIdentifiers(tx: tx)?.aci,
                    attachment
                )
            }

            // Check the existing attachment only if this was locally
            // orphaned (the record has a mediaName).
            if record.record.mediaName != nil {
                // If an attachment exists with the same media name, that means a new
                // copy with the same file contents got created between orphan record
                // insertion and now. Most likely we want to cancel this delete.
                if
                    let attachment,
                    attachment.mediaTierInfo?.cdnNumber == nil
                {
                    // The new attachment hasn't been uploaded to backups. It might
                    // be uploading right now, so don't try and delete.
                    return .cancelled
                } else if
                    let attachment,
                    let cdnNumber = attachment.mediaTierInfo?.cdnNumber,
                    cdnNumber == record.record.cdnNumber
                {
                    // The new copy has been uploaded to the same cdn.
                    // Don't delete it.
                    return .cancelled
                } else if
                    let attachment,
                    let cdnNumber = attachment.mediaTierInfo?.cdnNumber,
                    cdnNumber > record.record.cdnNumber
                {
                    // This is rare, but we could end up with two copies of
                    // the same attachment on two cdns (say 3 and 4). We want
                    // to allow deleting the copy on the older cdn but never the newer one.
                    // If the delete record is for 4 and the attachment is uploaded
                    // to 3, for all we know there's a job enqueued right now to
                    // "upload" it to 4 so we don't wanna delete and race with that.
                    Logger.info("Deleting duplicate upload at older cdn \(record.record.cdnNumber)")
                    return .cancelled
                }
            }

            guard let localAci else {
                let error = OWSAssertionError("Deleting without being registered")
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }

            let mediaId: Data

            if let recordMediaId = record.record.mediaId {
                mediaId = recordMediaId
            } else if let type = record.record.type, let mediaName = record.record.mediaName {
                let mediaTierEncryptionType: MediaTierEncryptionType
                switch type {
                case .fullsize:
                    mediaTierEncryptionType = .attachment
                case .thumbnail:
                    mediaTierEncryptionType = .thumbnail
                }

                do {
                    (mediaId) = try db.read { tx in
                        (
                            try messageBackupKeyMaterial.mediaEncryptionMetadata(
                                mediaName: mediaName,
                                type: mediaTierEncryptionType,
                                tx: tx
                            ).mediaId
                        )
                    }
                } catch let error {
                    Logger.error("Failed to generate media IDs")
                    return .unretryableError(error)
                }
            } else {
                return .unretryableError(OWSAssertionError("Invalid record"))
            }

            let messageBackupAuth: MessageBackupServiceAuth
            do {
                messageBackupAuth = try await messageBackupRequestManager.fetchBackupServiceAuth(
                    localAci: localAci,
                    auth: .implicit()
                )
            } catch let error {
                try? await loader.stop(reason: error)
                return .unretryableError(error)
            }

            do {
                try await messageBackupRequestManager.deleteMediaObjects(
                    objects: [MessageBackup.Request.DeleteMediaTarget(
                        cdn: record.record.cdnNumber,
                        mediaId: mediaId
                    )],
                    auth: messageBackupAuth
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

        func didSucceed(record: Store.Record, tx: any DBWriteTransaction) throws {
            Logger.info("Finished deleting backup attachment \(record.id)")
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: any DBWriteTransaction) throws {
            Logger.warn("Failed deleting backup attachment \(record.id), isRetryable: \(isRetryable), error: \(error)")
        }

        func didCancel(record: Store.Record, tx: any DBWriteTransaction) throws {
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

open class OrphanedBackupAttachmentManagerMock: OrphanedBackupAttachmentManager {

    public init() {}
}

#endif
