//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class BackupBGProcessingTaskRunner: BGProcessingTaskRunner {
    private enum StoreKeys {
        static let lastCompletionDate: String = "lastCompletionDate"
    }

    private let backgroundMessageFetcherFactory: () -> BackgroundMessageFetcherFactory
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let db: DB
    private let exportJob: () -> BackupExportJob
    private let kvStore: KeyValueStore
    private let tsAccountManager: () -> TSAccountManager

    init(
        backgroundMessageFetcherFactory: @escaping () -> BackgroundMessageFetcherFactory,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: SDSDatabaseStorage,
        exportJob: @escaping () -> BackupExportJob,
        tsAccountManager: @escaping () -> TSAccountManager,
    ) {
        self.backgroundMessageFetcherFactory = backgroundMessageFetcherFactory
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.exportJob = exportJob
        self.kvStore = KeyValueStore(collection: "BackupBGProcessingTaskRunner")
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - BGProcessingTaskRunner

    static let taskIdentifier = "BackupBGProcessingTaskRunner"
    static let logPrefix: String? = "[Backups][ExportJob]"
    static let requiresNetworkConnectivity = true
    static let requiresExternalPower = true

    func run() async throws {
        try await runWithChatConnection(
            backgroundMessageFetcherFactory: backgroundMessageFetcherFactory(),
            operation: {
                try await exportJob().exportAndUploadBackup(mode: .bgProcessingTask)

                await db.awaitableWrite { tx in
                    kvStore.setDate(dateProvider(), key: StoreKeys.lastCompletionDate, transaction: tx)
                }
            }
        )
    }

    public func startCondition() -> BGProcessingTaskStartCondition {
        return db.read { (tx) -> BGProcessingTaskStartCondition in
            guard tsAccountManager().registrationState(tx: tx).isRegisteredPrimaryDevice else {
                return .never
            }

            switch backupSettingsStore.backupPlan(tx: tx) {
            case .disabled, .disabling:
                return .never
            case .free, .paid, .paidExpiringSoon, .paidAsTester:
                break
            }

            // We want this task to run to completion nightly, so intentionally
            // use a distinct "last Backup date" than what's saved (and shared)
            // in BackupSettingsStore.
            let lastBackupDate = kvStore.getDate(StoreKeys.lastCompletionDate, transaction: tx) ?? .distantPast

            // If a day has passed and we didn't back up, do so right away.
            if Date().timeIntervalSince(lastBackupDate) > (.day * 1.5) {
                return .asSoonAsPossible
            }

            // Otherwise aim for dead of the night (3am) in the local timezone
            // to give the least chance of interruption.
            let calendar = Calendar.current
            let targetStartDate = calendar.nextDate(
                after: Date(),
                matching: DateComponents(hour: 3),
                matchingPolicy: .nextTime
            )
            if let targetStartDate {
                return .after(targetStartDate)
            } else {
                // Fall back to a fixed time.
                // Add in a little buffer so that we can roughly run at any time of
                // day, every day, but aren't always creeping forward with a strict
                // minimum. For example, if we run at 10pm one day then 9pm the next
                // is fine.
                return .after(lastBackupDate.addingTimeInterval(.day - (.hour * 4)))
            }
        }
    }
}
