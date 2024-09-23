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
        var threads: KeyPath<CLVRenderState, [TSThread]>?
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
        CLVRenderState(viewInfo: .empty, pinInfo: .empty, pinnedThreads: [], unpinnedThreads: [])
    }

    let viewInfo: CLVViewInfo
    let pinInfo: ChatListPinInfo
    let pinnedThreads: [TSThread]
    let unpinnedThreads: [TSThread]

    private(set) var sections: [Section] = []
    private(set) var inboxFilterSection: ChatListInboxFilterSection?

    init(viewInfo: CLVViewInfo, pinInfo: ChatListPinInfo, pinnedThreads: [TSThread], unpinnedThreads: [TSThread]) {
        self.viewInfo = viewInfo
        self.pinInfo = pinInfo
        self.pinnedThreads = pinnedThreads
        self.unpinnedThreads = unpinnedThreads
        self.inboxFilterSection = ChatListInboxFilterSection(renderState: self)
        self.sections = ChatListSectionType.allCases.compactMap(makeSection(for:))
    }

    private func makeSection(for sectionType: ChatListSectionType) -> Section? {
        switch sectionType {
        case .pinned:
            let isTitleVisible = hasSectionTitles && !pinnedThreads.isEmpty
            return Section(
                type: sectionType,
                title: isTitleVisible ? OWSLocalizedString("PINNED_SECTION_TITLE", comment: "The title for pinned conversation section on the conversation list") : nil,
                threads: \.pinnedThreads
            )

        case .unpinned:
            let isTitleVisible = hasSectionTitles && !unpinnedThreads.isEmpty
            return Section(
                type: sectionType,
                title: isTitleVisible ? OWSLocalizedString("UNPINNED_SECTION_TITLE", comment: "The title for unpinned conversation section on the conversation list") : nil,
                threads: \.unpinnedThreads
            )

        case .reminders where hasVisibleReminders,
             .archiveButton where hasArchivedThreadsRow:
            return Section(type: sectionType)

        case .inboxFilterFooter:
            guard let inboxFilterSection else { return nil }
            return Section(type: sectionType, value: inboxFilterSection)

        case .reminders, .archiveButton:
            return nil
        }
    }

    var hasSectionTitles: Bool {
        pinInfo.pinnedThreadCount > 0
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

    // MARK: UITableViewDataSource

    func numberOfRows(in section: Section) -> Int {
        switch section.type {
        case .reminders, .archiveButton, .inboxFilterFooter:
            return 1
        case .pinned:
            return pinnedThreads.count
        case .unpinned:
            return unpinnedThreads.count
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

        case .pinned, .unpinned, .reminders, .archiveButton:
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

        case .pinned, .unpinned, .reminders, .archiveButton:
            owsFailDebug("Section diffing not yet supported in section '\(section.type)'")
            return nil
        }
    }

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
