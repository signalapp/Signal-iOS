//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// A snapshot combining both view database state used to render chat list table view rows.
struct CLVRenderState {
    struct Section: Hashable, Identifiable {
        var type: ChatListSectionType
        var id: ChatListSectionType { type }
        var title: String?
        var threadUniqueIds: KeyPath<CLVRenderState, [String]>?
        var value: AnyHashable?
    }

    /// A type-erased representation of a row in a dynamic section of the chat
    /// list, to support automatic diffing of rows.
    struct RowItem: Hashable, Identifiable {
        var section: ChatListSectionType
        var id: AnyHashable
        var value: AnyHashable

        init(section: ChatListSectionType, value: some Hashable & Identifiable) {
            self.section = section
            self.id = value.id
            self.value = value
        }
    }

    static var empty: CLVRenderState {
        CLVRenderState(
            viewInfo: .empty,
            pinnedThreadUniqueIds: [],
            unpinnedThreadUniqueIds: [],
        )
    }

    let viewInfo: CLVViewInfo
    let pinnedThreadUniqueIds: [String]
    let unpinnedThreadUniqueIds: [String]

    private(set) var sections: [Section] = []
    private(set) var inboxFilterSection: ChatListInboxFilterSection?

    init(
        viewInfo: CLVViewInfo,
        pinnedThreadUniqueIds: [String],
        unpinnedThreadUniqueIds: [String],
    ) {
        self.viewInfo = viewInfo
        self.pinnedThreadUniqueIds = pinnedThreadUniqueIds
        self.unpinnedThreadUniqueIds = unpinnedThreadUniqueIds
        self.inboxFilterSection = ChatListInboxFilterSection(renderState: self)
        self.sections = ChatListSectionType.allCases.compactMap(makeSection(for:))
    }

    private func makeSection(for sectionType: ChatListSectionType) -> Section? {
        switch sectionType {
        case .pinned:
            let isTitleVisible = hasSectionTitles && !pinnedThreadUniqueIds.isEmpty
            return Section(
                type: sectionType,
                title: isTitleVisible ? OWSLocalizedString("PINNED_SECTION_TITLE", comment: "The title for pinned conversation section on the conversation list") : nil,
                threadUniqueIds: \.pinnedThreadUniqueIds,
            )

        case .unpinned:
            let isTitleVisible = hasSectionTitles && !unpinnedThreadUniqueIds.isEmpty
            return Section(
                type: sectionType,
                title: isTitleVisible ? OWSLocalizedString("UNPINNED_SECTION_TITLE", comment: "The title for unpinned conversation section on the conversation list") : nil,
                threadUniqueIds: \.unpinnedThreadUniqueIds,
            )

        case .reminders where hasVisibleReminders,
             .backupDownloadProgressView where shouldBackupDownloadProgressViewBeVisible,
             .archiveButton where hasArchivedThreadsRow:
            return Section(type: sectionType)

        case .inboxFilterFooter:
            guard let inboxFilterSection else { return nil }
            return Section(type: sectionType, value: inboxFilterSection)

        case .reminders, .backupDownloadProgressView, .archiveButton:
            return nil
        }
    }

    var hasSectionTitles: Bool {
        !pinnedThreadUniqueIds.isEmpty
    }

    var visibleThreadCount: Int {
        pinnedThreadUniqueIds.count + unpinnedThreadUniqueIds.count
    }

    var hasArchivedThreadsRow: Bool {
        viewInfo.hasArchivedThreadsRow
    }

    var hasVisibleReminders: Bool {
        viewInfo.hasVisibleReminders
    }

    var shouldBackupDownloadProgressViewBeVisible: Bool {
        viewInfo.shouldBackupDownloadProgressViewBeVisible
    }

    // MARK: UITableViewDataSource

    func numberOfRows(in section: Section) -> Int {
        switch section.type {
        case .reminders, .backupDownloadProgressView, .archiveButton, .inboxFilterFooter:
            return 1
        case .pinned:
            return pinnedThreadUniqueIds.count
        case .unpinned:
            return unpinnedThreadUniqueIds.count
        }
    }

    /// For chat list sections that support dynamic content, compute a
    /// collection difference of the rows in that section.
    func sectionDifference(for section: Section, from renderState: CLVRenderState) -> CollectionDifference<RowItem>? {
        switch section.type {
        case .inboxFilterFooter:
            let items = items(in: section) ?? []
            let oldValue = renderState.items(in: section) ?? []
            return items.difference(from: oldValue)

        case .pinned, .unpinned, .reminders, .backupDownloadProgressView, .archiveButton:
            return nil
        }
    }

    private func items(in section: Section) -> [RowItem]? {
        switch section.type {
        case .inboxFilterFooter:
            if let inboxFilterSection {
                return [RowItem(section: section.type, value: inboxFilterSection)]
            } else {
                return nil
            }

        case .pinned, .unpinned, .reminders, .backupDownloadProgressView, .archiveButton:
            owsFailDebug("Section diffing not yet supported in section '\(section.type)'")
            return nil
        }
    }

    func sectionIndex(for sectionType: ChatListSectionType) -> Int? {
        sections.firstIndex(where: { $0.type == sectionType })
    }

    func threadUniqueId(forIndexPath indexPath: IndexPath) -> String? {
        let section = sections[indexPath.section]
        guard let key = section.threadUniqueIds else { return nil }
        return self[keyPath: key][indexPath.row]
    }

    func indexPath(forUniqueId uniqueId: String) -> IndexPath? {
        if let index = pinnedThreadUniqueIds.firstIndex(of: uniqueId) {
            let section = sectionIndex(for: .pinned)!
            return IndexPath(item: index, section: section)
        } else if let index = unpinnedThreadUniqueIds.firstIndex(of: uniqueId) {
            let section = sectionIndex(for: .unpinned)!
            return IndexPath(item: index, section: section)
        } else {
            return nil
        }
    }

    func indexPath(afterThread thread: TSThread?) -> IndexPath? {
        let section: (index: Int, threadUniqueIds: KeyPath<CLVRenderState, [String]>)

        let threadIsPinned = thread.map { pinnedThreadUniqueIds.contains($0.uniqueId) } == true
        let noThreadSelectedAndHasPinnedThreads = thread == nil && !pinnedThreadUniqueIds.isEmpty
        if threadIsPinned || noThreadSelectedAndHasPinnedThreads {
            let index = sectionIndex(for: .pinned)!
            section = (index, sections[index].threadUniqueIds!)
        } else {
            let index = sectionIndex(for: .unpinned)!
            section = (index, sections[index].threadUniqueIds!)
        }

        guard !self[keyPath: section.threadUniqueIds].isEmpty else { return nil }

        let firstIndexPath = IndexPath(item: 0, section: section.index)

        guard
            let thread,
            let index = self[keyPath: section.threadUniqueIds].firstIndex(of: thread.uniqueId)
        else { return firstIndexPath }

        if index < (self[keyPath: section.threadUniqueIds].count - 1) {
            return IndexPath(item: index + 1, section: section.index)
        } else if
            let nextSection = sections[safe: section.index + 1],
            let nextSectionThreads = nextSection.threadUniqueIds,
            !self[keyPath: nextSectionThreads].isEmpty
        {
            return IndexPath(item: 0, section: section.index + 1)
        } else {
            return nil
        }
    }

    func indexPath(beforeThread thread: TSThread?) -> IndexPath? {
        let section: (index: Int, threadUniqueIds: KeyPath<CLVRenderState, [String]>)

        let threadIsPinned = thread.map { pinnedThreadUniqueIds.contains($0.uniqueId) } == true
        let allChatsArePinned = unpinnedThreadUniqueIds.isEmpty
        if threadIsPinned || allChatsArePinned {
            let index = sectionIndex(for: .pinned)!
            section = (index, sections[index].threadUniqueIds!)
        } else {
            let index = sectionIndex(for: .unpinned)!
            section = (index, sections[index].threadUniqueIds!)
        }

        guard !self[keyPath: section.threadUniqueIds].isEmpty else { return nil }

        let lastIndexPath = IndexPath(item: self[keyPath: section.threadUniqueIds].count - 1, section: section.index)

        guard
            let thread,
            let index = self[keyPath: section.threadUniqueIds].firstIndex(of: thread.uniqueId)
        else { return lastIndexPath }

        if index > 0 {
            return IndexPath(item: index - 1, section: section.index)
        } else if
            let previousSection = sections[safe: section.index - 1],
            let previousSectionThreads = previousSection.threadUniqueIds,
            !self[keyPath: previousSectionThreads].isEmpty
        {
            return IndexPath(item: self[keyPath: previousSectionThreads].count - 1, section: section.index - 1)
        } else {
            return nil
        }
    }
}
