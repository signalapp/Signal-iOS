//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BadgeCount {
    public let unreadChatCount: UInt
    public let unreadCallsCount: UInt

    public var unreadTotalCount: UInt {
        unreadChatCount + unreadCallsCount
    }
}

public struct BadgeCountFetcher {
    private let notificationPreferencesManager: NotificationPreferencesManager
    private let callRecordMissedCallManager: CallRecordMissedCallManager

    init(
        notificationPreferencesManager: NotificationPreferencesManager,
        callRecordMissedCallManager: CallRecordMissedCallManager,
    ) {
        self.notificationPreferencesManager = notificationPreferencesManager
        self.callRecordMissedCallManager = callRecordMissedCallManager
    }

    public func fetchBadgeCount(tx: DBReadTransaction) -> BadgeCount {
        let badgeCountType: BadgeCountType
        if BuildFlags.improvedNotifications {
            badgeCountType = notificationPreferencesManager.badgeCountType(tx: tx)
        } else {
            badgeCountType = .unreadMessages
        }

        let unreadChatCount: UInt
        switch badgeCountType {
        case .unreadMessages:
            unreadChatCount = InteractionFinder.unreadCountInAllThreads(transaction: tx)
        case .unreadChats:
            unreadChatCount = InteractionFinder.unreadThreadCountInAllThreads(transaction: tx)
        }
        let unreadMissedCallCount = callRecordMissedCallManager.countUnreadMissedCalls(tx: tx)

        return BadgeCount(
            unreadChatCount: unreadChatCount,
            unreadCallsCount: unreadMissedCallCount,
        )
    }
}
