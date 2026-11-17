//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct BadgeCount {
    public let unreadChatCount: UInt
    public let unreadCallsCount: UInt
    public let unreadCountsByChatFolder: [UUID: UInt]

    public var unreadTotalCount: UInt {
        unreadChatCount + unreadCallsCount
    }
}

public struct BadgeCountFetcher {
    private let chatFolderManager: ChatFolderManager
    private let notificationPreferencesManager: NotificationPreferencesManager
    private let callRecordMissedCallManager: CallRecordMissedCallManager
    private let threadFinder = ThreadFinder()

    init(
        chatFolderManager: ChatFolderManager,
        notificationPreferencesManager: NotificationPreferencesManager,
        callRecordMissedCallManager: CallRecordMissedCallManager,
    ) {
        self.chatFolderManager = chatFolderManager
        self.notificationPreferencesManager = notificationPreferencesManager
        self.callRecordMissedCallManager = callRecordMissedCallManager
    }

    public func fetchBadgeCount(includingChatFolders: Bool, tx: DBReadTransaction) -> BadgeCount {
        let badgeCountType: BadgeCountType
        if BuildFlags.improvedNotifications {
            badgeCountType = notificationPreferencesManager.badgeCountType(tx: tx)
        } else {
            badgeCountType = .unreadMessages
        }

        let chatFolders: [ChatFolder]
        if includingChatFolders, BuildFlags.chatFolders {
            chatFolders = chatFolderManager.fetchFoldersForDisplay(tx: tx)
        } else {
            chatFolders = []
        }

        let unreadThreads = threadFinder.unreadInboxThreads(tx: tx)
        let unreadCounts = Self.unreadCounts(
            unreadThreads: unreadThreads,
            badgeCountType: badgeCountType,
            includeMutedThreads: notificationPreferencesManager.includeMutedThreadsInBadgeCount(tx: tx),
            // If there's only one folder, it's the All Chats folder alone
            chatFolders: chatFolders.count > 1 ? chatFolders : [],
            nowMs: Date.ows_millisecondTimestamp(),
        )
        let unreadMissedCallCount = callRecordMissedCallManager.countUnreadMissedCalls(tx: tx)

        return BadgeCount(
            unreadChatCount: unreadCounts.unreadChatCount,
            unreadCallsCount: unreadMissedCallCount,
            unreadCountsByChatFolder: unreadCounts.unreadCountsByChatFolder,
        )
    }

    static func unreadCounts(
        unreadThreads: [ThreadFinder.UnreadInboxThread],
        badgeCountType: BadgeCountType,
        includeMutedThreads: Bool,
        chatFolders: [ChatFolder],
        nowMs: UInt64,
    ) -> (unreadChatCount: UInt, unreadCountsByChatFolder: [UUID: UInt]) {
        var unreadChatCount: UInt = 0
        var unreadCountsByChatFolder = [UUID: UInt]()
        for unreadThread in unreadThreads {
            let unreadCount: UInt = switch badgeCountType {
            case .unreadMessages:
                max(unreadThread.unreadMessageCount, 1)
            case .unreadChats:
                1
            }
            let isMuted = UInt64(bitPattern: unreadThread.inboxThread.mutedUntilTimestamp) > nowMs
            if includeMutedThreads || !isMuted {
                unreadChatCount += unreadCount
            }

            // Chat folders badge included muted chats
            for folder in chatFolders where folder.contains(unreadThread.inboxThread, nowMs: nowMs) {
                unreadCountsByChatFolder[folder.chatFolderId, default: 0] += unreadCount
            }
        }
        return (unreadChatCount, unreadCountsByChatFolder)
    }
}
