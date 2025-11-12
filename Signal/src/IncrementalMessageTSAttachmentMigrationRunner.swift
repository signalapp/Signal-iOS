//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Manages the BGProcessingTask for doing the migration as well as the runner for
/// doing so while the main app is running.
class IncrementalMessageTSAttachmentMigrationRunner: BGProcessingTaskRunner {
    private let appContext: AppContext
    private let db: SDSDatabaseStorage
    private let store: IncrementalTSAttachmentMigrationStore
    private let migrator: () -> any IncrementalMessageTSAttachmentMigrator

    init(
        appContext: AppContext,
        db: SDSDatabaseStorage,
        store: IncrementalTSAttachmentMigrationStore,
        migrator: @escaping () -> any IncrementalMessageTSAttachmentMigrator
    ) {
        self.appContext = appContext
        self.db = db
        self.store = store
        self.migrator = migrator
    }

    // MARK: - BGProcessingTaskRunner

    static let taskIdentifier = "MessageAttachmentMigrationTask"
    static let logPrefix: String? = nil
    static let requiresNetworkConnectivity = false
    static let requiresExternalPower = false

    func run() async throws {
        let logger = MigrationLogger(appContext: appContext, store: store)
        try await self.runInBatches(
            willBegin: { store.willAttemptMigrationUntilFinished() },
            runNextBatch: {
                return await migrator().runNextBatch(logger: logger)
            }
        )
    }

    public func startCondition() -> BGProcessingTaskStartCondition {
        let state = db.read(block: store.getState(tx:))
        if state != .finished {
            return .asSoonAsPossible
        } else {
            return .never
        }
    }

    private class MigrationLogger: TSAttachmentMigrationLogger {

        private let appContext: AppContext
        private let store: IncrementalTSAttachmentMigrationStore

        init(
            appContext: AppContext,
            store: IncrementalTSAttachmentMigrationStore
        ) {
            self.appContext = appContext
            self.store = store
        }

        func didFatalError(_ logString: String) {
            let logString = ScrubbingLogFormatter().redactMessage(logString)
            store.bgProcessingTaskDidExperienceError(logString: logString)
        }

        func flagDBCorrupted() {
            DatabaseCorruptionState.flagDatabaseAsCorrupted(userDefaults: appContext.appUserDefaults())
        }

        func checkpoint(_ checkpointString: String) {
            store.saveLastCheckpoint(checkpointString)
        }
    }
}
