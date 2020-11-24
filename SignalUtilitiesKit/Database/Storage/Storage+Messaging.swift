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

    /// Returns the ID of the thread the message was stored under along with the ID of the `TSIncomingMessage` that was constructed.
    public func persist(_ message: VisibleMessage, groupPublicKey: String?, using transaction: Any) -> (String, String)? {
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
        let message = TSIncomingMessage.from(message, associatedWith: thread)
        message.save(with: transaction)
        DispatchQueue.main.async { message.touch() } // FIXME: Hack for a thread updating issue
        return (thread.uniqueId!, message.uniqueId!)
    }

    /// Returns the IDs of the saved attachments.
    public func persist(_ attachments: [VisibleMessage.Attachment], using transaction: Any) -> [String] {
        return attachments.map { attachment in
            let tsAttachment = TSAttachmentPointer.from(attachment)
            tsAttachment.save(with: transaction as! YapDatabaseReadWriteTransaction)
            return tsAttachment.uniqueId!
        }
    }
    
    /// Also touches the associated message.
    public func setAttachmentState(to state: TSAttachmentPointerState, for pointer: TSAttachmentPointer, associatedWith tsIncomingMessageID: String, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        pointer.state = state
        pointer.save(with: transaction)
        guard let tsIncomingMessage = TSIncomingMessage.fetch(uniqueId: tsIncomingMessageID, transaction: transaction) else { return }
        tsIncomingMessage.touch(with: transaction)
    }
    
    /// Also touches the associated message.
    public func persist(_ stream: TSAttachmentStream, associatedWith tsIncomingMessageID: String, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        stream.save(with: transaction)
        guard let tsIncomingMessage = TSIncomingMessage.fetch(uniqueId: tsIncomingMessageID, transaction: transaction) else { return }
        tsIncomingMessage.touch(with: transaction)
    }
}

