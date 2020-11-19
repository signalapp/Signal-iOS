import PromiseKit

extension Storage {
    
    public func getOrGenerateRegistrationID(using transaction: Any) -> UInt32 {
        SSKEnvironment.shared.tsAccountManager.getOrGenerateRegistrationId(transaction as! YapDatabaseReadWriteTransaction)
    }

    public func getSenderCertificate(for publicKey: String) -> SMKSenderCertificate {
        let (promise, seal) = Promise<SMKSenderCertificate>.pending()
        SSKEnvironment.shared.udManager.ensureSenderCertificate { senderCertificate in
            seal.fulfill(senderCertificate)
        } failure: { error in
            // Should never fail
        }
        return try! promise.wait()
    }
    
    /// Returns the ID of the thread the message was stored under along with the `TSIncomingMessage` that was constructed.
    public func persist(_ message: VisibleMessage, groupPublicKey: String?, using transaction: Any) -> (String, Any)? {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return nil }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getOrCreateThread(withContactId: message.sender!, transaction: transaction)
        }
        guard let thread = threadOrNil else { return nil }
        let message = TSIncomingMessage.from(message, associatedWith: thread, using: transaction)
        message.save(with: transaction)
        return (thread.uniqueId!, message)
    }
}
