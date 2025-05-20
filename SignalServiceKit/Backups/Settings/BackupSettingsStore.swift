//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupFrequency: Int, CaseIterable, Identifiable {
    case daily = 1
    case weekly = 2
    case monthly = 3
    case manually = 4

    public var id: Int { rawValue }
}

public enum BackupPlan: Int, CaseIterable {
    case free = 1
    case paid = 2
}

// MARK: -

public struct BackupSettingsStore {

    public static let shouldBackUpOnCellularChangedNotification = Notification.Name("BackupSettingsStore.shouldBackUpOnCellularChangedNotification")

    private enum Keys {
        static let haveEverBeenEnabled = "haveEverBeenEnabled"
        static let plan = "plan"
        static let lastBackupDate = "lastBackupDate"
        static let lastBackupSizeBytes = "lastBackupSizeBytes"
        static let backupFrequency = "backupFrequency"
        static let shouldBackUpOnCellular = "shouldBackUpOnCellular"
        static let shouldOptimizeLocalStorage = "shouldOptimizeLocalStorage"
    }

    private let kvStore: KeyValueStore

    public init() {
        kvStore = KeyValueStore(collection: "BackupSettingsStore")
    }

    // MARK: -

    /// Whether Backups have ever been enabled, regardless of whether they are
    /// enabled currently.
    public func haveBackupsEverBeenEnabled(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.haveEverBeenEnabled, defaultValue: false, transaction: tx)
    }

    /// This device's view of the user's current Backup plan. A return value of
    /// `nil` indicates that the user has Backups disabled.
    ///
    /// - Important
    /// This value represents the user's plan *as this client is aware of it*.
    /// It's possible that this method may return `.paid` even though the user's
    /// paid subscription has expired, in which case they have been de facto
    /// downgraded (as far as the server is concerned) to the `.free` plan.
    public func backupPlan(tx: DBReadTransaction) -> BackupPlan? {
        return kvStore.getInt(Keys.plan, transaction: tx)
            .flatMap { BackupPlan(rawValue: $0) }
    }

    public func setBackupPlan(_ backupPlan: BackupPlan?, tx: DBWriteTransaction) {
        kvStore.setBool(true, key: Keys.haveEverBeenEnabled, transaction: tx)
        if let backupPlan {
            kvStore.setInt(backupPlan.rawValue, key: Keys.plan, transaction: tx)
        } else {
            kvStore.removeValue(forKey: Keys.plan, transaction: tx)
        }
    }

    // MARK: -

    public func lastBackupDate(tx: DBReadTransaction) -> Date? {
        return kvStore.getDate(Keys.lastBackupDate, transaction: tx)
    }

    public func setLastBackupDate(_ lastBackupDate: Date, tx: DBWriteTransaction) {
        kvStore.setDate(lastBackupDate, key: Keys.lastBackupDate, transaction: tx)
    }

    // MARK: -

    public func lastBackupSizeBytes(tx: DBReadTransaction) -> UInt64? {
        return kvStore.getUInt64(Keys.lastBackupSizeBytes, transaction: tx)
    }

    public func setLastBackupSizeBytes(_ lastBackupSizeBytes: UInt64, tx: DBWriteTransaction) {
        kvStore.setUInt64(lastBackupSizeBytes, key: Keys.lastBackupSizeBytes, transaction: tx)
    }

    // MARK: -

    public func backupFrequency(tx: DBReadTransaction) -> BackupFrequency {
        if
            let persisted = kvStore.getInt(Keys.backupFrequency, transaction: tx)
                .flatMap({ BackupFrequency(rawValue: $0) })
        {
            return persisted
        }

        return .daily
    }

    public func setBackupFrequency(_ backupFrequency: BackupFrequency, tx: DBWriteTransaction) {
        kvStore.setInt(backupFrequency.rawValue, key: Keys.backupFrequency, transaction: tx)
    }

    // MARK: -

    public func shouldBackUpOnCellular(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.shouldBackUpOnCellular, defaultValue: false, transaction: tx)
    }

    public func setShouldBackUpOnCellular(_ shouldBackUpOnCellular: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(shouldBackUpOnCellular, key: Keys.shouldBackUpOnCellular, transaction: tx)
        tx.addSyncCompletion {
            NotificationCenter.default.post(name: Self.shouldBackUpOnCellularChangedNotification, object: nil)
        }
    }

    // MARK: -

    public func getShouldOptimizeLocalStorage(tx: DBReadTransaction) -> Bool {
        guard backupPlan(tx: tx) == .paid else {
            // This setting is only for paid subscribers.
            return false
        }
        return kvStore.getBool(Keys.shouldOptimizeLocalStorage, defaultValue: false, transaction: tx)
    }

    public func setShouldOptimizeLocalStorage(_ newValue: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(newValue, key: Keys.shouldOptimizeLocalStorage, transaction: tx)
    }
}
