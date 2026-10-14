//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum NotificationType: UInt {
    case noNameNoPreview = 0
    case nameNoPreview = 1
    case namePreview = 2

    public var displayName: String {
        switch self {
        case .namePreview:
            return OWSLocalizedString("NOTIFICATIONS_SENDER_AND_MESSAGE", comment: "")
        case .nameNoPreview:
            return OWSLocalizedString("NOTIFICATIONS_SENDER_ONLY", comment: "")
        case .noNameNoPreview:
            return OWSLocalizedString("NOTIFICATIONS_NONE", comment: "")
        }
    }
}

public enum BadgeCountType: Int64, CaseIterable {
    case unreadMessages = 0
    case unreadChats = 1

    public var title: String {
        switch self {
        case .unreadMessages:
            return OWSLocalizedString(
                "SETTINGS_NOTIFICATION_BADGE_COUNT_UNREAD_MESSAGES",
                comment: "Label for the option that makes the app icon badge show the number of unread messages.",
            )
        case .unreadChats:
            return OWSLocalizedString(
                "SETTINGS_NOTIFICATION_BADGE_COUNT_UNREAD_CHATS",
                comment: "Label for the option that makes the app icon badge show the number of unread chats.",
            )
        }
    }
}

public struct NotificationPreferencesManager {
    public enum Defaults {
        public static let globalNotificationSound = Sound.standard(.note)
        static let previewType: NotificationType = .namePreview
        static let playSoundInForeground = true
        static let messageSentSound = true
        static let shouldNotifyOfNewAccounts = false
        static let includeMutedThreadsInBadgeCount = false
        static let badgeCountType: BadgeCountType = .unreadMessages
        public static let shouldNotifyForMentionsWhenMuted = true
        static let notifyForCallsWhenMuted = false
        static let notifyForRepliesWhenMuted = true
        static let areReactionNotificationsEnabled = true
        static let showUnreadReminders = false
    }

    private enum Key {
        static let previewType = "PreviewType"
        static let playSoundInForeground = "PlaySoundInForeground"
        static let messageSentSound = "MessageSentSound"
        static let shouldNotifyOfNewAccounts = "NotifyOfNewAccounts"
        static let includeMutedThreadsInBadgeCount = "IncludeMutedThreadsInBadgeCount"
        static let badgeCountType = "BadgeCountType"
        static let globalNotificationSound = "GlobalNotificationSound"
        static let areReactionNotificationsEnabled = "ReactionNotificationsEnabled"
        static let notifyForRepliesWhenMuted = "NotifyForRepliesWhenMuted"
        static let notifyForMentionsWhenMuted = "NotifyForMentionsWhenMuted"
        static let notifyForCallsWhenMuted = "NotifyForCallsWhenMuted"
        static let showUnreadReminders = "ShowUnreadReminders"
    }

    private let kvStore = NewKeyValueStore(collection: "NotificationPreferences")
    private let storageServiceManager: any StorageServiceManager

    public init(storageServiceManager: any StorageServiceManager) {
        self.storageServiceManager = storageServiceManager
    }

    // MARK: - Preview type

    public func previewType(tx: DBReadTransaction) -> NotificationType {
        let rawValue = kvStore.fetchValue(UInt64.self, forKey: Key.previewType, tx: tx)
        return rawValue.flatMap({ NotificationType(rawValue: UInt($0)) }) ?? Defaults.previewType
    }

    public func setPreviewType(_ value: NotificationType, tx: DBWriteTransaction) {
        kvStore.writeValue(UInt64(value.rawValue), forKey: Key.previewType, tx: tx)
    }

    // MARK: - Sounds

    public func playSoundInForeground(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.playSoundInForeground, tx: tx) ?? Defaults.playSoundInForeground
    }

    public func setPlaySoundInForeground(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.playSoundInForeground, tx: tx)
    }

    public func isMessageSentSoundEnabled(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.messageSentSound, tx: tx) ?? Defaults.messageSentSound
    }

    public func setIsMessageSentSoundEnabled(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.messageSentSound, tx: tx)
    }

    // MARK: - Reactions

    public func areReactionNotificationsEnabled(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.areReactionNotificationsEnabled, tx: tx) ?? Defaults.areReactionNotificationsEnabled
    }

    public func setAreReactionNotificationsEnabled(
        _ value: Bool,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(value, forKey: Key.areReactionNotificationsEnabled, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    // MARK: - New accounts

    public func shouldNotifyOfNewAccounts(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.shouldNotifyOfNewAccounts, tx: tx) ?? Defaults.shouldNotifyOfNewAccounts
    }

    public func setShouldNotifyOfNewAccounts(
        _ value: Bool,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(value, forKey: Key.shouldNotifyOfNewAccounts, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    // MARK: - Badge count

    public func includeMutedThreadsInBadgeCount(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Key.includeMutedThreadsInBadgeCount, tx: tx) ?? Defaults.includeMutedThreadsInBadgeCount
    }

    public func setIncludeMutedThreadsInBadgeCount(
        _ value: Bool,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(value, forKey: Key.includeMutedThreadsInBadgeCount, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func badgeCountType(tx: DBReadTransaction) -> BadgeCountType {
        let rawValue = kvStore.fetchValue(Int64.self, forKey: Key.badgeCountType, tx: tx)
        return rawValue.flatMap(BadgeCountType.init(rawValue:)) ?? Defaults.badgeCountType
    }

    public func setBadgeCountType(
        _ value: BadgeCountType,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(value.rawValue, forKey: Key.badgeCountType, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    // MARK: - Notification sound

    public func globalNotificationSound(tx: DBReadTransaction) -> Sound {
        let soundId = kvStore.fetchValue(UInt64.self, forKey: Key.globalNotificationSound, tx: tx)
        guard let soundId else { return Defaults.globalNotificationSound }
        return Sounds.soundForId(soundId)
    }

    public func setGlobalNotificationSound(_ sound: Sound, tx: DBWriteTransaction) {
        Logger.info("Setting global notification sound to: \(sound.displayName)")

        guard Sounds.writeFallbackNotificationSoundFile(for: sound) else {
            return
        }

        kvStore.writeValue(sound.id, forKey: Key.globalNotificationSound, tx: tx)
    }

    // MARK: - While muted

    public func globalNotifyForCallsWhenMuted(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForCallsWhenMuted, tx: tx) ?? Defaults.notifyForCallsWhenMuted
    }

    public func setGlobalNotifyForCallsWhenMuted(
        _ value: Bool,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(value, forKey: Key.notifyForCallsWhenMuted, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func notifyForCallsWhenMuted(thread: TSThread, tx: DBReadTransaction) -> Bool {
        thread.shouldNotifyForCallsWhenMuted ?? globalNotifyForCallsWhenMuted(tx: tx)
    }

    /// `nil` inherits the global setting
    public func setNotifyForCallsWhenMuted(
        _ value: Bool?,
        thread: TSThread,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        thread.updateWithShouldNotifyForCallsWhenMuted(value, transaction: tx)
        if updateStorageService {
            thread.recordPendingUpdates(storageServiceManager: storageServiceManager)
        }
    }

    // MARK: -

    public func globalNotifyForMentionsWhenMuted(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForMentionsWhenMuted, tx: tx) ?? Defaults.shouldNotifyForMentionsWhenMuted
    }

    public func setGlobalNotifyForMentionsWhenMuted(
        _ value: Bool,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(value, forKey: Key.notifyForMentionsWhenMuted, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func notifyForMentionsWhenMuted(thread: TSThread, tx: DBReadTransaction) -> Bool {
        thread.shouldNotifyForMentionsWhenMuted ?? globalNotifyForMentionsWhenMuted(tx: tx)
    }

    public func setNotifyForMentionsWhenMutedFromLegacyUI(
        _ value: Bool,
        thread: TSThread,
        tx: DBWriteTransaction,
    ) {
        setNotifyForMentionsWhenMuted(value, thread: thread, updateStorageService: false, tx: tx)
        setNotifyForRepliesWhenMuted(value, thread: thread, updateStorageService: true, tx: tx)
    }

    /// `nil` inherits the global setting
    public func setNotifyForMentionsWhenMuted(
        _ value: Bool?,
        thread: TSThread,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        thread.updateWithShouldNotifyForMentionsWhenMuted(value, transaction: tx)
        if updateStorageService {
            thread.recordPendingUpdates(storageServiceManager: storageServiceManager)
        }
    }

    // MARK: -

    public func globalNotifyForRepliesWhenMuted(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForRepliesWhenMuted, tx: tx) ?? Defaults.notifyForRepliesWhenMuted
    }

    public func setGlobalNotifyForRepliesWhenMuted(
        _ value: Bool,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(value, forKey: Key.notifyForRepliesWhenMuted, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func notifyForRepliesWhenMuted(thread: TSThread, tx: DBReadTransaction) -> Bool {
        thread.shouldNotifyForRepliesWhenMuted ?? globalNotifyForRepliesWhenMuted(tx: tx)
    }

    /// `nil` inherits the global setting
    public func setNotifyForRepliesWhenMuted(
        _ value: Bool?,
        thread: TSThread,
        updateStorageService: Bool = true,
        tx: DBWriteTransaction,
    ) {
        thread.updateWithShouldNotifyForRepliesWhenMuted(value, transaction: tx)
        if updateStorageService {
            thread.recordPendingUpdates(storageServiceManager: storageServiceManager)
        }
    }

    // MARK: - Unread reminders

    public func globalShowUnreadReminders(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.showUnreadReminders, tx: tx) ?? Defaults.showUnreadReminders
    }

    /// Prefer `UnreadReminderManager.setGlobalShowUnreadReminders`, which
    /// also reschedules or cancels pending reminders.
    func setGlobalShowUnreadReminders(
        _ value: Bool,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(value, forKey: Key.showUnreadReminders, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func showUnreadReminders(thread: TSThread, tx: DBReadTransaction) -> Bool {
        thread.shouldNotifyForUnreadRemindersWhenMuted ?? globalShowUnreadReminders(tx: tx)
    }

    /// `nil` inherits the global preference.
    ///
    /// Prefer `UnreadReminderManager.setShowUnreadReminders`, which also
    /// reschedules or cancels the chat's pending reminder.
    func setShowUnreadReminders(
        _ value: Bool?,
        thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        thread.updateWithShouldNotifyForUnreadRemindersWhenMuted(value, transaction: tx)
        if updateStorageService {
            thread.recordPendingUpdates(storageServiceManager: storageServiceManager)
        }
    }

    // MARK: -

    public static let whileMutedCallsTitle = OWSLocalizedString(
        "SETTINGS_WHILE_MUTED_CALLS",
        comment: "Label for the switch controlling whether calls ring or notify in muted chats.",
    )

    public static let whileMutedMentionsTitle = OWSLocalizedString(
        "SETTINGS_WHILE_MUTED_MENTIONS",
        comment: "Label for the switch controlling whether mentions of you notify in muted chats.",
    )

    public static let whileMutedRepliesTitle = OWSLocalizedString(
        "SETTINGS_WHILE_MUTED_REPLIES",
        comment: "Label for the switch controlling whether replies to your messages notify in muted chats.",
    )

    public func whileMutedEnabledString(thread: TSThread? = nil, tx: DBReadTransaction) -> String {
        let notifyForCalls = if let thread {
            notifyForCallsWhenMuted(thread: thread, tx: tx)
        } else {
            globalNotifyForCallsWhenMuted(tx: tx)
        }
        let notifyForMentions = if let thread {
            notifyForMentionsWhenMuted(thread: thread, tx: tx)
        } else {
            globalNotifyForMentionsWhenMuted(tx: tx)
        }
        let notifyForReplies = if let thread {
            notifyForRepliesWhenMuted(thread: thread, tx: tx)
        } else {
            globalNotifyForRepliesWhenMuted(tx: tx)
        }

        var enabledSettingNames = [String]()
        if notifyForCalls {
            enabledSettingNames.append(Self.whileMutedCallsTitle)
        }
        if thread?.isGroupThread ?? true {
            if notifyForMentions {
                enabledSettingNames.append(Self.whileMutedMentionsTitle)
            }
            if notifyForReplies {
                enabledSettingNames.append(Self.whileMutedRepliesTitle)
            }
        }

        if enabledSettingNames.isEmpty {
            return CommonStrings.switchOff
        }

        return enabledSettingNames.formatted(.list(type: .and, width: .narrow))
    }

    // MARK: - Backups

    // The raw value stored, `nil` when unset rather than filling in the default setting

    func storedIncludeMutedThreadsInBadgeCount(tx: DBReadTransaction) -> Bool? {
        kvStore.fetchValue(Bool.self, forKey: Key.includeMutedThreadsInBadgeCount, tx: tx)
    }

    func storedAreReactionNotificationsEnabled(tx: DBReadTransaction) -> Bool? {
        kvStore.fetchValue(Bool.self, forKey: Key.areReactionNotificationsEnabled, tx: tx)
    }

    func storedGlobalNotifyForCallsWhenMuted(tx: DBReadTransaction) -> Bool? {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForCallsWhenMuted, tx: tx)
    }

    func storedGlobalNotifyForMentionsWhenMuted(tx: DBReadTransaction) -> Bool? {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForMentionsWhenMuted, tx: tx)
    }

    func storedGlobalNotifyForRepliesWhenMuted(tx: DBReadTransaction) -> Bool? {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForRepliesWhenMuted, tx: tx)
    }

    func storedGlobalShowUnreadReminders(tx: DBReadTransaction) -> Bool? {
        kvStore.fetchValue(Bool.self, forKey: Key.showUnreadReminders, tx: tx)
    }

    func storedShouldNotifyOfNewAccounts(tx: DBReadTransaction) -> Bool? {
        kvStore.fetchValue(Bool.self, forKey: Key.shouldNotifyOfNewAccounts, tx: tx)
    }

    // MARK: - Reset

    public func resetAll(tx: DBWriteTransaction) {
        kvStore.removeAll(tx: tx)
        Sounds.resetThreadNotificationSounds(tx: tx)
        setGlobalNotificationSound(Defaults.globalNotificationSound, tx: tx)
        resetPerChatNotificationPreferences(tx: tx)
        storageServiceManager.recordPendingLocalAccountUpdates()
    }

    private func resetPerChatNotificationPreferences(tx: DBWriteTransaction) {
        // Save threads to avoid mutation with cursor open
        var threads: [TSThread] = []
        ThreadFinder().enumerateNonStoryThreads(tx: tx) { thread in
            if
                thread.shouldNotifyForMentionsWhenMutedLegacy != Defaults.shouldNotifyForMentionsWhenMuted
                || thread.shouldNotifyForMentionsWhenMuted != nil
                || thread.shouldNotifyForRepliesWhenMuted != nil
                || thread.shouldNotifyForCallsWhenMuted != nil
                || thread.shouldNotifyForUnreadRemindersWhenMuted != nil
            {
                threads.append(thread)
            }
            return true
        }

        for thread in threads {
            if
                thread.shouldNotifyForMentionsWhenMutedLegacy != Defaults.shouldNotifyForMentionsWhenMuted
                || thread.shouldNotifyForMentionsWhenMuted != nil
            {
                setNotifyForMentionsWhenMuted(nil, thread: thread, tx: tx)
            }
            if thread.shouldNotifyForRepliesWhenMuted != nil {
                setNotifyForRepliesWhenMuted(nil, thread: thread, tx: tx)
            }
            if thread.shouldNotifyForCallsWhenMuted != nil {
                setNotifyForCallsWhenMuted(nil, thread: thread, tx: tx)
            }
            if thread.shouldNotifyForUnreadRemindersWhenMuted != nil {
                setShowUnreadReminders(nil, thread: thread, updateStorageService: true, tx: tx)
            }
        }
    }
}
