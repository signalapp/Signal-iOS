//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Incrementally migrates TSAttachments owned by TSMessages to v2 attachments.
public protocol IncrementalMessageTSAttachmentMigrator {

    func runUntilFinished() async

    // Returns true if done.
    func runNextBatch() async throws -> Bool
}

public class IncrementalMessageTSAttachmentMigratorImpl: IncrementalMessageTSAttachmentMigrator {

    private let databaseStorage: SDSDatabaseStorage
    private let store: IncrementalTSAttachmentMigrationStore

    public init(
        appReadiness: AppReadiness,
        databaseStorage: SDSDatabaseStorage,
        store: IncrementalTSAttachmentMigrationStore
    ) {
        self.databaseStorage = databaseStorage
        self.store = store

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [weak self] in
            guard let self else { return }
            self.databaseStorage.read { tx in
                switch self.store.getState(tx: tx) {
                case .unstarted:
                    Logger.info("Has not started message attachment migration")
                case .started:
                    Logger.info("Partial progress on message attachment migration")
                case .finished:
                    Logger.info("Finished message attachment migration")
                }
            }
        }
    }

    public func runUntilFinished() async {
        // We DO NOT check the incrementalMigrationBreakGlass feature flag here;
        // this is used by backups which require the migration to have finished
        // and aren't enabled outside internal builds anyway.
        let state = databaseStorage.read(block: store.getState(tx:))
        switch state {
        case .finished:
            return
        case .unstarted, .started:
            Logger.info("Running until finished")
        }

        var batchCount = 0
        var didFinish = false
        while !didFinish {
            do {
                // Run in batches, instead of one big write transaction, so that
                // we can commit incremental progress if we are interrupted.
                didFinish = try await self.runNextBatch()
                batchCount += 1
            } catch let error {
                owsFailDebug("Failed migration batch, stopping after \(batchCount) batches: \(error)")
                return
            }
        }
        Logger.info("Ran until finished after \(batchCount) batches")
    }

    // Returns true if done.
    public func runNextBatch() async throws -> Bool {
        typealias Migrator = TSAttachmentMigration.TSMessageMigration

        return try await databaseStorage.awaitableWrite { tx in
            // First we try to migrate a batch of prepared messages.
            let didMigrateBatch = try Migrator.completeNextIterativeTSMessageMigrationBatch(
                tx: tx.unwrapGrdbWrite
            )
            if didMigrateBatch {
                return false
            }

            // If no messages are prepared, we try to prepare a batch of messages.
            let didPrepareBatch = try Migrator.prepareNextIterativeTSMessageMigrationBatch(
                tx: tx.unwrapGrdbWrite
            )
            if didPrepareBatch {
                try self.store.setState(.started, tx: tx)
                return false
            }

            // If there was nothing to migrate and nothing to prepare, wipe the files and finish.
            try Migrator.cleanUpTSAttachmentFiles()
            try self.store.setState(.finished, tx: tx)
            return true
        }
    }
}

public class NoOpIncrementalMessageTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator {
    public init() {}

    public func runUntilFinished() async {}

    // Returns true if done.
    public func runNextBatch() async throws -> Bool {
        return true
    }
}

#if TESTABLE_BUILD

public class IncrementalMessageTSAttachmentMigratorMock: IncrementalMessageTSAttachmentMigrator {

    public init() {}

    public func runUntilFinished() async {}

    // Returns true if done.
    public func runNextBatch() async throws -> Bool {
        return true
    }
}

#endif
