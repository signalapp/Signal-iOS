//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class CLVRenderState: NSObject {

    let viewInfo: CLVViewInfo

    let pinnedThreads: OrderedDictionary<String, TSThread>
    let unpinnedThreads: [TSThread]

    var archiveCount: UInt { viewInfo.archiveCount }
    var inboxCount: UInt { viewInfo.inboxCount }

    var visibleThreadCount: Int { pinnedThreads.count + unpinnedThreads.count }

    var hasArchivedThreadsRow: Bool { viewInfo.hasArchivedThreadsRow }
    var hasVisibleReminders: Bool { viewInfo.hasVisibleReminders }

    // MARK: -

    public init(viewInfo: CLVViewInfo,
                pinnedThreads: OrderedDictionary<String, TSThread>,
                unpinnedThreads: [TSThread]) {
        self.viewInfo = viewInfo
        self.pinnedThreads = pinnedThreads
        self.unpinnedThreads = unpinnedThreads
    }

    public static var empty: CLVRenderState {
        CLVRenderState(viewInfo: .empty,
                      pinnedThreads: OrderedDictionary(),
                      unpinnedThreads: [])
    }

    public var hasPinnedAndUnpinnedThreads: Bool {
        !pinnedThreads.isEmpty && !unpinnedThreads.isEmpty
    }

    func thread(forIndexPath indexPath: IndexPath, expectsSuccess: Bool = true) -> TSThread? {
        guard let section = ChatListSection(rawValue: indexPath.section) else {
            if expectsSuccess {
                owsFailDebug("Invalid section: \(indexPath.section).")
            }
            return nil
        }

        switch section {
        case .pinned:
            guard let thread = pinnedThreads[safe: indexPath.row]?.value else {
                if expectsSuccess {
                    owsFailDebug("No thread for index path: \(indexPath)")
                }
                return nil
            }
            return thread
        case .unpinned:
            guard let thread = unpinnedThreads[safe: indexPath.row] else {
                if expectsSuccess {
                    owsFailDebug("No thread for index path: \(indexPath)")
                }
                return nil
            }
            return thread
        default:
            if expectsSuccess {
                owsFailDebug("Invalid index path: \(indexPath).")
            }
            return nil
        }
    }

    @objc
    func indexPath(forUniqueId uniqueId: String) -> IndexPath? {
        if let index = (unpinnedThreads.firstIndex { $0.uniqueId == uniqueId}) {
            return IndexPath(item: index, section: ChatListSection.unpinned.rawValue)
        } else if let index = (pinnedThreads.orderedKeys.firstIndex { $0 == uniqueId}) {
            return IndexPath(item: index, section: ChatListSection.pinned.rawValue)
        } else {
            return nil
        }
    }

    func indexPath(afterThread thread: TSThread?) -> IndexPath? {
        let isPinnedThread: Bool
        if let thread = thread, pinnedThreads.orderedKeys.contains(thread.uniqueId) {
            isPinnedThread = true
        } else {
            isPinnedThread = false
        }

        let section: ChatListSection = isPinnedThread ? .pinned : .unpinned
        let threadsInSection = isPinnedThread ? pinnedThreads.orderedValues : unpinnedThreads

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
        if let thread = thread, pinnedThreads.orderedKeys.contains(thread.uniqueId) {
            isPinnedThread = true
        } else {
            isPinnedThread = false
        }

        let section: ChatListSection = isPinnedThread ? .pinned : .unpinned
        let threadsInSection = isPinnedThread ? pinnedThreads.orderedValues : unpinnedThreads

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

public struct CLVViewInfo: Equatable {
    let chatListMode: ChatListMode
    let archiveCount: UInt
    let inboxCount: UInt
    let hasArchivedThreadsRow: Bool
    let hasVisibleReminders: Bool

    static var empty: CLVViewInfo {
        CLVViewInfo(chatListMode: .inbox,
                   archiveCount: 0,
                   inboxCount: 0,
                   hasArchivedThreadsRow: false,
                   hasVisibleReminders: false)
    }

    static func build(chatListMode: ChatListMode,
                      hasVisibleReminders: Bool,
                      transaction: SDSAnyReadTransaction) -> CLVViewInfo {
        do {
            let threadFinder = AnyThreadFinder()
            let archiveCount = try threadFinder.visibleThreadCount(isArchived: true, transaction: transaction)
            let inboxCount = try threadFinder.visibleThreadCount(isArchived: false, transaction: transaction)
            let hasArchivedThreadsRow = (chatListMode == .inbox && archiveCount > 0)
            return CLVViewInfo(chatListMode: chatListMode,
                              archiveCount: archiveCount,
                               inboxCount: inboxCount,
                               hasArchivedThreadsRow: hasArchivedThreadsRow,
                               hasVisibleReminders: hasVisibleReminders)
        } catch {
            owsFailDebug("Error: \(error)")
            return .empty
        }
    }
}
