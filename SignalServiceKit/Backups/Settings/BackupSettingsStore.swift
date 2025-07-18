//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupPlan: RawRepresentable {
    case disabled
    case disabling
    case free
    case paid(optimizeLocalStorage: Bool)
    case paidExpiringSoon(optimizeLocalStorage: Bool)
    case paidAsTester(optimizeLocalStorage: Bool)

    // MARK: RawRepresentable

    public init?(rawValue: Int) {
        switch rawValue {
        case 6: self = .disabled
        case 7: self = .disabling
        case 1: self = .free
        case 2: self = .paid(optimizeLocalStorage: false)
        case 3: self = .paid(optimizeLocalStorage: true)
        case 4: self = .paidExpiringSoon(optimizeLocalStorage: false)
        case 5: self = .paidExpiringSoon(optimizeLocalStorage: true)
        case 8: self = .paidAsTester(optimizeLocalStorage: false)
        case 9: self = .paidAsTester(optimizeLocalStorage: true)
        default: return nil
        }
    }

    public var rawValue: Int {
        switch self {
        case .disabled: return 6
        case .disabling: return 7
        case .free: return 1
        case .paid(let optimizeLocalStorage): return optimizeLocalStorage ? 3 : 2
        case .paidExpiringSoon(let optimizeLocalStorage): return optimizeLocalStorage ? 5 : 4
        case .paidAsTester(let optimizeLocalStorage): return optimizeLocalStorage ? 9 : 8
        }
    }
}

// MARK: -

extension NSNotification.Name {
    public static let backupAttachmentDownloadQueueSuspensionStatusDidChange = Notification.Name("BackupSettingsStore.backupAttachmentDownloadQueueSuspensionStatusDidChange")
    public static let shouldAllowBackupDownloadsOnCellularChanged = Notification.Name("BackupSettingsStore.shouldAllowBackupDownloadsOnCellularChanged")
    public static let shouldAllowBackupUploadsOnCellularChanged = Notification.Name("BackupSettingsStore.shouldAllowBackupUploadsOnCellularChanged")
}

// MARK: -

public struct BackupSettingsStore {

    private enum Keys {
        static let haveEverBeenEnabled = "haveEverBeenEnabledKey2"
        static let plan = "planKey2"
        static let firstBackupDate = "firstBackupDate"
        static let lastBackupDate = "lastBackupDate"
        static let lastBackupSizeBytes = "lastBackupSizeBytes"
        static let isBackupAttachmentDownloadQueueSuspended = "isBackupAttachmentDownloadQueueSuspended"
        static let shouldAllowBackupDownloadsOnCellular = "shouldAllowBackupDownloadsOnCellular"
        static let shouldAllowBackupUploadsOnCellular = "shouldAllowBackupUploadsOnCellular"
        static let shouldOptimizeLocalStorage = "shouldOptimizeLocalStorage"
        static let lastBackupKeyReminderDate = "lastBackupKeyReminderDate"
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

    /// Set the current `BackupPlan`, without side-effects.
    ///
    /// - Important
    /// Callers should prefer the API on `BackupPlanManager`, or have considered
    /// the consequences of avoiding the side-effects of setting `BackupPlan`.
    public func setBackupPlan(_ newBackupPlan: BackupPlan, tx: DBWriteTransaction) {
        kvStore.setBool(true, key: Keys.haveEverBeenEnabled, transaction: tx)
        kvStore.setInt(newBackupPlan.rawValue, key: Keys.plan, transaction: tx)
    }

    // MARK: -

    public func firstBackupDate(tx: DBReadTransaction) -> Date? {
        return kvStore.getDate(Keys.firstBackupDate, transaction: tx)
    }

    private func setFirstBackupDate(_ firstBackupDate: Date?, tx: DBWriteTransaction) {
        if let firstBackupDate {
            kvStore.setDate(firstBackupDate, key: Keys.firstBackupDate, transaction: tx)
        } else {
            kvStore.removeValue(forKey: Keys.firstBackupDate, transaction: tx)
        }
    }

    // MARK: -

    public func lastBackupDate(tx: DBReadTransaction) -> Date? {
        return kvStore.getDate(Keys.lastBackupDate, transaction: tx)
    }

    public func setLastBackupDate(_ lastBackupDate: Date, tx: DBWriteTransaction) {
        kvStore.setDate(lastBackupDate, key: Keys.lastBackupDate, transaction: tx)

        if firstBackupDate(tx: tx) == nil {
            setFirstBackupDate(lastBackupDate, tx: tx)
        }
    }

    public func resetLastBackupDate(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.lastBackupDate, transaction: tx)
        setFirstBackupDate(nil, tx: tx)
    }

    // MARK: -

    public func lastBackupSizeBytes(tx: DBReadTransaction) -> UInt64? {
        return kvStore.getUInt64(Keys.lastBackupSizeBytes, transaction: tx)
    }

    public func setLastBackupSizeBytes(_ lastBackupSizeBytes: UInt64, tx: DBWriteTransaction) {
        kvStore.setUInt64(lastBackupSizeBytes, key: Keys.lastBackupSizeBytes, transaction: tx)
    }

    public func resetLastBackupSizeBytes(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.lastBackupSizeBytes, transaction: tx)
    }

    // MARK: -

    public func isBackupAttachmentDownloadQueueSuspended(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.isBackupAttachmentDownloadQueueSuspended, defaultValue: false, transaction: tx)
    }

    /// We "suspend" the download queue to prevent downloads from automatically
    /// beginning (and consuming device storage) without user opt-in, such as
    /// when `BackupPlan` changes in the background. We un-suspend when the user
    /// takes explicit action such that we know downloads should happen.
    public func setIsBackupDownloadQueueSuspended(_ isSuspended: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(isSuspended, key: Keys.isBackupAttachmentDownloadQueueSuspended, transaction: tx)

        // The "allow cellular downloads" setting isn't exposed as a toggle, and
        // instead lasts for the duration of the "current download" once set.
        //
        // If the user has taken action on the download queue, treat that as the
        // "current download" rotating, and consequently forget any past
        // cellular-download state.
        _setShouldAllowBackupDownloadsOnCellular(nil, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .backupAttachmentDownloadQueueSuspensionStatusDidChange, object: nil)
        }
    }

    // MARK: -

    public func shouldAllowBackupDownloadsOnCellular(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.shouldAllowBackupDownloadsOnCellular, defaultValue: false, transaction: tx)
    }

    public func setShouldAllowBackupDownloadsOnCellular(tx: DBWriteTransaction) {
        _setShouldAllowBackupDownloadsOnCellular(true, tx: tx)
    }

    private func _setShouldAllowBackupDownloadsOnCellular(_ shouldAllowBackupDownloadsOnCellular: Bool?, tx: DBWriteTransaction) {
        if let shouldAllowBackupDownloadsOnCellular {
            kvStore.setBool(shouldAllowBackupDownloadsOnCellular, key: Keys.shouldAllowBackupDownloadsOnCellular, transaction: tx)
        } else {
            kvStore.removeValue(forKey: Keys.shouldAllowBackupDownloadsOnCellular, transaction: tx)
        }

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .shouldAllowBackupDownloadsOnCellularChanged, object: nil)
        }
    }

    // MARK: -

    public func shouldAllowBackupUploadsOnCellular(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.shouldAllowBackupUploadsOnCellular, defaultValue: false, transaction: tx)
    }

    public func setShouldAllowBackupUploadsOnCellular(_ shouldAllowBackupUploadsOnCellular: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(shouldAllowBackupUploadsOnCellular, key: Keys.shouldAllowBackupUploadsOnCellular, transaction: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .shouldAllowBackupUploadsOnCellularChanged, object: nil)
        }
    }

    public func resetShouldAllowBackupUploadsOnCellular(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.shouldAllowBackupUploadsOnCellular, transaction: tx)
    }

    // MARK: -

    public func lastBackupKeyReminderDate(tx: DBReadTransaction) -> Date? {
        return kvStore.getDate(Keys.lastBackupKeyReminderDate, transaction: tx)
    }

    public func setLastBackupKeyReminderDate(_ lastBackupKeyReminderDate: Date, tx: DBWriteTransaction) {
        kvStore.setDate(lastBackupKeyReminderDate, key: Keys.lastBackupKeyReminderDate, transaction: tx)
    }
}
