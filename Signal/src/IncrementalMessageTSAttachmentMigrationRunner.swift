//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BackgroundTasks
import Foundation
public import SignalServiceKit

/// Manages the BGProcessingTask for doing the migration as well as the runner for
/// doing so while the main app is running.
public class IncrementalMessageTSAttachmentMigrationRunner: BGProcessingTaskRunner {

    public init() {}

    // MARK: - BGProcessingTaskRunner

    public typealias Migrator = IncrementalMessageTSAttachmentMigrator
    public typealias Store = IncrementalTSAttachmentMigrationStore

    public static let taskIdentifier = "MessageAttachmentMigrationTask"

    public static let requiresNetworkConnectivity = false

    public static let logger = PrefixedLogger(prefix: "IncrementalMessageTSAttachmentMigrator")

    public static func runNextBatch(
        migrator: Migrator,
        store: Store,
        db: SDSDatabaseStorage
    ) async throws -> Bool {
        return await migrator.runNextBatch(errorLogger: {
            let logString = ScrubbingLogFormatter().redactMessage($0)
            store.bgProcessingTaskDidExperienceError(logString: logString)
        })
    }

    public static func shouldLaunchBGProcessingTask(store: Store, db: SDSDatabaseStorage) -> Bool {
        let state = db.read(block: store.getState(tx:))
        return state != .finished
    }

    public static func willBeginBGProcessingTask(
        store: Store,
        db: SDSDatabaseStorage
    ) {
        store.willAttemptMigrationUntilFinished()
    }
}
