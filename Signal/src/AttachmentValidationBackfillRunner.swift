//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

/// Manages the BGProcessingTask for doing the backfill of attachments that were
/// validated using an old version of the validator and need revalidation.
public class AttachmentValidationBackfillRunner: BGProcessingTaskRunner {

    // MARK: - BGProcessingTaskRunner

    // TODO: add migrator class
    public typealias Migrator = AttachmentValidationBackfillMigrator
    public typealias Store = AttachmentValidationBackfillStore

    public static let taskIdentifier = "AttachmentValidationBackfillMigrator"

    public static let requiresNetworkConnectivity = false

    public static let logger = PrefixedLogger(prefix: "AttachmentValidationBackfillMigrator")

    public static func runNextBatch(
        migrator: Migrator,
        store: Store,
        db: SDSDatabaseStorage
    ) async throws -> Bool {
        return try await migrator.runNextBatch()
    }

    public static func shouldLaunchBGProcessingTask(store: Store, db: SDSDatabaseStorage) -> Bool {
        return db.read { tx in
            do {
                return try store.needsToRun(tx: tx.asV2Read)
            } catch let error {
                Self.logger.error("Failed to check status \(error)")
                return false
            }
        }
    }

    public static func willBeginBGProcessingTask(
        store: Store,
        db: SDSDatabaseStorage
    ) {}
}
