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
}

public class OrphanedAttachmentCleanerImpl: OrphanedAttachmentCleaner {

    private let db: DatabaseWriter
    private let featureFlags: Shims.FeatureFlags
    private let taskScheduler: Shims.TaskScheduler

    private let observer: OrphanTableObserver

    public convenience init(
        db: SDSDatabaseStorage,
        featureFlags: Shims.FeatureFlags = Wrappers.FeatureFlags(),
        fileSystem: Shims.OWSFileSystem = Wrappers.OWSFileSystem(),
        taskScheduler: Shims.TaskScheduler = Wrappers.TaskScheduler()
    ) {
        self.init(
            db: db.grdbStorage.pool,
            featureFlags: featureFlags,
            fileSystem: fileSystem,
            taskScheduler: taskScheduler
        )
    }

    internal init(
        db: DatabaseWriter,
        featureFlags: Shims.FeatureFlags,
        fileSystem: Shims.OWSFileSystem,
        taskScheduler: Shims.TaskScheduler
    ) {
        self.db = db
        self.featureFlags = featureFlags
        self.taskScheduler = taskScheduler
        self.observer = OrphanTableObserver(
            jobRunner: JobRunner(
                db: db,
                fileSystem: fileSystem
            ),
            taskScheduler: taskScheduler
        )
    }

    public func beginObserving() {
        guard featureFlags.readV2Attachments else {
            return
        }

        // Kick off a run immediately for any rows already in the database.
        taskScheduler.task { [observer] in
            await observer.jobRunner.runNextCleanupJob()
        }
        // Begin observing the database for changes.
        db.add(transactionObserver: observer)
    }

    private actor JobRunner {

        private let db: DatabaseWriter
        private let fileSystem: Shims.OWSFileSystem

        init(
            db: DatabaseWriter,
            fileSystem: Shims.OWSFileSystem
        ) {
            self.db = db
            self.fileSystem = fileSystem
        }

        private var isRunning = false

        // Tracks the row ids that failed to delete for some reason.
        // We track these so we can skip them and not block subsequent rows from deletion.
        // We keep this in memory; we will retry on next app launch.
        private var failedRowIds = Set<Int64>()

        func runNextCleanupJob() async {
            guard !isRunning else {
                return
            }
            isRunning = true
            guard let nextRecord = fetchNextOrphanRecord() else {
                Logger.info("No orphaned attachments to clean up")
                isRunning = false
                return
            }

            await Task.yield()
            do {
                try deleteFiles(record: nextRecord)
                await Task.yield()
                try await db.write { db in
                    _ = try nextRecord.delete(db)
                }
            } catch {
                Logger.error("Failed to clean up orphan table row: \(error)")
                failedRowIds.insert(nextRecord.sqliteId!)

                // Kick off the next run anyway; this row will be skipped.
                isRunning = false
                await runNextCleanupJob()
            }

            Logger.info("Cleaned up orphaned attachment files")
            // Kick off the next run
            isRunning = false
            await runNextCleanupJob()
        }

        private func fetchNextOrphanRecord() -> OrphanedAttachmentRecord? {
            if failedRowIds.isEmpty {
                return try? db.read { db in try? OrphanedAttachmentRecord.fetchOne(db) }
            }
            let rowIdColumn = Column(OrphanedAttachmentRecord.CodingKeys.sqliteId)
            var query: QueryInterfaceRequest<OrphanedAttachmentRecord>?
            for failedRowId in failedRowIds {
                if let querySoFar = query {
                    query = querySoFar.filter(rowIdColumn != failedRowId)
                } else {
                    query = OrphanedAttachmentRecord.filter(rowIdColumn != failedRowId)
                }
            }
            return try? db.read { db in try? query?.fetchOne(db) }
        }

        private func deleteFiles(record: OrphanedAttachmentRecord) throws {
            let relativeFilePaths: [String] = [
                record.localRelativeFilePath,
                record.localRelativeFilePathThumbnail,
                record.localRelativeFilePathAudioWaveform,
                record.localRelativeFilePathVideoStillFrame
            ].compacted()

            try relativeFilePaths.forEach { relativeFilePath in
                let fileURL = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: relativeFilePath)
                try fileSystem.deleteFileIfExists(url: fileURL)
            }
        }
    }

    // MARK: - Observation

    private class OrphanTableObserver: TransactionObserver {

        fileprivate let jobRunner: JobRunner
        private let taskScheduler: Shims.TaskScheduler

        init(
            jobRunner: JobRunner,
            taskScheduler: Shims.TaskScheduler
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

        func databaseDidChange(with event: DatabaseEvent) {}

        func databaseDidCommit(_ db: GRDB.Database) {
            // When we get a matching event, run the next job _after_ committing.
            // The job should pick up whatever new row(s) got added to the table.
            taskScheduler.task { [jobRunner] in
                await jobRunner.runNextCleanupJob()
            }
        }

        func databaseDidRollback(_ db: GRDB.Database) {}
    }
}

extension OrphanedAttachmentCleanerImpl {
    public enum Shims {
        public typealias FeatureFlags = _OrphanedAttachmentCleanerImpl_FeatureFlagsShim
        public typealias OWSFileSystem = _OrphanedAttachmentCleanerImpl_OWSFileSystemShim
        public typealias TaskScheduler = _OrphanedAttachmentCleanerImpl_TaskSchedulerShim
    }
    public enum Wrappers {
        public typealias FeatureFlags = _OrphanedAttachmentCleanerImpl_FeatureFlagsWrapper
        public typealias OWSFileSystem = _OrphanedAttachmentCleanerImpl_OWSFileSystemWrapper
        public typealias TaskScheduler = _OrphanedAttachmentCleanerImpl_TaskSchedulerWrapper
    }
}

public protocol _OrphanedAttachmentCleanerImpl_FeatureFlagsShim {

    var readV2Attachments: Bool { get }
}

public class _OrphanedAttachmentCleanerImpl_FeatureFlagsWrapper: _OrphanedAttachmentCleanerImpl_FeatureFlagsShim {

    public init() {}

    public var readV2Attachments: Bool { FeatureFlags.readV2Attachments }
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
