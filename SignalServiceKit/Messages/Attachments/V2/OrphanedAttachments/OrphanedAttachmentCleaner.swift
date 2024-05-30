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

    private let observer: OrphanTableObserver

    public convenience init(
        db: SDSDatabaseStorage,
        featureFlags: Shims.FeatureFlags = Wrappers.FeatureFlags(),
        fileSystem: Shims.OWSFileSystem = Wrappers.OWSFileSystem()
    ) {
        self.init(db: db.grdbStorage.pool, featureFlags: featureFlags, fileSystem: fileSystem)
    }

    internal init(
        db: DatabaseWriter,
        featureFlags: Shims.FeatureFlags,
        fileSystem: Shims.OWSFileSystem
    ) {
        self.db = db
        self.featureFlags = featureFlags
        self.observer = OrphanTableObserver(JobRunner(db: db, fileSystem: fileSystem))
    }

    public func beginObserving() {
        guard featureFlags.readV2Attachments else {
            return
        }

        // Kick off a run immediately for any rows already in the database.
        Task {
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

        func runNextCleanupJob() async {
            // TODO
        }
    }

    // MARK: - Observation

    private class OrphanTableObserver: TransactionObserver {

        fileprivate let jobRunner: JobRunner

        init(_ jobRunner: JobRunner) {
            self.jobRunner = jobRunner
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
            Task { [jobRunner] in
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
    }
    public enum Wrappers {
        public typealias FeatureFlags = _OrphanedAttachmentCleanerImpl_FeatureFlagsWrapper
        public typealias OWSFileSystem = _OrphanedAttachmentCleanerImpl_OWSFileSystemWrapper
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

    func fileOrFolderExists(url: URL) -> Bool

    func deleteFile(url: URL) throws
}

public class _OrphanedAttachmentCleanerImpl_OWSFileSystemWrapper: _OrphanedAttachmentCleanerImpl_OWSFileSystemShim {

    public init() {}

    public func fileOrFolderExists(url: URL) -> Bool {
        return OWSFileSystem.fileOrFolderExists(url: url)
    }

    public func deleteFile(url: URL) throws {
        try OWSFileSystem.deleteFile(url: url)
    }
}
