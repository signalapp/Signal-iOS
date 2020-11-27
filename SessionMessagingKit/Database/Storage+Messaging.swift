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

    /// Returns the ID of the thread.
    public func getOrCreateThread(for publicKey: String, groupPublicKey: String?, using transaction: Any) -> String? {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return nil }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getOrCreateThread(withContactId: publicKey, transaction: transaction)
        }
        return threadOrNil?.uniqueId
    }

    /// Returns the ID of the `TSIncomingMessage` that was constructed.
    public func persist(_ message: VisibleMessage, withQuotedMessage quotedMessage: TSQuotedMessage?, groupPublicKey: String?, using transaction: Any) -> String? {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let threadID = getOrCreateThread(for: message.sender!, groupPublicKey: groupPublicKey, using: transaction),
            let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return nil }
        let message = TSIncomingMessage.from(message, withQuotedMessage: quotedMessage, associatedWith: thread)
        message.save(with: transaction)
        DispatchQueue.main.async { message.touch() } // FIXME: Hack for a thread updating issue
        return message.uniqueId!
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
        // Workaround for some YapDatabase funkiness where pointer at this point can actually be a TSAttachmentStream
        guard pointer.responds(to: #selector(setter: TSAttachmentPointer.state)) else { return }
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

    private static let receivedMessageTimestampsCollection = "ReceivedMessageTimestampsCollection"

    public func getReceivedMessageTimestamps(using transaction: Any) -> [UInt64] {
        var result: [UInt64] = []
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        transaction.enumerateRows(inCollection: Storage.receivedMessageTimestampsCollection) { _, object, _, _ in
            guard let timestamp = object as? UInt64 else { return }
            result.append(timestamp)
        }
        return result
    }

    public func addReceivedMessageTimestamp(_ timestamp: UInt64, using transaction: Any) {
        var receivedMessageTimestamps = getReceivedMessageTimestamps(using: transaction)
        // TODO: Do we need to sort the timestamps here?
        if receivedMessageTimestamps.count > 1000 { receivedMessageTimestamps.remove(at: 0) } // Limit the size of the collection to 1000
        receivedMessageTimestamps.append(timestamp)
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        transaction.setObject(receivedMessageTimestamps, forKey: "receivedMessageTimestamps", inCollection: Storage.receivedMessageTimestampsCollection)
    }
}

