//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Manages the BGProcessingTask for doing the migration as well as the runner for
/// doing so while the main app is running.
class IncrementalMessageTSAttachmentMigrationRunner: BGProcessingTaskRunner {
    private let db: SDSDatabaseStorage
    private let store: IncrementalTSAttachmentMigrationStore
    private let migrator: () -> any IncrementalMessageTSAttachmentMigrator

    init(
        db: SDSDatabaseStorage,
        store: IncrementalTSAttachmentMigrationStore,
        migrator: @escaping () -> any IncrementalMessageTSAttachmentMigrator
    ) {
        self.db = db
        self.store = store
        self.migrator = migrator
    }

    // MARK: - BGProcessingTaskRunner

    public static let taskIdentifier = "MessageAttachmentMigrationTask"

    public static let requiresNetworkConnectivity = false

    func run() async throws {
        try await self.runInBatches(
            willBegin: { store.willAttemptMigrationUntilFinished() },
            runNextBatch: {
                return await migrator().runNextBatch(errorLogger: {
                    let logString = ScrubbingLogFormatter().redactMessage($0)
                    store.bgProcessingTaskDidExperienceError(logString: logString)
                })
            }
        )
    }

    public func shouldLaunchBGProcessingTask() -> Bool {
        let state = db.read(block: store.getState(tx:))
        return state != .finished
    }
}
