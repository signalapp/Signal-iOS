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
        db: DB,
    ) {
        self.init(
            db: db,
            fileSystem: Wrappers.OWSFileSystem(),
            taskScheduler: Wrappers.TaskScheduler(),
        )
    }

    init(
        db: DB,
        fileSystem: Shims.OWSFileSystem,
        taskScheduler: Shims.TaskScheduler,
    ) {
        self.db = db
        self.taskScheduler = taskScheduler
        self.observer = OrphanTableObserver(
            jobRunner: JobRunner(
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
                let id = record.id
                skippedRowIds.update(block: { $0.insert(id) })
                results[key] = id
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

        // Remove from skipped row ids.
        // This isn't critical; now that the row is gone skipping the id does nothing.
        skippedRowIds.update(block: { $0.remove(id) })
    }

    // Tracks the row ids that should be skipped for the current in-memory process.
    // This can be because they failed to delete, or they are pending attachments.
    // We track these so we can skip them and not block subsequent rows from deletion.
    // We keep this in memory; we will retry on next app launch.
    //
    // Should only be accessed from within a write transaction.
    fileprivate var skippedRowIds = AtomicValue<Set<OrphanedAttachmentRecord.RowId>>(Set(), lock: .init())

    private actor JobRunner {

        private let db: DB
        private nonisolated let fileSystem: Shims.OWSFileSystem
        private weak var cleaner: OrphanedAttachmentCleanerImpl?

        private let taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

        init(
            db: DB,
            fileSystem: Shims.OWSFileSystem,
            cleaner: OrphanedAttachmentCleanerImpl,
        ) {
            self.db = db
            self.fileSystem = fileSystem
            self.cleaner = cleaner
        }

        func runNextCleanupJob() async throws(CancellationError) {
            try await taskQueue.run {
                await self._runNextCleanupJob()
            }
        }

        private func _runNextCleanupJob() async {
            // TODO: [Backups] does the BGProcessingTask count as "isMainApp"? I think yes but
            // if this doesn't run this is the thing to check.
            guard CurrentAppContext().isMainApp else {
                // Don't run the cleaner outside the main app.
                return
            }
            guard let nextRecord = fetchNextOrphanRecord() else {
                return
            }

            do {
                try Task.checkCancellation()
            } catch {
                return
            }
            await Task.yield()

            if nextRecord.isPendingAttachment {
                // This deletion job is potentially racing with the share
                // share extension's attachment sending flow. This job wants to
                // delete the files of the pending attachment being sent.
                //
                // If this job wins, the attachment send will fail (it will throw
                // an error when calling `releasePendingAttachment`).
                // That's recoverable, but its better if the send flow wins.
                // Add a delay to increase the chances of the send flow winning.
                try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)
            }

            let cleaner = self.cleaner

            try? await db.awaitableWrite { tx in
                // Ensure the record is still around; if it was a pending attachment
                // and the send flow finished while this job slept, just skip & exit.
                // This happens within the database write lock to ensure correctness.
                guard try nextRecord.exists(tx.database) else {
                    Logger.info("Skipping since-deleted orphan row")
                    return
                }
                if
                    let skippedRowIds = cleaner?.skippedRowIds,
                    skippedRowIds.get().contains(nextRecord.id)
                {
                    Logger.info("Skipping a marked-as-skipped row id")
                    return
                }
                do {
                    // Delete within the database write lock to ensure we don't
                    // conflict with the pending attachment send flow.
                    try self.deleteFiles(record: nextRecord)
                    _ = try nextRecord.delete(tx.database)
                    Logger.info("Cleaned up orphaned attachment files")
                    return
                } catch {
                    Logger.error("Failed to clean up orphan table row: \(error)")
                    let skipId = nextRecord.id
                    cleaner?.skippedRowIds.update(block: { $0.insert(skipId) })
                }
            }

            // Kick off the next run whether the prior run succeeded or not.
            await _runNextCleanupJob()
        }

        private func fetchNextOrphanRecord() -> OrphanedAttachmentRecord? {
            return db.read { tx -> OrphanedAttachmentRecord? in
                guard let skippedRowIds = cleaner?.skippedRowIds.get(), !skippedRowIds.isEmpty else {
                    return try? OrphanedAttachmentRecord.fetchOne(tx.database)
                }
                let rowIdColumn = Column(OrphanedAttachmentRecord.CodingKeys.id)
                var query: QueryInterfaceRequest<OrphanedAttachmentRecord>?

                let skippedRowIdsForQuery: any Collection<OrphanedAttachmentRecord.RowId>
                let skippedRowIdsForInMemoryFilter: any Collection<OrphanedAttachmentRecord.RowId>
                if skippedRowIds.count > 50 {
                    Logger.warn("Too many skipped row ids!")
                    (
                        skippedRowIdsForQuery,
                        skippedRowIdsForInMemoryFilter,
                    ) = skippedRowIds.split(
                        at: skippedRowIds.index(skippedRowIds.startIndex, offsetBy: 50),
                    )
                } else {
                    skippedRowIdsForQuery = skippedRowIds
                    skippedRowIdsForInMemoryFilter = []
                }

                for skippedRowId in skippedRowIdsForQuery {
                    if let querySoFar = query {
                        query = querySoFar.filter(rowIdColumn != skippedRowId)
                    } else {
                        query = OrphanedAttachmentRecord.filter(rowIdColumn != skippedRowId)
                    }
                }
                if skippedRowIdsForInMemoryFilter.isEmpty {
                    return try? query?.fetchOne(tx.database)
                } else {
                    let cursor = try? query?.fetchCursor(tx.database)
                    while let next = try? cursor?.next() {
                        if !skippedRowIdsForInMemoryFilter.contains(next.id) {
                            return next
                        }
                    }
                    return nil
                }
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
            taskScheduler.task { [jobRunner] in
                try await jobRunner.runNextCleanupJob()
            }
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
