//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Observes insertions to the OrphanedAttachmentRecord table and deletes the associated files added to it.
public protocol OrphanedAttachmentCleaner {

    /// Begin observing changes to the ``OrphanedAttachmentRecord`` table.
    /// Should be called on every app launch.
    ///
    /// Whenever a new row is inserted into the table, starts up a job to delete any files
    /// associated with rows in the table (cleaning up a deleted attachment's files) and
    /// removes the row once file deletion is confirmed.
    ///
    /// Also fires immediately to clean up existing rows in the table, if any remained from prior app launches.
    func beginObserving()

    func runUntilFinished() async throws(CancellationError)

    /// Marks pending attachment files for deletion.
    /// Call `releasePendingAttachment` to un-mark the files for deletion
    /// once the attachment has been created.
    ///
    /// This method opens a write transaction and commits the changes; this is required
    /// so that after this method returns attachment files can be safely created/moved at
    /// the target file paths.
    ///
    /// Return the id which can be used to release the pending attachment.
    func commitPendingAttachment(
        _ insertableRecord: OrphanedAttachmentRecord.InsertableRecord,
    ) async -> OrphanedAttachmentRecord.RowId

    /// See commitPendingAttachmentWithSneakyTransaction; does the same thing for
    /// multiple orphan records at once, keyed as chosen by the caller.
    func commitPendingAttachments<Key: Hashable>(
        _ insertableRecords: [Key: OrphanedAttachmentRecord.InsertableRecord],
    ) async -> [Key: OrphanedAttachmentRecord.RowId]

    /// Un-marks a pending attachment for deletion IFF currently marked for deletion.
    ///
    /// If the id is not found, throws an error.
    /// Why? Here is the expected sequence:
    /// 1. Reserve attachment file locations (assign random file UUIDs)
    /// 2. `commitPendingAttachment`
    /// 3. Copy/write files into the reserved file locations
    /// 4. Open write transaction
    /// 5. Create Attachment table row
    /// 6. Call `releasePendingAttachment`
    /// 7. Close write transaction
    ///
    /// If the attachment file(s) get deleted between steps 2 and 4, then this
    /// method will crash in step 6 rolling back the write transaction in step 4/5.
    ///
    /// This ensures that when we reach step 7, either:
    /// A. Step 6 succeeded, attachment is created and not marked for deletion
    /// B. Step 6 failed, everything is rolled back and we start from step 1 again.
    /// There is never a case where step 5 succeeds but we have deleted files,
    /// or step 5 fails but we didn't delete the files.
    func releasePendingAttachment(
        withId: OrphanedAttachmentRecord.RowId,
        tx: DBWriteTransaction,
    )
}

public class OrphanedAttachmentCleanerImpl: OrphanedAttachmentCleaner {

    private let db: DB
    private let taskScheduler: Shims.TaskScheduler

    private var observer: OrphanTableObserver!

    public convenience init(
        dateProvider: @escaping DateProvider,
        db: DB,
    ) {
        self.init(
            dateProvider: dateProvider,
            db: db,
            fileSystem: Wrappers.OWSFileSystem(),
            taskScheduler: Wrappers.TaskScheduler(),
        )
    }

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        fileSystem: Shims.OWSFileSystem,
        taskScheduler: Shims.TaskScheduler,
    ) {
        self.db = db
        self.taskScheduler = taskScheduler
        self.observer = OrphanTableObserver(
            jobRunner: JobRunner(
                dateProvider: dateProvider,
                db: db,
                fileSystem: fileSystem,
                cleaner: self,
            ),
            taskScheduler: taskScheduler,
        )
    }

    public func beginObserving() {
        // Kick off a run immediately for any rows already in the database.
        taskScheduler.task { [observer] in
            try? await observer!.jobRunner.runNextCleanupJob()
        }
        // Begin observing the database for changes.
        db.add(transactionObserver: observer, extent: .observerLifetime)
    }

    public func runUntilFinished() async throws(CancellationError) {
        try await observer.jobRunner.runNextCleanupJob()
    }

    public func commitPendingAttachment(
        _ insertableRecord: OrphanedAttachmentRecord.InsertableRecord,
    ) async -> OrphanedAttachmentRecord.RowId {
        let id = UUID()
        return await commitPendingAttachments([id: insertableRecord])[id]!
    }

    public func commitPendingAttachments<Key: Hashable>(
        _ insertableRecords: [Key: OrphanedAttachmentRecord.InsertableRecord],
    ) async -> [Key: OrphanedAttachmentRecord.RowId] {
        return await db.awaitableWrite { tx in
            var results = [Key: OrphanedAttachmentRecord.RowId]()
            for (key, insertableRecord) in insertableRecords {
                // Ensure we mark this attachment as pending.
                owsPrecondition(insertableRecord.isPendingAttachment, "must be pending")
                let record = OrphanedAttachmentRecord.insertRecord(insertableRecord, tx: tx)
                results[key] = record.id
            }
            return results
        }
    }

    public func releasePendingAttachment(withId id: OrphanedAttachmentRecord.RowId, tx: DBWriteTransaction) {
        let db = tx.database
        let foundRecord = failIfThrows { try OrphanedAttachmentRecord.fetchOne(db, key: id) }
        guard let foundRecord else {
            owsFailDebug("Pending attachment not marked for deletion")
            return
        }
        failIfThrows { try foundRecord.delete(db) }
    }

    private actor JobRunner {
        private let dateProvider: DateProvider
        private let db: DB
        private nonisolated let fileSystem: Shims.OWSFileSystem
        private weak var cleaner: OrphanedAttachmentCleanerImpl?

        private let taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

        init(
            dateProvider: @escaping DateProvider,
            db: DB,
            fileSystem: Shims.OWSFileSystem,
            cleaner: OrphanedAttachmentCleanerImpl,
        ) {
            self.dateProvider = dateProvider
            self.db = db
            self.fileSystem = fileSystem
            self.cleaner = cleaner
        }

        func runNextCleanupJob() async throws(CancellationError) {
            try await taskQueue.run { () throws(CancellationError) -> Void in
                try await self._runNextCleanupJob()
            }
        }

        private func _runNextCleanupJob() async throws(CancellationError) {
            guard CurrentAppContext().isMainApp else {
                // Don't run the cleaner outside the main app.
                return
            }

            // Clean any non-pending attachments. These have been explicitly orphaned, so are game to
            // clean up at any time
            try await cleanOrphanedAttachments(
                query: OrphanedAttachmentRecord
                    .filter(Column(OrphanedAttachmentRecord.CodingKeys.isPendingAttachment) == false),
            )

            // Clean any pending attachments. In normal operation, a pending orphan reference should
            // be cleared once the attachment has been properly handled. Since this can take some time
            // and can be running simultaneous with the cleaner, skip over any relatively recent (~30s)
            // pending attachments and deal with those in a future run, if necessary.
            let filterTimestamp = dateProvider().addingTimeInterval(-30).ows_millisecondsSince1970
            try await cleanOrphanedAttachments(
                query: OrphanedAttachmentRecord
                    .filter(Column(OrphanedAttachmentRecord.CodingKeys.isPendingAttachment) == true)
                    .filter(Column(OrphanedAttachmentRecord.CodingKeys.timestamp) < filterTimestamp),
            )
        }

        func cleanOrphanedAttachments(query: QueryInterfaceRequest<OrphanedAttachmentRecord>) async throws(CancellationError) {
            var lastOrphanedRecordID: Int64 = 0
            try await TimeGatedBatch.processAll(db: db) { tx throws(CancellationError) in
                if Task.isCancelled {
                    throw CancellationError()
                }

                let nextRecord = failIfThrows {
                    try query
                        .filter(Column(OrphanedAttachmentRecord.CodingKeys.id) > lastOrphanedRecordID)
                        .fetchOne(tx.database)
                }
                guard let nextRecord else {
                    return .done(())
                }

                do {
                    // Delete within the database write lock to ensure we don't
                    // conflict with the pending attachment send flow.
                    try self.deleteFiles(record: nextRecord)
                    failIfThrows {
                        _ = try nextRecord.delete(tx.database)
                    }
                    Logger.info(
                        "Cleaned up \(nextRecord.isPendingAttachment ? "pending " : "")" +
                            "orphaned attachment files [\(nextRecord.id)]: " +
                            "local: \(nextRecord.localRelativeFilePath ?? "") " +
                            "thumbnail: \(nextRecord.localRelativeFilePathThumbnail != nil) " +
                            "audio: \(nextRecord.localRelativeFilePathAudioWaveform != nil) " +
                            "video: \(nextRecord.localRelativeFilePathVideoStillFrame != nil)",
                    )
                } catch {
                    Logger.error("Failed to clean up orphan table row \(nextRecord.id): \(error)")
                }

                // Advance the recordID regardless of failure; will retry on next cron run.
                lastOrphanedRecordID = nextRecord.id
                return .more
            }
        }

        private nonisolated func deleteFiles(record: OrphanedAttachmentRecord) throws {
            let relativeFilePaths: [String] = [
                record.localRelativeFilePath,
                record.localRelativeFilePathThumbnail,
                record.localRelativeFilePathAudioWaveform,
                record.localRelativeFilePathVideoStillFrame,
            ].compacted()

            try relativeFilePaths.forEach { relativeFilePath in
                let fileURL = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: relativeFilePath)
                try fileSystem.deleteFileIfExists(url: fileURL)
            }

            if let localRelativeFilePath = record.localRelativeFilePath {
                // Delete any cached thumbnails as well.
                for quality in AttachmentThumbnailQuality.allCases {
                    let cacheFileUrl = AttachmentThumbnailQuality.thumbnailCacheFileUrl(
                        attachmentLocalRelativeFilePath: localRelativeFilePath,
                        at: quality,
                    )
                    try fileSystem.deleteFileIfExists(url: cacheFileUrl)
                }
            }
        }
    }

    // MARK: - Observation

    private class OrphanTableObserver: TransactionObserver {

        fileprivate let jobRunner: JobRunner
        private let taskScheduler: Shims.TaskScheduler

        lazy var runNextCleanupJobEvent = DebouncedEvents.build(
            mode: .lastOnly,
            maxFrequencySeconds: 1.0,
            onQueue: .sharedUserInitiated,
            notifyBlock: { [weak self] in
                self?.taskScheduler.task { [weak self] in
                    try await self?.jobRunner.runNextCleanupJob()
                }
            },
        )

        init(
            jobRunner: JobRunner,
            taskScheduler: Shims.TaskScheduler,
        ) {
            self.jobRunner = jobRunner
            self.taskScheduler = taskScheduler
        }

        func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
            switch eventKind {
            case .insert:
                return eventKind.tableName == OrphanedAttachmentRecord.databaseTableName
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

            // When we get a matching event, run the next job _after_ committing.
            // The job should pick up whatever new row(s) got added to the table.
            runNextCleanupJobEvent.requestNotify()
        }

        func databaseDidRollback(_ db: GRDB.Database) {}
    }
}

extension OrphanedAttachmentCleanerImpl {
    public enum Shims {
        public typealias OWSFileSystem = _OrphanedAttachmentCleanerImpl_OWSFileSystemShim
        public typealias TaskScheduler = _OrphanedAttachmentCleanerImpl_TaskSchedulerShim
    }

    public enum Wrappers {
        public typealias OWSFileSystem = _OrphanedAttachmentCleanerImpl_OWSFileSystemWrapper
        public typealias TaskScheduler = _OrphanedAttachmentCleanerImpl_TaskSchedulerWrapper
    }
}

public protocol _OrphanedAttachmentCleanerImpl_OWSFileSystemShim {

    func deleteFileIfExists(url: URL) throws
}

public class _OrphanedAttachmentCleanerImpl_OWSFileSystemWrapper: _OrphanedAttachmentCleanerImpl_OWSFileSystemShim {

    public init() {}

    public func deleteFileIfExists(url: URL) throws {
        try OWSFileSystem.deleteFileIfExists(url: url)
    }
}

public protocol _OrphanedAttachmentCleanerImpl_TaskSchedulerShim {

    func task(_ block: @Sendable @escaping () async throws -> Void)
}

public class _OrphanedAttachmentCleanerImpl_TaskSchedulerWrapper: _OrphanedAttachmentCleanerImpl_TaskSchedulerShim {

    public init() {}

    public func task(_ block: @Sendable @escaping () async throws -> Void) {
        Task(operation: block)
    }
}
