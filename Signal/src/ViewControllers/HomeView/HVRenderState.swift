//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class HVRenderState: NSObject {

    let pinnedThreads: OrderedDictionary<String, TSThread>
    let unpinnedThreads: [TSThread]

    let archiveCount: UInt
    let inboxCount: UInt

    public init(pinnedThreads: OrderedDictionary<String, TSThread>,
                unpinnedThreads: [TSThread],
                archiveCount: UInt,
                inboxCount: UInt) {
        self.pinnedThreads = pinnedThreads
        self.unpinnedThreads = unpinnedThreads
        self.archiveCount = archiveCount
        self.inboxCount = inboxCount
    }

    public static var empty: HVRenderState {
        HVRenderState(pinnedThreads: OrderedDictionary(),
                      unpinnedThreads: [],
                      archiveCount: 0,
                      inboxCount: 0)
    }

    public var hasPinnedAndUnpinnedThreads: Bool {
        !pinnedThreads.isEmpty && !unpinnedThreads.isEmpty
    }

    @objc
    func thread(forIndexPath indexPath: IndexPath) -> TSThread? {
        guard let section = HomeViewSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return nil
        }

        switch section {
        case .pinned:
            guard let thread = pinnedThreads[safe: indexPath.row]?.value else {
                owsFailDebug("No thread for index path: \(indexPath)")
                return nil
            }
            return thread
        case .unpinned:
            guard let thread = unpinnedThreads[safe: indexPath.row] else {
                owsFailDebug("No thread for index path: \(indexPath)")
                return nil
            }
            return thread
        default:
            owsFailDebug("Invalid index path: \(indexPath).")
            return nil
        }
    }

    @objc
    func indexPath(forUniqueId uniqueId: String) -> IndexPath? {
        if let index = (unpinnedThreads.firstIndex { $0.uniqueId == uniqueId}) {
            return IndexPath(item: index, section: HomeViewSection.unpinned.rawValue)
        } else if let index = (pinnedThreads.orderedKeys.firstIndex { $0 == uniqueId}) {
            return IndexPath(item: index, section: HomeViewSection.pinned.rawValue)
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

        let section: HomeViewSection = isPinnedThread ? .pinned : .unpinned
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

        let section: HomeViewSection = isPinnedThread ? .pinned : .unpinned
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
