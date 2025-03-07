//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Manages the BGProcessingTask for doing the backfill of attachments that were
/// validated using an old version of the validator and need revalidation.
class AttachmentValidationBackfillRunner: BGProcessingTaskRunner {

    private let db: SDSDatabaseStorage
    private let store: AttachmentValidationBackfillStore
    private let migrator: () -> any AttachmentValidationBackfillMigrator

    init(
        db: SDSDatabaseStorage,
        store: AttachmentValidationBackfillStore,
        migrator: @escaping () -> any AttachmentValidationBackfillMigrator
    ) {
        self.db = db
        self.store = store
        self.migrator = migrator
    }

    // MARK: - BGProcessingTaskRunner

    public static let taskIdentifier = "AttachmentValidationBackfillMigrator"

    public static let requiresNetworkConnectivity = false

    func run() async throws {
        try await self.runInBatches(
            willBegin: {},
            runNextBatch: { try await migrator().runNextBatch() }
        )
    }

    public func shouldLaunchBGProcessingTask() -> Bool {
        return db.read { tx in
            do {
                return try store.needsToRun(tx: tx.asV2Read)
            } catch let error {
                Logger.error("Failed to check status \(error)")
                return false
            }
        }
    }
}
