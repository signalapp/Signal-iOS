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
    }

    private let kvStore = NewKeyValueStore(collection: "NotificationPreferences")

    public init() {}

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

    public func setAreReactionNotificationsEnabled(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.areReactionNotificationsEnabled, tx: tx)
    }

    // MARK: - New accounts

    public func shouldNotifyOfNewAccounts(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.shouldNotifyOfNewAccounts, tx: tx) ?? Defaults.shouldNotifyOfNewAccounts
    }

    public func setShouldNotifyOfNewAccounts(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.shouldNotifyOfNewAccounts, tx: tx)
    }

    // MARK: - Badge count

    public func includeMutedThreadsInBadgeCount(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Key.includeMutedThreadsInBadgeCount, tx: tx) ?? Defaults.includeMutedThreadsInBadgeCount
    }

    public func setIncludeMutedThreadsInBadgeCount(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.includeMutedThreadsInBadgeCount, tx: tx)
    }

    public func badgeCountType(tx: DBReadTransaction) -> BadgeCountType {
        let rawValue = kvStore.fetchValue(Int64.self, forKey: Key.badgeCountType, tx: tx)
        return rawValue.flatMap(BadgeCountType.init(rawValue:)) ?? Defaults.badgeCountType
    }

    public func setBadgeCountType(_ value: BadgeCountType, tx: DBWriteTransaction) {
        kvStore.writeValue(value.rawValue, forKey: Key.badgeCountType, tx: tx)
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

    public func defaultNotifyForCallsWhenMuted(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForCallsWhenMuted, tx: tx) ?? Defaults.notifyForCallsWhenMuted
    }

    public func setDefaultNotifyForCallsWhenMuted(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.notifyForCallsWhenMuted, tx: tx)
    }

    public func notifyForCallsWhenMuted(thread: TSThread, tx: DBReadTransaction) -> Bool {
        thread.shouldNotifyForCallsWhenMuted ?? defaultNotifyForCallsWhenMuted(tx: tx)
    }

    /// `nil` inherits the default
    public func setNotifyForCallsWhenMuted(_ value: Bool?, thread: TSThread, tx: DBWriteTransaction) {
        thread.updateWithShouldNotifyForCallsWhenMuted(value, transaction: tx)
        // [Notifications] TODO: Storage Service sync
    }

    // MARK: -

    public func defaultNotifyForMentionsWhenMuted(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForMentionsWhenMuted, tx: tx) ?? Defaults.shouldNotifyForMentionsWhenMuted
    }

    public func setDefaultNotifyForMentionsWhenMuted(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.notifyForMentionsWhenMuted, tx: tx)
    }

    public func notifyForMentionsWhenMuted(thread: TSThread, tx: DBReadTransaction) -> Bool {
        thread.shouldNotifyForMentionsWhenMuted ?? defaultNotifyForMentionsWhenMuted(tx: tx)
    }

    /// `nil` inherits the default
    public func setNotifyForMentionsWhenMuted(_ value: Bool?, thread: TSThread, tx: DBWriteTransaction) {
        thread.updateWithShouldNotifyForMentionsWhenMuted(value, transaction: tx)
        // [Notifications] TODO: Storage Service sync
    }

    // MARK: -

    public func defaultNotifyForRepliesWhenMuted(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.notifyForRepliesWhenMuted, tx: tx) ?? Defaults.notifyForRepliesWhenMuted
    }

    public func setDefaultNotifyForRepliesWhenMuted(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.notifyForRepliesWhenMuted, tx: tx)
    }

    public func notifyForRepliesWhenMuted(thread: TSThread, tx: DBReadTransaction) -> Bool {
        thread.shouldNotifyForRepliesWhenMuted ?? defaultNotifyForRepliesWhenMuted(tx: tx)
    }

    /// `nil` inherits the default
    public func setNotifyForRepliesWhenMuted(_ value: Bool?, thread: TSThread, tx: DBWriteTransaction) {
        thread.updateWithShouldNotifyForRepliesWhenMuted(value, transaction: tx)
        // [Notifications] TODO: Storage Service sync
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
            defaultNotifyForCallsWhenMuted(tx: tx)
        }
        let notifyForMentions = if let thread {
            notifyForMentionsWhenMuted(thread: thread, tx: tx)
        } else {
            defaultNotifyForMentionsWhenMuted(tx: tx)
        }
        let notifyForReplies = if let thread {
            notifyForRepliesWhenMuted(thread: thread, tx: tx)
        } else {
            defaultNotifyForRepliesWhenMuted(tx: tx)
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

    // MARK: - Reset

    public func resetAll(tx: DBWriteTransaction) {
        kvStore.removeAll(tx: tx)
        Sounds.resetThreadNotificationSounds(tx: tx)
        setGlobalNotificationSound(Defaults.globalNotificationSound, tx: tx)
        resetPerChatNotificationPreferences(tx: tx)
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
            {
                threads.append(thread)
            }
            return true
        }

        for thread in threads {
            if thread.shouldNotifyForMentionsWhenMutedLegacy != Defaults.shouldNotifyForMentionsWhenMuted {
                thread.updateWithShouldNotifyForMentionsWhenMutedLegacy(
                    Defaults.shouldNotifyForMentionsWhenMuted,
                    wasLocallyInitiated: true,
                    transaction: tx,
                )
            }
            if thread.shouldNotifyForMentionsWhenMuted != nil {
                setNotifyForMentionsWhenMuted(nil, thread: thread, tx: tx)
            }
            if thread.shouldNotifyForRepliesWhenMuted != nil {
                setNotifyForRepliesWhenMuted(nil, thread: thread, tx: tx)
            }
            if thread.shouldNotifyForCallsWhenMuted != nil {
                setNotifyForCallsWhenMuted(nil, thread: thread, tx: tx)
            }
        }
    }
}
