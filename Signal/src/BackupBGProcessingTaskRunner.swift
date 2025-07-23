//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class BackupBGProcessingTaskRunner: BGProcessingTaskRunner {

    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let exportJob: () -> any BackupExportJob

    init(
        backupSettingsStore: BackupSettingsStore,
        db: SDSDatabaseStorage,
        exportJob: @escaping () -> any BackupExportJob
    ) {
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.exportJob = exportJob
    }

    // MARK: - BGProcessingTaskRunner

    public static let taskIdentifier = "BackupBGProcessingTaskRunner"

    public static let requiresNetworkConnectivity = true

    func run() async throws {
        try await exportJob().exportAndUploadBackup(onProgressUpdate: nil)
    }

    public func startCondition() -> BGProcessingTaskStartCondition {
        guard FeatureFlags.Backups.supported else {
            return .never
        }

        return db.read { (tx) -> BGProcessingTaskStartCondition in
            switch backupSettingsStore.backupPlan(tx: tx) {
            case .disabled, .disabling:
                return .never
            case .free, .paid, .paidExpiringSoon, .paidAsTester:
                break
            }
            let lastBackupDate = (backupSettingsStore.lastBackupDate(tx: tx) ?? Date(millisecondsSince1970: 0))

            // Add in a little buffer so that we can roughly run at any time of
            // day, every day, but aren't always creeping forward with a strict
            // minimum. For example, if we run at 10pm one day then 9pm the next
            // is fine.
            return .after(lastBackupDate.addingTimeInterval(.day - (.hour * 4)))
        }
    }
}
