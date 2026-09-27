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
    let shouldBackupExportProgressViewBeVisible: Bool
    let shouldLocalFileBackupRestoreProgressViewBeVisible: Bool
    let shouldLocalFileBackupExportProgressViewBeVisible: Bool
    let lastSelectedThreadId: String?
    let requiredVisibleThreadIds: Set<String>

    var hasArchivedThreadsRow: Bool {
        chatListMode == .inbox
            && !isMultiselectActive
            && inboxFilter == .unfiltered
            && archiveCount > 0
    }

    static var empty: CLVViewInfo {
        CLVViewInfo(
            chatListMode: .inbox,
            archiveCount: 0,
            inboxCount: 0,
            inboxFilter: .unfiltered,
            isMultiselectActive: false,
            hasVisibleReminders: false,
            shouldBackupDownloadProgressViewBeVisible: false,
            shouldBackupExportProgressViewBeVisible: false,
            shouldLocalFileBackupRestoreProgressViewBeVisible: false,
            shouldLocalFileBackupExportProgressViewBeVisible: false,
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
        shouldBackupExportProgressViewBeVisible: Bool,
        shouldLocalFileBackupRestoreProgressViewBeVisible: Bool,
        shouldLocalFileBackupExportProgressViewBeVisible: Bool,
        transaction: DBReadTransaction,
    ) -> CLVViewInfo {
        let requiredThreadIds: Set<String> = switch (inboxFilter, lastSelectedThreadId) {
        case (.unread, .some(let lastSelectedThreadId)):
            [lastSelectedThreadId]
        case (.unread, nil), (.unfiltered, _):
            []
        }
        let threadFinder = ThreadFinder()
        let archiveCount = threadFinder.visibleThreadCount(isArchived: true, transaction: transaction)
        let inboxCount = threadFinder.visibleThreadCount(isArchived: false, transaction: transaction)
        return CLVViewInfo(
            chatListMode: chatListMode,
            archiveCount: archiveCount,
            inboxCount: inboxCount,
            inboxFilter: inboxFilter,
            isMultiselectActive: isMultiselectActive,
            hasVisibleReminders: hasVisibleReminders,
            shouldBackupDownloadProgressViewBeVisible: shouldBackupDownloadProgressViewBeVisible,
            shouldBackupExportProgressViewBeVisible: shouldBackupExportProgressViewBeVisible,
            shouldLocalFileBackupRestoreProgressViewBeVisible: shouldLocalFileBackupRestoreProgressViewBeVisible,
            shouldLocalFileBackupExportProgressViewBeVisible: shouldLocalFileBackupExportProgressViewBeVisible,
            lastSelectedThreadId: lastSelectedThreadId,
            requiredVisibleThreadIds: requiredThreadIds,
        )
    }
}
