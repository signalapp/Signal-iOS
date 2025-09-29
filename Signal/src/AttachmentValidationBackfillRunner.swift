//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Manages the BGProcessingTask for doing the backfill of attachments that were
/// validated using an old version of the validator and need revalidation.
final class AttachmentValidationBackfillRunner: BGProcessingTaskRunner {

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
    public static let requiresExternalPower = false

    func run() async throws {
        try await self.runInBatches(
            willBegin: {},
            runNextBatch: { try await migrator().runNextBatch() }
        )
    }

    public func startCondition() -> BGProcessingTaskStartCondition {
        return db.read { tx in
            do {
                if try store.needsToRun(tx: tx) {
                    return .asSoonAsPossible
                } else {
                    return .never
                }
            } catch let error {
                Logger.error("Failed to check status \(error)")
                return .never
            }
        }
    }
}
