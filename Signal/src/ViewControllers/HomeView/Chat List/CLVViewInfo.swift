//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// A snapshot of the current chat list view state used for rendering table view rows.
struct CLVViewInfo: Equatable {
    let chatListMode: ChatListMode
    let archiveCount: UInt
    let inboxCount: UInt
    let inboxFilter: InboxFilter
    let isMultiselectActive: Bool
    let hasVisibleReminders: Bool
    let shouldBackupDownloadProgressViewBeVisible: Bool
    let lastSelectedThreadId: String?
    let requiredVisibleThreadIds: Set<String>

    var hasArchivedThreadsRow: Bool {
        chatListMode == .inbox && !isMultiselectActive && inboxFilter == .none && archiveCount > 0
    }

    static var empty: CLVViewInfo {
        CLVViewInfo(
            chatListMode: .inbox,
            archiveCount: 0,
            inboxCount: 0,
            inboxFilter: .none,
            isMultiselectActive: false,
            hasVisibleReminders: false,
            shouldBackupDownloadProgressViewBeVisible: false,
            lastSelectedThreadId: nil,
            requiredVisibleThreadIds: [],
        )
    }

    static func build(
        chatListMode: ChatListMode,
        inboxFilter: InboxFilter,
        isMultiselectActive: Bool,
        lastSelectedThreadId: String?,
        hasVisibleReminders: Bool,
        shouldBackupDownloadProgressViewBeVisible: Bool,
        transaction: DBReadTransaction,
    ) -> CLVViewInfo {
        do {
            let requiredThreadIds: Set<String> = if inboxFilter != .none, let lastSelectedThreadId {
                [lastSelectedThreadId]
            } else {
                []
            }
            let threadFinder = ThreadFinder()
            let archiveCount = try threadFinder.visibleThreadCount(isArchived: true, transaction: transaction)
            let inboxCount = try threadFinder.visibleThreadCount(isArchived: false, transaction: transaction)
            return CLVViewInfo(
                chatListMode: chatListMode,
                archiveCount: archiveCount,
                inboxCount: inboxCount,
                inboxFilter: inboxFilter,
                isMultiselectActive: isMultiselectActive,
                hasVisibleReminders: hasVisibleReminders,
                shouldBackupDownloadProgressViewBeVisible: shouldBackupDownloadProgressViewBeVisible,
                lastSelectedThreadId: lastSelectedThreadId,
                requiredVisibleThreadIds: requiredThreadIds,
            )
        } catch {
            owsFailDebug("Error: \(error)")
            return .empty
        }
    }
}
