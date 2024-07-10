//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct CLVRenderState {
    struct Section {
        var type: ChatListSectionType
        var threads: KeyPath<CLVRenderState, [TSThread]>?
    }

    static var empty: CLVRenderState {
        CLVRenderState(viewInfo: .empty, pinnedThreads: [], unpinnedThreads: [])
    }

    let viewInfo: CLVViewInfo
    let pinnedThreads: [TSThread]
    let unpinnedThreads: [TSThread]
    private(set) var sections: [Section] = []

    init(viewInfo: CLVViewInfo, pinnedThreads: [TSThread], unpinnedThreads: [TSThread]) {
        self.viewInfo = viewInfo
        self.pinnedThreads = pinnedThreads
        self.unpinnedThreads = unpinnedThreads

        for sectionType in ChatListSectionType.allCases {
            switch sectionType {
            case .reminders:
                if hasVisibleReminders {
                    sections.append(Section(type: sectionType))
                }
            case .archiveButton:
                if hasArchivedThreadsRow {
                    sections.append(Section(type: sectionType))
                }
            case .pinned:
                sections.append(Section(type: sectionType, threads: \.pinnedThreads))
            case .unpinned:
                sections.append(Section(type: sectionType, threads: \.unpinnedThreads))
            }
        }
    }

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

    var hasPinnedAndUnpinnedThreads: Bool {
        !pinnedThreads.isEmpty && !unpinnedThreads.isEmpty
    }

    // MARK: UITableViewDataSource

    func sectionIndex(for sectionType: ChatListSectionType) -> Int? {
        sections.firstIndex(where: { $0.type == sectionType })
    }

    func thread(forIndexPath indexPath: IndexPath) -> TSThread? {
        let section = sections[indexPath.section]
        guard let key = section.threads else { return nil }
        return self[keyPath: key][indexPath.row]
    }

    func indexPath(forUniqueId uniqueId: String) -> IndexPath? {
        if let index = pinnedThreads.firstIndex(where: { $0.uniqueId == uniqueId }) {
            let section = sectionIndex(for: .pinned)!
            return IndexPath(item: index, section: section)
        } else if let index = unpinnedThreads.firstIndex(where: { $0.uniqueId == uniqueId }) {
            let section = sectionIndex(for: .unpinned)!
            return IndexPath(item: index, section: section)
        } else {
            return nil
        }
    }

    func indexPath(afterThread thread: TSThread?) -> IndexPath? {
        let section: (index: Int, threads: KeyPath<CLVRenderState, [TSThread]>)

        if let thread = thread, pinnedThreads.contains(where: { $0.uniqueId == thread.uniqueId }) {
            let index = sectionIndex(for: .pinned)!
            section = (index, sections[index].threads!)
        } else {
            let index = sectionIndex(for: .unpinned)!
            section = (index, sections[index].threads!)
        }

        guard !self[keyPath: section.threads].isEmpty else { return nil }

        let firstIndexPath = IndexPath(item: 0, section: section.index)

        guard let thread,
              let index = self[keyPath: section.threads].firstIndex(where: { $0.uniqueId == thread.uniqueId })
        else { return firstIndexPath }

        if index < (self[keyPath: section.threads].count - 1) {
            return IndexPath(item: index + 1, section: section.index)
        } else {
            return nil
        }
    }

    func indexPath(beforeThread thread: TSThread?) -> IndexPath? {
        let section: (index: Int, threads: KeyPath<CLVRenderState, [TSThread]>)

        if let thread = thread, pinnedThreads.contains(where: { $0.uniqueId == thread.uniqueId }) {
            let index = sectionIndex(for: .pinned)!
            section = (index, sections[index].threads!)
        } else {
            let index = sectionIndex(for: .unpinned)!
            section = (index, sections[index].threads!)
        }

        guard !self[keyPath: section.threads].isEmpty else { return nil }

        let lastIndexPath = IndexPath(item: self[keyPath: section.threads].count - 1, section: section.index)

        guard let thread,
              let index = self[keyPath: section.threads].firstIndex(where: { $0.uniqueId == thread.uniqueId })
        else { return lastIndexPath }

        if index > 0 {
            return IndexPath(item: index - 1, section: section.index)
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
    let hasVisibleReminders: Bool
    let lastSelectedThreadId: String?
    let requiredVisibleThreadIds: Set<String>

    var hasArchivedThreadsRow: Bool {
        chatListMode == .inbox && inboxFilter == nil && archiveCount > 0
    }

    static var empty: CLVViewInfo {
        CLVViewInfo(
            chatListMode: .inbox,
            archiveCount: 0,
            inboxCount: 0,
            inboxFilter: nil,
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
            return CLVViewInfo(
                chatListMode: chatListMode,
                archiveCount: archiveCount,
                inboxCount: inboxCount,
                inboxFilter: inboxFilter,
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
