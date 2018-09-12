//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSBlockListCacheDelegate)
public protocol BlockListCacheDelegate: class {
    func blockListCacheDidUpdate(_ blocklistCache: BlockListCache)
}

/// A performant cache for which contacts/groups are blocked.
///
/// The source of truth for which contacts and groups are blocked is the `blockingManager`, but because
/// those accessors are made to be thread safe, they can be slow in tight loops, e.g. when rendering table
/// view cells.
///
/// Typically you'll want to create a Cache, update it to the latest state while simultaneously being informed
/// of any future changes to block list state.
///
///     class SomeViewController: BlockListCacheDelegate {
///         let blockListCache = BlockListCache()
///         func viewDidLoad() {
///            super.viewDidLoad()
///            blockListCache.startObservingAndSyncState(delegate: self)
///            self.updateAnyViewsWhichDepondOnBlockListCache()
///         }
///
///         func blockListCacheDidUpdate(_ blocklistCache: BlockListCache) {
///             self.updateAnyViewsWhichDepondOnBlockListCache()
///         }
///
///         ...
///      }
///
@objc(OWSBlockListCache)
public class BlockListCache: NSObject {

    private var blockedRecipientIds: Set<String> = Set()
    private var blockedGroupIds: Set<Data> = Set()
    private let serialQueue: DispatchQueue = DispatchQueue(label: "BlockListCache")
    weak var delegate: BlockListCacheDelegate?

    private var blockingManager: OWSBlockingManager {
        return OWSBlockingManager.shared()
    }

    /// Generally something which wants to use this cache wants to do 3 things
    ///   1. get the cache on the latest state
    ///   2. update the cache whenever the blockingManager's state changes
    ///   3. be notified when the cache updates
    /// This method does all three.
    @objc
    public func startObservingAndSyncState(delegate: BlockListCacheDelegate) {
        self.delegate = delegate
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(blockListDidChange),
                                               name: NSNotification.Name(rawValue: kNSNotificationName_BlockListDidChange),
                                               object: nil)
        updateWithoutNotifyingDelegate()
    }

    // MARK: -

    @objc
    func blockListDidChange() {
        self.update()
    }

    @objc(isRecipientIdBlocked:)
    public func isBlocked(recipientId: String) -> Bool {
        return serialQueue.sync {
            blockedRecipientIds.contains(recipientId)
        }
    }

    @objc(isGroupIdBlocked:)
    public func isBlocked(groupId: Data) -> Bool {
        return serialQueue.sync {
            blockedGroupIds.contains(groupId)
        }
    }

    @objc(isThreadBlocked:)
    public func isBlocked(thread: TSThread) -> Bool {
        switch thread {
        case let contactThread as TSContactThread:
            return serialQueue.sync {
                blockedRecipientIds.contains(contactThread.contactIdentifier())
            }
        case let groupThread as TSGroupThread:
            return serialQueue.sync {
                blockedGroupIds.contains(groupThread.groupModel.groupId)
            }
        default:
            owsFail("\(self.logTag) in \(#function) unexepected thread type: \(type(of: thread))")
            return false
        }
    }

    // MARK: -

    public func update() {
        updateWithoutNotifyingDelegate()
        DispatchQueue.main.async {
            self.delegate?.blockListCacheDidUpdate(self)
        }
    }

    private func updateWithoutNotifyingDelegate() {
        let blockedRecipientIds = Set(blockingManager.blockedPhoneNumbers())
        let blockedGroupIds = Set(blockingManager.blockedGroupIds)
        update(blockedRecipientIds: blockedRecipientIds, blockedGroupIds: blockedGroupIds)
    }

    private func update(blockedRecipientIds: Set<String>, blockedGroupIds: Set<Data>) {
        serialQueue.sync {
            self.blockedRecipientIds = blockedRecipientIds
            self.blockedGroupIds = blockedGroupIds
        }
    }
}
