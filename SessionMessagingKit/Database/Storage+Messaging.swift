import PromiseKit

extension Storage {

    /// Returns the ID of the thread.
    public func getOrCreateThread(for publicKey: String, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let openGroupID = openGroupID {
            if let threadID = Storage.shared.v2GetThreadID(for: openGroupID),
                let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) {
                threadOrNil = thread
            }
        } else if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return nil }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getOrCreateThread(withContactSessionID: publicKey, transaction: transaction)
        }
        return threadOrNil?.uniqueId
    }

    /// Returns the ID of the `TSIncomingMessage` that was constructed.
    public func persist(_ message: VisibleMessage, quotedMessage: TSQuotedMessage?, linkPreview: OWSLinkPreview?, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let threadID = getOrCreateThread(for: message.syncTarget ?? message.sender!, groupPublicKey: groupPublicKey, openGroupID: openGroupID, using: transaction),
            let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return nil }
        let tsMessage: TSMessage
        if message.sender == getUserPublicKey() {
            let tsOutgoingMessage = TSOutgoingMessage.from(message, associatedWith: thread, using: transaction)
            var recipients: [String] = []
            if let syncTarget = message.syncTarget {
                recipients.append(syncTarget)
            } else if let thread = thread as? TSGroupThread {
                if thread.isClosedGroup { recipients = thread.groupModel.groupMemberIds }
                else { recipients.append(LKGroupUtilities.getDecodedGroupID(thread.groupModel.groupId)) }
            }
            recipients.forEach { recipient in
                tsOutgoingMessage.update(withSentRecipient: recipient, wasSentByUD: true, transaction: transaction)
            }
            tsMessage = tsOutgoingMessage
        } else {
            tsMessage = TSIncomingMessage.from(message, quotedMessage: quotedMessage, linkPreview: linkPreview, associatedWith: thread)
        }
        tsMessage.save(with: transaction)
        tsMessage.attachments(with: transaction).forEach { attachment in
            attachment.albumMessageId = tsMessage.uniqueId!
            attachment.save(with: transaction)
        }
        return tsMessage.uniqueId!
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
    public func setAttachmentState(to state: TSAttachmentPointerState, for pointer: TSAttachmentPointer, associatedWith tsMessageID: String, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Workaround for some YapDatabase funkiness where pointer at this point can actually be a TSAttachmentStream
        guard pointer.responds(to: #selector(setter: TSAttachmentPointer.state)) else { return }
        pointer.state = state
        pointer.save(with: transaction)
        guard let tsMessage = TSMessage.fetch(uniqueId: tsMessageID, transaction: transaction) else { return }
        MessageInvalidator.invalidate(tsMessage, with: transaction)
    }
    
    /// Also touches the associated message.
    public func persist(_ stream: TSAttachmentStream, associatedWith tsMessageID: String, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        stream.save(with: transaction)
        guard let tsMessage = TSMessage.fetch(uniqueId: tsMessageID, transaction: transaction) else { return }
        MessageInvalidator.invalidate(tsMessage, with: transaction)
    }

    private static let receivedMessageTimestampsCollection = "ReceivedMessageTimestampsCollection"

    public func getReceivedMessageTimestamps(using transaction: Any) -> [UInt64] {
        var result: [UInt64] = []
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        transaction.enumerateRows(inCollection: Storage.receivedMessageTimestampsCollection) { _, object, _, _ in
            guard let timestamps = object as? [UInt64] else { return }
            result = timestamps
        }
        return result
    }
    
    public func removeReceivedMessageTimestamps(_ timestamps: Set<UInt64>, using transaction: Any) {
        var receivedMessageTimestamps = getReceivedMessageTimestamps(using: transaction)
        timestamps.forEach { timestamp in
            guard let index = receivedMessageTimestamps.firstIndex(of: timestamp) else { return }
            receivedMessageTimestamps.remove(at: index)
        }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        transaction.setObject(receivedMessageTimestamps, forKey: "receivedMessageTimestamps", inCollection: Storage.receivedMessageTimestampsCollection)
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

