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

public enum BackupPlan: RawRepresentable {
    case disabled
    case free
    case paid(optimizeLocalStorage: Bool)
    case paidExpiringSoon(optimizeLocalStorage: Bool)

    // MARK: RawRepresentable

    public init?(rawValue: Int) {
        switch rawValue {
        case 6: self = .disabled
        case 1: self = .free
        case 2: self = .paid(optimizeLocalStorage: false)
        case 3: self = .paid(optimizeLocalStorage: true)
        case 4: self = .paidExpiringSoon(optimizeLocalStorage: false)
        case 5: self = .paidExpiringSoon(optimizeLocalStorage: true)
        default: return nil
        }
    }

    public var rawValue: Int {
        switch self {
        case .disabled: return 6
        case .free: return 1
        case .paid(let optimizeLocalStorage): return optimizeLocalStorage ? 3 : 2
        case .paidExpiringSoon(let optimizeLocalStorage): return optimizeLocalStorage ? 5 : 4
        }
    }
}

// MARK: -

public struct BackupSettingsStore {

    public enum Notifications {
        public static let backupPlanChanged = Notification.Name("BackupSettingsStore.backupPlanChanged")
        public static let shouldBackUpOnCellularChanged = Notification.Name("BackupSettingsStore.shouldBackUpOnCellularChanged")
    }

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
    /// It's possible that the value returned by this method is out of date
    /// w.r.t server state; for example, if the user's `.paid` Backup plan has
    /// expired, but the client hasn't yet learned that fact.
    public func backupPlan(tx: DBReadTransaction) -> BackupPlan {
        if let rawValue = kvStore.getInt(Keys.plan, transaction: tx) {
            return BackupPlan(rawValue: rawValue) ?? .disabled
        }

        return .disabled
    }

    public func setBackupPlan(_ backupPlan: BackupPlan, tx: DBWriteTransaction) {
        kvStore.setBool(true, key: Keys.haveEverBeenEnabled, transaction: tx)
        kvStore.setInt(backupPlan.rawValue, key: Keys.plan, transaction: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: Notifications.backupPlanChanged, object: nil)
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
            NotificationCenter.default.post(name: Notifications.shouldBackUpOnCellularChanged, object: nil)
        }
    }
}
