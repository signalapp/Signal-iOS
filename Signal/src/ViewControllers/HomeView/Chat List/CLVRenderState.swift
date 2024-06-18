//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct CLVRenderState {
    let viewInfo: CLVViewInfo
    let pinnedThreads: [TSThread]
    let unpinnedThreads: [TSThread]

    var archiveCount: UInt {
        viewInfo.archiveCount
    }

    var inboxCount: UInt {
        viewInfo.inboxCount
    }

    var visibleThreadCount: Int {
        pinnedThreads.count + unpinnedThreads.count
    }

    var hasArchivedThreadsRow: Bool {
        viewInfo.hasArchivedThreadsRow
    }

    var hasVisibleReminders: Bool {
        viewInfo.hasVisibleReminders
    }

    static var empty: CLVRenderState {
        CLVRenderState(viewInfo: .empty, pinnedThreads: [], unpinnedThreads: [])
    }

    var hasPinnedAndUnpinnedThreads: Bool {
        !pinnedThreads.isEmpty && !unpinnedThreads.isEmpty
    }

    func thread(forIndexPath indexPath: IndexPath) -> TSThread? {
        let section = ChatListSection(rawValue: indexPath.section)!

        switch section {
        case .pinned:
            return pinnedThreads[indexPath.row]
        case .unpinned:
            return unpinnedThreads[indexPath.row]
        default:
            return nil
        }
    }

    func indexPath(forUniqueId uniqueId: String) -> IndexPath? {
        if let index = (unpinnedThreads.firstIndex { $0.uniqueId == uniqueId}) {
            return IndexPath(item: index, section: ChatListSection.unpinned.rawValue)
        } else if let index = pinnedThreads.firstIndex(where: { $0.uniqueId == uniqueId }) {
            return IndexPath(item: index, section: ChatListSection.pinned.rawValue)
        } else {
            return nil
        }
    }

    func indexPath(afterThread thread: TSThread?) -> IndexPath? {
        let isPinnedThread: Bool
        if let thread = thread, pinnedThreads.contains(where: { $0.uniqueId == thread.uniqueId }) {
            isPinnedThread = true
        } else {
            isPinnedThread = false
        }

        let section: ChatListSection = isPinnedThread ? .pinned : .unpinned
        let threadsInSection = isPinnedThread ? pinnedThreads : unpinnedThreads

        guard !threadsInSection.isEmpty else { return nil }

        let firstIndexPath = IndexPath(item: 0, section: section.rawValue)

        guard let thread = thread else { return firstIndexPath }
        guard let index = threadsInSection.firstIndex(where: { $0.uniqueId == thread.uniqueId}) else {
            return firstIndexPath
        }

        if index < (threadsInSection.count - 1) {
            return IndexPath(item: index + 1, section: section.rawValue)
        } else {
            return nil
        }
    }

    func indexPath(beforeThread thread: TSThread?) -> IndexPath? {
        let isPinnedThread: Bool
        if let thread = thread, pinnedThreads.contains(where: { $0.uniqueId == thread.uniqueId }) {
            isPinnedThread = true
        } else {
            isPinnedThread = false
        }

        let section: ChatListSection = isPinnedThread ? .pinned : .unpinned
        let threadsInSection = isPinnedThread ? pinnedThreads : unpinnedThreads

        guard !threadsInSection.isEmpty else { return nil }

        let lastIndexPath = IndexPath(item: threadsInSection.count - 1, section: section.rawValue)

        guard let thread = thread else { return lastIndexPath }
        guard let index = threadsInSection.firstIndex(where: { $0.uniqueId == thread.uniqueId}) else {
            return lastIndexPath
        }

        if index > 0 {
            return IndexPath(item: index - 1, section: section.rawValue)
        } else {
            return nil
        }
    }
}

// MARK: -

struct CLVViewInfo: Equatable {
    let chatListMode: ChatListMode
    let archiveCount: UInt
    let inboxCount: UInt
    let inboxFilter: InboxFilter?
    let hasArchivedThreadsRow: Bool
    let hasVisibleReminders: Bool
    let lastSelectedThreadId: String?
    let requiredVisibleThreadIds: Set<String>

    static var empty: CLVViewInfo {
        CLVViewInfo(
            chatListMode: .inbox,
            archiveCount: 0,
            inboxCount: 0,
            inboxFilter: nil,
            hasArchivedThreadsRow: false,
            hasVisibleReminders: false,
            lastSelectedThreadId: nil,
            requiredVisibleThreadIds: []
        )
    }

    static func build(
        chatListMode: ChatListMode,
        inboxFilter: InboxFilter?,
        lastSelectedThreadId: String?,
        hasVisibleReminders: Bool,
        transaction: SDSAnyReadTransaction
    ) -> CLVViewInfo {
        do {
            let requiredThreadIds: Set<String> = if inboxFilter != nil, let lastSelectedThreadId {
                [lastSelectedThreadId]
            } else {
                []
            }
            let threadFinder = ThreadFinder()
            let archiveCount = try threadFinder.visibleThreadCount(isArchived: true, transaction: transaction)
            let inboxCount = try threadFinder.visibleThreadCount(isArchived: false, transaction: transaction)
            let hasArchivedThreadsRow = (chatListMode == .inbox && archiveCount > 0)
            return CLVViewInfo(
                chatListMode: chatListMode,
                archiveCount: archiveCount,
                inboxCount: inboxCount,
                inboxFilter: inboxFilter,
                hasArchivedThreadsRow: hasArchivedThreadsRow,
                hasVisibleReminders: hasVisibleReminders,
                lastSelectedThreadId: lastSelectedThreadId,
                requiredVisibleThreadIds: requiredThreadIds
            )
        } catch {
            owsFailDebug("Error: \(error)")
            return .empty
        }
    }
}
