//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalServiceKit

class LazyDatabaseMigratorRunner: BGProcessingTaskRunner {
    private let infoMessageMigrator: InfoMessageGroupUpdateMigrator

    init(
        databaseStorage: SDSDatabaseStorage,
        modelReadCaches: @escaping () -> ModelReadCaches,
        tsAccountManager: @escaping () -> TSAccountManager,
    ) {
        self.infoMessageMigrator = InfoMessageGroupUpdateMigrator(
            db: databaseStorage,
            modelReadCaches: modelReadCaches,
            tsAccountManager: tsAccountManager,
        )
    }

    static let taskIdentifier: String = "LazyDatabaseMigratorTask"
    static let logPrefix: String? = nil
    static let requiresNetworkConnectivity = false
    static let requiresExternalPower = false

    func startCondition() -> BGProcessingTaskStartCondition {
        if infoMessageMigrator.needsToRun() {
            return .asSoonAsPossible
        }

        return .never
    }

    /// Run the migrations.
    ///
    /// If you encounter an error in this method, you can update
    /// `simulatePriorCancellation` to return true and run on a simulator.
    func run() async throws {
        try await infoMessageMigrator.run()
    }

#if targetEnvironment(simulator)
    func simulatePriorCancellation() -> Bool {
        // Simulates a prior cancellation that may cause the task to run when it's
        // already finished.
        return Int.random(in: 0..<10) == 0
    }
#endif
}
