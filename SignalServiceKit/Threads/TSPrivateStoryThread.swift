//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSPrivateStoryThread {
    public typealias RowId = Int64

    @objc
    public class var myStoryUniqueId: String {
        // My Story always uses a UUID of all 0s
        "00000000-0000-0000-0000-000000000000"
    }

    public class func getMyStory(transaction: DBReadTransaction) -> TSPrivateStoryThread! {
        anyFetchPrivateStoryThread(uniqueId: myStoryUniqueId, transaction: transaction)
    }

    @discardableResult
    public class func getOrCreateMyStory(transaction: DBWriteTransaction) -> TSPrivateStoryThread {
        if let myStory = getMyStory(transaction: transaction) { return myStory }

        let myStory = TSPrivateStoryThread(uniqueId: myStoryUniqueId, name: "", allowsReplies: true, viewMode: .blockList)
        myStory.anyInsert(transaction: transaction)
        return myStory
    }

    // MARK: -

    @objc
    public var distributionListIdentifier: Data? { UUID(uuidString: uniqueId)?.data }

    override public func recipientAddresses(with tx: DBReadTransaction) -> [SignalServiceAddress] {
        let storyRecipientManager = DependenciesBridge.shared.storyRecipientManager
        do {
            switch storyViewMode {
            case .default:
                throw OWSAssertionError("Unexpectedly have private story with no view mode")
            case .explicit, .disabled:
                return try storyRecipientManager.fetchRecipients(forStoryThread: self, tx: tx).map { $0.address }
            case .blockList:
                let blockedAddresses = try storyRecipientManager.fetchRecipients(forStoryThread: self, tx: tx).map { $0.address }
                let profileManager = SSKEnvironment.shared.profileManagerRef
                return profileManager.allWhitelistedRegisteredAddresses(tx: tx).filter {
                    return !blockedAddresses.contains($0) && !$0.isLocalAddress
                }
            }
        } catch {
            Logger.warn("Couldn't fetch addresses; returning []: \(error)")
            return []
        }
    }

    // MARK: - updateWith...

    public func updateWithAllowsReplies(
        _ allowsReplies: Bool,
        updateStorageService: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdatePrivateStoryThread(transaction: tx) { privateStoryThread in
            privateStoryThread.allowsReplies = allowsReplies
        }

        if updateStorageService, let distributionListIdentifier {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(
                updatedStoryDistributionListIds: [distributionListIdentifier],
            )
        }
    }

    public func updateWithName(
        _ name: String,
        updateStorageService: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdatePrivateStoryThread(transaction: tx) { privateStoryThread in
            privateStoryThread.name = name
        }

        if updateStorageService, let distributionListIdentifier {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(
                updatedStoryDistributionListIds: [distributionListIdentifier],
            )
        }
    }

    /// Update this private story thread with the given view mode and
    /// corresponding addresses.
    ///
    /// - Parameter updateStorageService
    /// Whether or not we should update the distribution list this thread
    /// represents in Storage Service.
    /// - Parameter updateHasSetMyStoryPrivacyIfNeeded
    /// Whether or not we should set the local "has set My Story privacy" flag
    /// (to `true`), assuming this thread represents "My Story". Only callers
    /// who will be managing that flag's state themselves – at the time of
    /// writing, that is exclusively Backups – should set this to `false`.
    public func updateWithStoryViewMode(
        _ storyViewMode: TSThreadStoryViewMode,
        storyRecipientIds storyRecipientIdsChange: OptionalChange<[SignalRecipient.RowId]>,
        updateStorageService: Bool,
        updateHasSetMyStoryPrivacyIfNeeded: Bool = true,
        transaction tx: DBWriteTransaction,
    ) {
        if updateHasSetMyStoryPrivacyIfNeeded, isMyStory {
            StoryManager.setHasSetMyStoriesPrivacy(
                true,
                shouldUpdateStorageService: updateStorageService,
                transaction: tx,
            )
        }

        anyUpdatePrivateStoryThread(transaction: tx) { privateStoryThread in
            privateStoryThread.storyViewMode = storyViewMode
        }

        switch storyRecipientIdsChange {
        case .noChange:
            break
        case .setTo(let storyRecipientIds):
            let storyRecipientManager = DependenciesBridge.shared.storyRecipientManager
            failIfThrows {
                try storyRecipientManager.setRecipientIds(
                    storyRecipientIds,
                    for: self,
                    shouldUpdateStorageService: false, // handled below
                    tx: tx,
                )
            }
        }

        if updateStorageService, let distributionListIdentifier {
            tx.addSyncCompletion {
                let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef
                storageServiceManager.recordPendingUpdates(updatedStoryDistributionListIds: [distributionListIdentifier])
            }
        }
    }
}
