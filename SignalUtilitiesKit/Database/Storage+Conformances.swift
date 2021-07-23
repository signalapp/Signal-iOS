
extension Storage : SessionMessagingKitStorageProtocol, SessionSnodeKitStorageProtocol {
    
    public func updateMessageIDCollectionByPruningMessagesWithIDs(_ messageIDs: Set<String>, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        OWSPrimaryStorage.shared().updateMessageIDCollectionByPruningMessagesWithIDs(messageIDs, in: transaction)
    }
}
