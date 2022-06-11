//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension TSPrivateStoryThread {
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
        case .none:
            owsFailDebug("Unexpectedly have private story with no view mode")
            return []
        case .explicit:
            return addresses
        case .blockList:
            return profileManager.allWhitelistedRegisteredAddresses(with: transaction).filter { !addresses.contains($0) }
        }
    }
}
