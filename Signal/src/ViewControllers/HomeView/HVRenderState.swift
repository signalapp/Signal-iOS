//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class HVRenderState: NSObject {

    // TODO: What collection type should we use here?
    let pinnedThreads: OrderedDictionary<String, TSThread>
    let unpinnedThreads: [TSThread]

    // We use a new cache for each render state.
    private let threadViewModelCache = LRUCache<String, ThreadViewModel>(maxSize: 32)

    public init(pinnedThreads: OrderedDictionary<String, TSThread>,
                unpinnedThreads: [TSThread]) {
        self.pinnedThreads = pinnedThreads
        self.unpinnedThreads = unpinnedThreads
    }

    public static var empty: HVRenderState {
        HVRenderState(pinnedThreads: OrderedDictionary(),
                      unpinnedThreads: [])
    }

    public var hasPinnedAndUnpinnedThreads: Bool {
        !pinnedThreads.isEmpty && !unpinnedThreads.isEmpty
    }

    public func threadViewModel(forThread thread: TSThread) -> ThreadViewModel {
        if let value = threadViewModelCache.get(key: thread.uniqueId) {
            return value
        }
        let threadViewModel = databaseStorage.read { transaction in
            ThreadViewModel(thread: thread, forConversationList: true, transaction: transaction)
        }
        threadViewModelCache.set(key: thread.uniqueId, value: threadViewModel)
        return threadViewModel
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
    func threadViewModel(forIndexPath indexPath: IndexPath) -> ThreadViewModel? {
        guard let thread = self.thread(forIndexPath: indexPath) else {
            return nil
        }
        return self.threadViewModel(forThread: thread)
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
}
