// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension Storage : SessionMessagingKitStorageProtocol {
    
    public func updateMessageIDCollectionByPruningMessagesWithIDs(_ messageIDs: Set<String>, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        OWSPrimaryStorage.shared().updateMessageIDCollectionByPruningMessagesWithIDs(messageIDs, in: transaction)
    }
}
