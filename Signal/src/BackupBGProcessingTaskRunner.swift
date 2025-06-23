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
        try await exportJob().exportAndUploadBackup(progress: nil)
    }

    public func shouldLaunchBGProcessingTask() -> Bool {
        guard FeatureFlags.Backups.remoteExportAlpha else {
            return false
        }

        return db.read { tx in
            switch backupSettingsStore.backupPlan(tx: tx) {
            case .disabled:
                return false
            case .free, .paid, .paidExpiringSoon:
                break
            }
            let lastBackupDate = (backupSettingsStore.lastBackupDate(tx: tx) ?? Date(millisecondsSince1970: 0))
            let nextBackupTimestamp: UInt64
            switch backupSettingsStore.backupFrequency(tx: tx) {
            case .daily:
                nextBackupTimestamp = lastBackupDate.ows_millisecondsSince1970 + .dayInMs
            case .weekly:
                nextBackupTimestamp = lastBackupDate.ows_millisecondsSince1970 + .weekInMs
            case .monthly:
                if
                    let oneMonthLater = Calendar.current.date(
                        byAdding: .month,
                        value: 1,
                        to: lastBackupDate
                    )
                {
                    nextBackupTimestamp = oneMonthLater.ows_millisecondsSince1970
                } else {
                    owsFailDebug("Unable to add month to date")
                    nextBackupTimestamp = lastBackupDate.ows_millisecondsSince1970 + (.weekInMs * 4)
                }
            case .manually:
                return false
            }

            return nextBackupTimestamp <= Date().ows_millisecondsSince1970
        }
    }
}
