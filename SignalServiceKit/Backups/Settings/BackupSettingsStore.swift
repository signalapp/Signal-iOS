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

    public init?(rawValue: Int64) {
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

    public var rawValue: Int64 {
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
        static let shouldOverrideShowBackupsOnboarding = "shouldOverrideShowBackupsOnboarding"
        static let shouldGenerateThumbnailsOnNextOffloading = "shouldGenerateThumbnailsOnNextOffloading"
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
        static let lastRecoveryKeyReminderDate = "lastBackupKeyReminderDate"
        static let haveSetBackupID = "haveSetBackupID"
        static let lastBackupEnabledDetails = "lastBackupEnabledDetails"

        static let backgroundBackupErrorCount = "backgroundBackupErrorCount"
        static let interactiveBackupErrorCount = "interactiveBackupErrorCount"
    }

    private let kvStore: NewKeyValueStore
    private let errorStateStore: NewKeyValueStore
    private let refreshBackupStore: CronStore

    public init() {
        kvStore = NewKeyValueStore(collection: "BackupSettingsStore")
        errorStateStore = NewKeyValueStore(collection: "BackupSettingsErrorStateStore")
        refreshBackupStore = CronStore(uniqueKey: .refreshBackup)
    }

    // MARK: - EverBeenEnabled

    /// Whether Backups have ever been enabled, regardless of whether they are
    /// enabled currently.
    public func haveBackupsEverBeenEnabled(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.haveEverBeenEnabled, tx: tx) ?? false
    }

    // MARK: - Internal: Show Backups Onboarding

    /// Whether to force showing Backups onboarding.
    ///
    /// Not intended for production use.
    public func shouldOverrideShowBackupsOnboarding(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.shouldOverrideShowBackupsOnboarding, tx: tx) ?? false
    }

    /// Set an override to show Backups onboarding.
    ///
    /// Not intended for production use.
    public func setShouldOverrideShowBackupsOnboarding(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Keys.shouldOverrideShowBackupsOnboarding, tx: tx)
    }

    /// Whether to force generation/upload of new thumbnails during the next offloading of attachment.
    ///
    /// Not intended for production use.
    public func shouldGenerateThumbnailsOnNextOffloading(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.shouldGenerateThumbnailsOnNextOffloading, tx: tx) ?? false
    }

    /// Set an override to force generation/upload of new thumbnails during the next offloading of attachment.
    ///
    /// Not intended for production use.
    public func setShouldGenerateThumbnailsOnNextOffloading(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Keys.shouldGenerateThumbnailsOnNextOffloading, tx: tx)
    }

    // MARK: - BackupPlan

    /// This device's view of the user's current Backup plan. A return value of
    /// `nil` indicates that the user has Backups disabled.
    ///
    /// - Important
    /// This value represents the user's plan *as this client is aware of it*.
    /// It's possible that the value returned by this method is out of date
    /// w.r.t server state; for example, if the user's `.paid` Backup plan has
    /// expired, but the client hasn't yet learned that fact.
    public func backupPlan(tx: DBReadTransaction) -> BackupPlan {
        if let rawValue = kvStore.fetchValue(Int64.self, forKey: Keys.plan, tx: tx) {
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
        kvStore.writeValue(true, forKey: Keys.haveEverBeenEnabled, tx: tx)
        kvStore.writeValue(newBackupPlan.rawValue, forKey: Keys.plan, tx: tx)
    }

    // MARK: - LastBackupEnabledDetails

    public struct LastBackupEnabledDetails: Codable {
        public let enabledTime: Date
        public let notificationDelay: TimeInterval

        public var shouldRemindUserAfter: Date { enabledTime.addingTimeInterval(notificationDelay) }
    }

    public func lastBackupEnabledDetails(
        tx: DBReadTransaction,
    ) -> LastBackupEnabledDetails? {
        do {
            return try kvStore.fetchJSONAsValue(
                LastBackupEnabledDetails.self,
                forKey: Keys.lastBackupEnabledDetails,
                tx: tx,
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
        kvStore.writeValueAsJSON(
            LastBackupEnabledDetails(
                enabledTime: backupsEnabledTime,
                notificationDelay: notificationDelay,
            ),
            forKey: Keys.lastBackupEnabledDetails,
            tx: tx,
        )
    }

    public func clearLastBackupEnabledDetails(tx: DBWriteTransaction) {
        kvStore.removeValue(
            forKey: Keys.lastBackupEnabledDetails,
            tx: tx,
        )
    }

    // MARK: - LastBackupDetails

    public struct LastBackupDetails {
        /// The date of our first backup.
        public let firstBackupDate: Date
        /// The date of our last backup.
        public let date: Date
        /// The size of our most recent Backup proto file.
        public let backupFileSizeBytes: UInt64
        /// The total size of our most recent backup, including the Backup proto
        /// file and all backed-up media. Only set if we're on the paid tier.
        public let backupTotalSizeBytes: UInt64?

        public init(
            firstBackupDate: Date,
            date: Date,
            backupFileSizeBytes: UInt64,
            backupTotalSizeBytes: UInt64?,
        ) {
            self.firstBackupDate = firstBackupDate
            self.date = date
            self.backupFileSizeBytes = backupFileSizeBytes
            self.backupTotalSizeBytes = backupTotalSizeBytes
        }
    }

    public func lastBackupDetails(tx: DBReadTransaction) -> LastBackupDetails? {
        guard
            let firstBackupDate = kvStore.fetchValue(Date.self, forKey: Keys.firstBackupDate, tx: tx),
            let lastBackupDate = kvStore.fetchValue(Date.self, forKey: Keys.lastBackupDate, tx: tx),
            let backupFileSizeBytes = kvStore.fetchValue(UInt64.self, forKey: Keys.lastBackupFileSizeBytes, tx: tx)
        else {
            return nil
        }

        let backupTotalSizeBytes: UInt64?
        switch backupPlan(tx: tx) {
        case .disabled, .disabling, .free:
            backupTotalSizeBytes = nil
        case .paid, .paidExpiringSoon, .paidAsTester:
            backupTotalSizeBytes = kvStore.fetchValue(UInt64.self, forKey: Keys.lastBackupSizeBytes, tx: tx)
        }

        return LastBackupDetails(
            firstBackupDate: firstBackupDate,
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
        kvStore.writeValue(date, forKey: Keys.lastBackupDate, tx: tx)
        kvStore.writeValue(backupFileSizeBytes, forKey: Keys.lastBackupFileSizeBytes, tx: tx)
        kvStore.writeValue(backupFileSizeBytes + backupMediaSizeBytes, forKey: Keys.lastBackupSizeBytes, tx: tx)

        if kvStore.fetchValue(Date.self, forKey: Keys.firstBackupDate, tx: tx) == nil {
            kvStore.writeValue(date, forKey: Keys.firstBackupDate, tx: tx)
        }

        refreshBackupStore.setMostRecentDate(Date(), jitter: 0, tx: tx)

        // We did a backup, so clear all error state.
        errorStateStore.removeAll(tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .lastBackupDetailsDidChange, object: nil)
        }
    }

    public func resetLastBackupDetails(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.firstBackupDate, tx: tx)
        kvStore.removeValue(forKey: Keys.lastBackupDate, tx: tx)
        kvStore.removeValue(forKey: Keys.lastBackupFileSizeBytes, tx: tx)
        kvStore.removeValue(forKey: Keys.lastBackupSizeBytes, tx: tx)
        refreshBackupStore.setMostRecentDate(.distantPast, jitter: 0, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .lastBackupDetailsDidChange, object: nil)
        }
    }

    // MARK: - Backup Errors

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
        errorStateStore.fetchValue(Bool.self, forKey: target.key, tx: tx) ?? false
    }

    public func setErrorBadgeMuted(target: ErrorBadgeTarget, tx: DBWriteTransaction) {
        errorStateStore.writeValue(true, forKey: target.key, tx: tx)
    }

    public func getInteractiveBackupErrorCount(tx: DBReadTransaction) -> Int64 {
        errorStateStore.fetchValue(Int64.self, forKey: Keys.interactiveBackupErrorCount, tx: tx) ?? 0
    }

    public func incrementInteractiveBackupErrorCount(tx: DBWriteTransaction) {
        let nextCount = getInteractiveBackupErrorCount(tx: tx) + 1
        errorStateStore.writeValue(nextCount, forKey: Keys.interactiveBackupErrorCount, tx: tx)
    }

    public func getBackgroundBackupErrorCount(tx: DBReadTransaction) -> Int64 {
        errorStateStore.fetchValue(Int64.self, forKey: Keys.backgroundBackupErrorCount, tx: tx) ?? 0
    }

    public func incrementBackgroundBackupErrorCount(tx: DBWriteTransaction) {
        let nextCount = getBackgroundBackupErrorCount(tx: tx) + 1
        errorStateStore.writeValue(nextCount, forKey: Keys.backgroundBackupErrorCount, tx: tx)
    }

    // MARK: - Downloads

    public func isBackupAttachmentDownloadQueueSuspended(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.isBackupAttachmentDownloadQueueSuspended, tx: tx) ?? false
    }

    /// We "suspend" the download queue to prevent downloads from automatically
    /// beginning (and consuming device storage) without user opt-in, such as
    /// when `BackupPlan` changes in the background. We un-suspend when the user
    /// takes explicit action such that we know downloads should happen.
    public func setIsBackupDownloadQueueSuspended(_ isSuspended: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(isSuspended, forKey: Keys.isBackupAttachmentDownloadQueueSuspended, tx: tx)

        // Since the user has taken action to suspend the download queue, reset
        // "temporary" cellular downloads state (in case we had set it).
        setShouldAllowBackupDownloadsOnCellular(false, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .backupAttachmentDownloadQueueSuspensionStatusDidChange, object: nil)
        }
    }

    /// Whether downloads of Backup media are allowed to use cellular, rather
    /// than being restricted to WiFi. Defaults to `false`.
    ///
    /// - Note
    /// This setting is not exposed as a toggle, and is instead a "temporary
    /// override" that's reset automatically on various triggers.
    public func shouldAllowBackupDownloadsOnCellular(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.shouldAllowBackupDownloadsOnCellular, tx: tx) ?? false
    }

    public func setShouldAllowBackupDownloadsOnCellular(_ shouldAllowBackupDownloadsOnCellular: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(shouldAllowBackupDownloadsOnCellular, forKey: Keys.shouldAllowBackupDownloadsOnCellular, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .shouldAllowBackupDownloadsOnCellularChanged, object: nil)
        }
    }

    // MARK: - ConsumedMediaTierCapacity

    public func hasConsumedMediaTierCapacity(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.hasConsumedMediaTierCapacity, tx: tx) ?? false
    }

    /// When we get the relevant error response from the server on an attempt to copy a transit tier
    /// upload to the media tier, we set this to true, so that we stop attempting uploads until we have
    /// the chance to perform cleanup.
    /// This only gets set to false again once we (attempt) clean up, which may free up enough space to
    /// resume uploading.
    public func setHasConsumedMediaTierCapacity(_ hasConsumedMediaTierCapacity: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(hasConsumedMediaTierCapacity, forKey: Keys.hasConsumedMediaTierCapacity, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .hasConsumedMediaTierCapacityStatusDidChange, object: nil)
        }
    }

    // MARK: - Uploads

    public func isBackupAttachmentUploadQueueSuspended(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.isBackupAttachmentUploadQueueSuspended, tx: tx) ?? false
    }

    public func setIsBackupUploadQueueSuspended(_ isSuspended: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(isSuspended, forKey: Keys.isBackupAttachmentUploadQueueSuspended, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .backupAttachmentUploadQueueSuspensionStatusDidChange, object: nil)
        }
    }

    public func shouldAllowBackupUploadsOnCellular(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.shouldAllowBackupUploadsOnCellular, tx: tx) ?? false
    }

    public func setShouldAllowBackupUploadsOnCellular(_ shouldAllowBackupUploadsOnCellular: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(shouldAllowBackupUploadsOnCellular, forKey: Keys.shouldAllowBackupUploadsOnCellular, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .shouldAllowBackupUploadsOnCellularChanged, object: nil)
        }
    }

    public func resetShouldAllowBackupUploadsOnCellular(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.shouldAllowBackupUploadsOnCellular, tx: tx)
    }

    // MARK: - Recovery Key Reminder

    public func lastRecoveryKeyReminderDate(tx: DBReadTransaction) -> Date? {
        return kvStore.fetchValue(Date.self, forKey: Keys.lastRecoveryKeyReminderDate, tx: tx)
    }

    public func setLastRecoveryKeyReminderDate(_ lastRecoveryKeyReminderDate: Date, tx: DBWriteTransaction) {
        kvStore.writeValue(lastRecoveryKeyReminderDate, forKey: Keys.lastRecoveryKeyReminderDate, tx: tx)
    }

    // MARK: - Backup-ID

    public func haveSetBackupID(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.haveSetBackupID, tx: tx) ?? false
    }

    public func setHaveSetBackupID(haveSetBackupID: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(haveSetBackupID, forKey: Keys.haveSetBackupID, tx: tx)
    }
}

// MARK: -

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
