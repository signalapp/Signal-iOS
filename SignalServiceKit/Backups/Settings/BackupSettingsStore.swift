//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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
    public static let lastBackupDetailsDidChange = Notification.Name("BackupSettingsStore.lastBackupDetailsDidChange")
    public static let backupAttachmentDownloadQueueSuspensionStatusDidChange = Notification.Name("BackupSettingsStore.backupAttachmentDownloadQueueSuspensionStatusDidChange")
    public static let backupAttachmentUploadQueueSuspensionStatusDidChange = Notification.Name("BackupSettingsStore.backupAttachmentUploadQueueSuspensionStatusDidChange")
    public static let hasConsumedMediaTierCapacityStatusDidChange = Notification.Name("BackupSettingsStore.hasConsumedMediaTierCapacityStatusDidChange")
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
        static let lastBackupFileSizeBytes = "lastBackupFileSizeBytes"
        static let lastBackupSizeBytes = "lastBackupSizeBytes"
        static let isBackupAttachmentDownloadQueueSuspended = "isBackupAttachmentDownloadQueueSuspended"
        static let isBackupAttachmentUploadQueueSuspended = "isBackupAttachmentUploadQueueSuspended"
        static let hasConsumedMediaTierCapacity = "hasConsumedMediaTierCapacity"
        static let shouldAllowBackupDownloadsOnCellular = "shouldAllowBackupDownloadsOnCellular"
        static let shouldAllowBackupUploadsOnCellular = "shouldAllowBackupUploadsOnCellular"
        static let shouldOptimizeLocalStorage = "shouldOptimizeLocalStorage"
        static let lastRecoveryKeyReminderDate = "lastBackupKeyReminderDate"
        static let haveSetBackupID = "haveSetBackupID"
        static let lastBackupEnabledDetails = "lastBackupEnabledDetails"

        static let backgroundBackupErrorCount = "backgroundBackupErrorCount"
        static let interactiveBackupErrorCount = "interactiveBackupErrorCount"
    }

    private let kvStore: KeyValueStore
    private let errorStateStore: KeyValueStore
    private let refreshBackupStore: CronStore

    public init() {
        kvStore = KeyValueStore(collection: "BackupSettingsStore")
        errorStateStore = KeyValueStore(collection: "BackupSettingsErrorStateStore")
        refreshBackupStore = CronStore(uniqueKey: .refreshBackup)
    }

    // MARK: -

    /// Whether Backups have ever been enabled, regardless of whether they are
    /// enabled currently.
    public func haveBackupsEverBeenEnabled(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.haveEverBeenEnabled, defaultValue: false, transaction: tx)
    }

    /// Wipes whether Backups have ever been enabled.
    ///
    /// **Not intended for production use.**
    public func wipeHaveBackupsEverBeenEnabled(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.haveEverBeenEnabled, transaction: tx)
    }

    // MARK: -

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

    public struct LastBackupEnabledDetails: Codable {
        public let enabledTime: Date
        public let notificationDelay: TimeInterval

        public var shouldRemindUserAfter: Date { enabledTime.addingTimeInterval(notificationDelay) }
    }

    public func lastBackupEnabledDetails(
        tx: DBReadTransaction,
    ) -> LastBackupEnabledDetails? {
        do {
            return try kvStore.getCodableValue(
                forKey: Keys.lastBackupEnabledDetails,
                transaction: tx,
            )
        } catch {
            owsFailDebug("Failed to get LastBackupEnabledDetails \(error)")
            return nil
        }
    }

    public func setLastBackupEnabledDetails(
        backupsEnabledTime: Date,
        notificationDelay: TimeInterval,
        tx: DBWriteTransaction,
    ) {
        do {
            try kvStore.setCodable(
                LastBackupEnabledDetails(
                    enabledTime: backupsEnabledTime,
                    notificationDelay: notificationDelay,
                ),
                key: Keys.lastBackupEnabledDetails,
                transaction: tx,
            )
        } catch {
            owsFailDebug("Failed to set LastBackupEnabledDetails")
        }
    }

    public func clearLastBackupEnabledDetails(tx: DBWriteTransaction) {
        kvStore.removeValue(
            forKey: Keys.lastBackupEnabledDetails,
            transaction: tx,
        )
    }

    // MARK: -

    public struct LastBackupDetails {
        /// The date of our last backup.
        public let date: Date
        /// The size of our most recent Backup proto file.
        public let backupFileSizeBytes: UInt64
        /// The total size of our most recent backup, including the Backup proto
        /// file and all backed-up media. Only set if we're on the paid tier.
        public let backupTotalSizeBytes: UInt64?

        public init(date: Date, backupFileSizeBytes: UInt64, backupTotalSizeBytes: UInt64?) {
            self.date = date
            self.backupFileSizeBytes = backupFileSizeBytes
            self.backupTotalSizeBytes = backupTotalSizeBytes
        }
    }

    public func lastBackupDetails(tx: DBReadTransaction) -> LastBackupDetails? {
        guard
            let lastBackupDate = kvStore.getDate(Keys.lastBackupDate, transaction: tx),
            let backupFileSizeBytes = kvStore.getUInt64(Keys.lastBackupFileSizeBytes, transaction: tx)
        else {
            return nil
        }

        let backupTotalSizeBytes: UInt64?
        switch backupPlan(tx: tx) {
        case .disabled, .disabling, .free:
            backupTotalSizeBytes = nil
        case .paid, .paidExpiringSoon, .paidAsTester:
            backupTotalSizeBytes = kvStore.getUInt64(Keys.lastBackupSizeBytes, transaction: tx)
        }

        return LastBackupDetails(
            date: lastBackupDate,
            backupFileSizeBytes: backupFileSizeBytes,
            backupTotalSizeBytes: backupTotalSizeBytes,
        )
    }

    public func setLastBackupDetails(
        date: Date,
        backupFileSizeBytes: UInt64,
        backupMediaSizeBytes: UInt64,
        tx: DBWriteTransaction,
    ) {
        kvStore.setDate(date, key: Keys.lastBackupDate, transaction: tx)
        kvStore.setUInt64(backupFileSizeBytes, key: Keys.lastBackupFileSizeBytes, transaction: tx)
        kvStore.setUInt64(backupFileSizeBytes + backupMediaSizeBytes, key: Keys.lastBackupSizeBytes, transaction: tx)

        if firstBackupDate(tx: tx) == nil {
            setFirstBackupDate(date, tx: tx)
        }

        refreshBackupStore.setMostRecentDate(Date(), jitter: 0, tx: tx)

        // We did a backup, so clear all error state.
        errorStateStore.removeAll(transaction: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .lastBackupDetailsDidChange, object: nil)
        }
    }

    public func resetLastBackupDetails(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.lastBackupDate, transaction: tx)
        kvStore.removeValue(forKey: Keys.lastBackupFileSizeBytes, transaction: tx)
        kvStore.removeValue(forKey: Keys.lastBackupSizeBytes, transaction: tx)
        refreshBackupStore.setMostRecentDate(.distantPast, jitter: 0, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .lastBackupDetailsDidChange, object: nil)
        }
    }

    // MARK: -

    public func firstBackupDate(tx: DBReadTransaction) -> Date? {
        return kvStore.getDate(Keys.firstBackupDate, transaction: tx)
    }

    private func setFirstBackupDate(_ firstBackupDate: Date, tx: DBWriteTransaction) {
        kvStore.setDate(firstBackupDate, key: Keys.firstBackupDate, transaction: tx)
    }

    // MARK: -

    public enum ErrorBadgeTarget {
        case chatListAvatar
        case chatListMenuItem

        fileprivate var key: String {
            switch self {
            case .chatListAvatar: "avatar_muted"
            case .chatListMenuItem: "menu_muted"
            }
        }
    }

    public func getErrorBadgeMuted(target: ErrorBadgeTarget, tx: DBReadTransaction) -> Bool {
        errorStateStore.getBool(target.key, defaultValue: false, transaction: tx)
    }

    public func setErrorBadgeMuted(target: ErrorBadgeTarget, tx: DBWriteTransaction) {
        errorStateStore.setBool(true, key: target.key, transaction: tx)
    }

    // MARK: -

    public func getInteractiveBackupErrorCount(tx: DBReadTransaction) -> Int {
        errorStateStore.getInt(Keys.interactiveBackupErrorCount, defaultValue: 0, transaction: tx)
    }

    public func incrementInteractiveBackupErrorCount(tx: DBWriteTransaction) {
        let nextCount = getInteractiveBackupErrorCount(tx: tx) + 1
        errorStateStore.setInt(nextCount, key: Keys.interactiveBackupErrorCount, transaction: tx)
    }

    public func getBackgroundBackupErrorCount(tx: DBReadTransaction) -> Int {
        errorStateStore.getInt(Keys.backgroundBackupErrorCount, defaultValue: 0, transaction: tx)
    }

    public func incrementBackgroundBackupErrorCount(tx: DBWriteTransaction) {
        let nextCount = getBackgroundBackupErrorCount(tx: tx) + 1
        errorStateStore.setInt(nextCount, key: Keys.backgroundBackupErrorCount, transaction: tx)
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

        // Since the user has taken action to suspend the download queue, reset
        // "temporary" cellular downloads state (in case we had set it).
        setShouldAllowBackupDownloadsOnCellular(false, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .backupAttachmentDownloadQueueSuspensionStatusDidChange, object: nil)
        }
    }

    // MARK: -

    public func hasConsumedMediaTierCapacity(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.hasConsumedMediaTierCapacity, defaultValue: false, transaction: tx)
    }

    /// When we get the relevant error response from the server on an attempt to copy a transit tier
    /// upload to the media tier, we set this to true, so that we stop attempting uploads until we have
    /// the chance to perform cleanup.
    /// This only gets set to false again once we (attempt) clean up, which may free up enough space to
    /// resume uploading.
    public func setHasConsumedMediaTierCapacity(_ hasConsumedMediaTierCapacity: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(hasConsumedMediaTierCapacity, key: Keys.hasConsumedMediaTierCapacity, transaction: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .hasConsumedMediaTierCapacityStatusDidChange, object: nil)
        }
    }

    // MARK: -

    public func isBackupAttachmentUploadQueueSuspended(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.isBackupAttachmentUploadQueueSuspended, defaultValue: false, transaction: tx)
    }

    public func setIsBackupUploadQueueSuspended(_ isSuspended: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(isSuspended, key: Keys.isBackupAttachmentUploadQueueSuspended, transaction: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .backupAttachmentUploadQueueSuspensionStatusDidChange, object: nil)
        }
    }

    // MARK: -

    /// Whether downloads of Backup media are allowed to use cellular, rather
    /// than being restricted to WiFi. Defaults to `false`.
    ///
    /// - Note
    /// This setting is not exposed as a toggle, and is instead a "temporary
    /// override" that's reset automatically on various triggers.
    public func shouldAllowBackupDownloadsOnCellular(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.shouldAllowBackupDownloadsOnCellular, transaction: tx) ?? false
    }

    public func setShouldAllowBackupDownloadsOnCellular(_ shouldAllowBackupDownloadsOnCellular: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(shouldAllowBackupDownloadsOnCellular, key: Keys.shouldAllowBackupDownloadsOnCellular, transaction: tx)

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

    public func lastRecoveryKeyReminderDate(tx: DBReadTransaction) -> Date? {
        return kvStore.getDate(Keys.lastRecoveryKeyReminderDate, transaction: tx)
    }

    public func setLastRecoveryKeyReminderDate(_ lastRecoveryKeyReminderDate: Date, tx: DBWriteTransaction) {
        kvStore.setDate(lastRecoveryKeyReminderDate, key: Keys.lastRecoveryKeyReminderDate, transaction: tx)
    }

    // MARK: -

    public func haveSetBackupID(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.haveSetBackupID, defaultValue: false, transaction: tx)
    }

    public func setHaveSetBackupID(haveSetBackupID: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(haveSetBackupID, key: Keys.haveSetBackupID, transaction: tx)
    }
}

private extension BackupPlan {
    var asStorageServiceBackupTier: UInt64? {
        switch self {
        case .disabled, .disabling:
            return nil
        case .paid, .paidExpiringSoon, .paidAsTester:
            return UInt64(LibSignalClient.BackupLevel.paid.rawValue)
        case .free:
            return UInt64(LibSignalClient.BackupLevel.free.rawValue)
        }
    }
}
