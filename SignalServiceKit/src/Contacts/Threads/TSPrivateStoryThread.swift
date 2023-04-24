//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension TSPrivateStoryThread {
    @objc
    var distributionListIdentifier: Data? { UUID(uuidString: uniqueId)?.data }

    @objc
    class var myStoryUniqueId: String {
        // My Story always uses a UUID of all 0s
        "00000000-0000-0000-0000-000000000000"
    }

    class func getMyStory(transaction: SDSAnyReadTransaction) -> TSPrivateStoryThread! {
        anyFetchPrivateStoryThread(uniqueId: myStoryUniqueId, transaction: transaction)
    }

    @discardableResult
    class func getOrCreateMyStory(transaction: SDSAnyWriteTransaction) -> TSPrivateStoryThread! {
        if let myStory = getMyStory(transaction: transaction) { return myStory }

        let myStory = TSPrivateStoryThread(uniqueId: myStoryUniqueId, name: "", allowsReplies: true, addresses: [], viewMode: .blockList)
        myStory.anyInsert(transaction: transaction)
        return myStory
    }

    override func recipientAddresses(with transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        switch storyViewMode {
        case .default:
            owsFailDebug("Unexpectedly have private story with no view mode")
            return []
        case .explicit, .disabled:
            return addresses
        case .blockList:
            return profileManager.allWhitelistedRegisteredAddresses(with: transaction).filter { !addresses.contains($0) && !$0.isLocalAddress }
        }
    }

    private static let deletedAtTimestampKVS = SDSKeyValueStore(collection: "TSPrivateStoryThread+DeletedAtTimestamp")
    private static let deletedAtTimestampThreshold = kMonthInterval

    static func deletedAtTimestamp(forDistributionListIdentifier identifier: Data, transaction: SDSAnyReadTransaction) -> UInt64? {
        guard let uniqueId = UUID(data: identifier)?.uuidString else { return nil }
        return deletedAtTimestampKVS.getUInt64(uniqueId, transaction: transaction)
    }

    static func recordDeletedAtTimestamp(_ timestamp: UInt64, forDistributionListIdentifier identifier: Data, transaction: SDSAnyWriteTransaction) {
        guard Date().timeIntervalSince(Date(millisecondsSince1970: timestamp)) < deletedAtTimestampThreshold else {
            Logger.warn("Ignorning stale deleted at timestamp")
            return
        }

        guard let uniqueId = UUID(data: identifier)?.uuidString else { return }
        deletedAtTimestampKVS.setUInt64(timestamp, key: uniqueId, transaction: transaction)
    }

    static func allDeletedIdentifiers(transaction: SDSAnyReadTransaction) -> [Data] {
        deletedAtTimestampKVS.allKeys(transaction: transaction).compactMap { UUID(uuidString: $0)?.data }
    }

    static func cleanupDeletedTimestamps(transaction: SDSAnyWriteTransaction) {
        var deletedIdentifiers = [Data]()
        for identifier in deletedAtTimestampKVS.allKeys(transaction: transaction) {
            guard let timestamp = deletedAtTimestampKVS.getUInt64(
                identifier,
                transaction: transaction
            ) else { continue }
            guard Date().timeIntervalSince(Date(millisecondsSince1970: timestamp)) > deletedAtTimestampThreshold else { continue }
            deletedAtTimestampKVS.removeValue(forKey: identifier, transaction: transaction)

            // If we still have a private story thread for this deleted timestamp, it's
            // now safe to purge it from the database.
            TSPrivateStoryThread.anyFetchPrivateStoryThread(
                uniqueId: identifier,
                transaction: transaction
            )?.anyRemove(transaction: transaction)

            UUID(uuidString: identifier).map { deletedIdentifiers.append($0.data) }
        }
        Self.storageServiceManager.recordPendingUpdates(updatedStoryDistributionListIds: deletedIdentifiers)
    }

    override func updateWithShouldThreadBeVisible(_ shouldThreadBeVisible: Bool, transaction: SDSAnyWriteTransaction) {
        super.updateWithShouldThreadBeVisible(shouldThreadBeVisible, transaction: transaction)
        updateWithStoryViewMode(.disabled, transaction: transaction)
    }
}
