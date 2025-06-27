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

    public func startCondition() -> BGProcessingTaskStartCondition {
        guard FeatureFlags.Backups.remoteExportAlpha else {
            return .never
        }

        return db.read { (tx) -> BGProcessingTaskStartCondition in
            switch backupSettingsStore.backupPlan(tx: tx) {
            case .disabled:
                return .never
            case .free, .paid, .paidExpiringSoon:
                break
            }
            let lastBackupDate = (backupSettingsStore.lastBackupDate(tx: tx) ?? Date(millisecondsSince1970: 0))
            switch backupSettingsStore.backupFrequency(tx: tx) {
            case .daily:
                // Add in a little buffer, here and for all the others, so that
                // we can roughly run at any time of day every day but aren't
                // always creeping forward with a strict minimum. For example,
                // if we run at 10pm one day 9pm the next is fine; we don't want
                // to run at 10:30 then 11 then 3, then 4 etc with strict min dates.
                return .after(lastBackupDate.addingTimeInterval(.day - (.hour * 4)))
            case .weekly:
                return .after(lastBackupDate.addingTimeInterval(.week - (.hour * 4)))
            case .monthly:
                if
                    let oneMonthLater = Calendar.current.date(
                        byAdding: .month,
                        value: 1,
                        to: lastBackupDate
                    )
                {
                    return .after(oneMonthLater.addingTimeInterval(.hour * -4))
                } else {
                    owsFailDebug("Unable to add month to date")
                    return .after(lastBackupDate.addingTimeInterval(.week * 4 - (.hour * 4)))
                }
            case .manually:
                return .never
            }
        }
    }
}
