//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class LocalFileBackupBGProcessingTaskRunner: BGProcessingTaskRunner {
    private enum StoreKeys {
        static let lastCompletionDate: String = "lastCompletionDate"
    }

    private let backgroundMessageFetcherFactory: () -> BackgroundMessageFetcherFactory
    private let localFileBackupStore: LocalFileBackupStore
    private let dateProvider: DateProvider
    private let db: DB
    private let exportJobRunner: () -> LocalFileBackupExportJobRunner
    private let kvStore: NewKeyValueStore
    private let tsAccountManager: () -> TSAccountManager

    init(
        backgroundMessageFetcherFactory: @escaping () -> BackgroundMessageFetcherFactory,
        localFileBackupStore: LocalFileBackupStore,
        dateProvider: @escaping DateProvider,
        db: SDSDatabaseStorage,
        exportJobRunner: @escaping () -> LocalFileBackupExportJobRunner,
        tsAccountManager: @escaping () -> TSAccountManager,
    ) {
        self.backgroundMessageFetcherFactory = backgroundMessageFetcherFactory
        self.localFileBackupStore = localFileBackupStore
        self.dateProvider = dateProvider
        self.db = db
        self.exportJobRunner = exportJobRunner
        self.kvStore = NewKeyValueStore(collection: "LocalFileBackupBGProcessingTaskRunner")
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - BGProcessingTaskRunner

    static let taskIdentifier = "LocalFileBackupBGProcessingTaskRunner"
    static let logPrefix: String? = "[LocalFileBackups][ExportJob]"
    static let requiresNetworkConnectivity = false
    static let requiresExternalPower = true

    func run() async throws {
        try await runWithChatConnection(
            backgroundMessageFetcherFactory: backgroundMessageFetcherFactory(),
            operation: {
                let exportJobRunner = exportJobRunner()

                if let existingRun = exportJobRunner.cancelIfRunning() {
                    try? await existingRun.value
                }

                try await withTaskCancellationHandler(
                    operation: { () async throws -> Void in
                        let newRun = exportJobRunner.startIfNecessary(mode: .bgProcessingTask)
                        try await newRun.value
                    },
                    onCancel: { () -> Void in
                        _ = exportJobRunner.cancelIfRunning()
                    },
                )

                await db.awaitableWrite { tx in
                    kvStore.writeValue(dateProvider(), forKey: StoreKeys.lastCompletionDate, tx: tx)
                }
            },
        )
    }

    func startCondition() -> BGProcessingTaskStartCondition {
        return db.read { tx -> BGProcessingTaskStartCondition in
            guard tsAccountManager().registrationState(tx: tx).isRegisteredPrimaryDevice else {
                return .never
            }

            let isLocalFileBackupsEnabled = localFileBackupStore.localBackupsEnabled(tx: tx)
            if !isLocalFileBackupsEnabled {
                return .never
            }

            // We want this task to run to completion nightly, so intentionally
            // use a distinct "last Backup date" than what's saved (and shared)
            // in LocalFileBackupStore.
            let lastLocalBackupDate = kvStore.fetchValue(Date.self, forKey: StoreKeys.lastCompletionDate, tx: tx) ?? .distantPast

            // If a day has passed and we didn't back up, do so right away.
            if Date().timeIntervalSince(lastLocalBackupDate) > (.day * 1.5) {
                return .asSoonAsPossible
            }

            // Otherwise aim for dead of the night, but offset from remote backups (3:30am) in the local timezone
            // to give the least chance of interruption, and less of a chance of overlap of the two backups.
            let calendar = Calendar.current
            let targetStartDate = calendar.nextDate(
                after: Date(),
                matching: DateComponents(hour: 3, minute: 30),
                matchingPolicy: .nextTime,
            )
            if let targetStartDate {
                return .after(targetStartDate)
            } else {
                // Fall back to a fixed time.
                // Add in a little buffer so that we can roughly run at any time of
                // day, every day, but aren't always creeping forward with a strict
                // minimum. For example, if we run at 10pm one day then 9pm the next
                // is fine.
                return .after(lastLocalBackupDate.addingTimeInterval(.day - (.hour * 4)))
            }
        }
    }
}
