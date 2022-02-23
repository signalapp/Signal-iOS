import PromiseKit
import Sodium

extension Storage {

    /// Returns the ID of the thread.
    public func getOrCreateThread(for publicKey: String, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let openGroupID = openGroupID {
            if let threadID = Storage.shared.getThreadID(for: openGroupID),
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
        let isOutgoingMessage: Bool
        
        // Need to check if the blinded id matches for open groups
        if let sender: String = message.sender, let openGroupID: String = openGroupID {
            guard let userEdKeyPair: Box.KeyPair = Storage.shared.getUserED25519KeyPair() else { return nil }
            
            switch IdPrefix(with: sender) {
                case .blinded:
                    let sodium: Sodium = Sodium()
                    let serverNameParts: [String.SubSequence] = openGroupID.split(separator: ".")
                    let serverName: String = serverNameParts[0..<(serverNameParts.count - 1)].joined(separator: ".")
                    
                    // Note: This is horrible but it doesn't look like there is going to be a nicer way to do it...
                    guard let serverPublicKey: String = Storage.shared.getOpenGroupPublicKey(for: serverName) else {
                        return nil
                    }
                    guard let blindedKeyPair: Box.KeyPair = sodium.blindedKeyPair(serverPublicKey: serverPublicKey, edKeyPair: userEdKeyPair, genericHash: sodium.genericHash) else {
                        return nil
                    }
                    
                    isOutgoingMessage = (sender == IdPrefix.blinded.hexEncodedPublicKey(for: blindedKeyPair.publicKey))
                    
                case .standard, .unblinded:
                    isOutgoingMessage = (
                        message.sender == getUserPublicKey() ||
                        sender == IdPrefix.unblinded.hexEncodedPublicKey(for: userEdKeyPair.publicKey)
                    )
                    
                case .none:
                    isOutgoingMessage = false
            }
        }
        else {
            isOutgoingMessage = (message.sender == getUserPublicKey())
        }
        
        if isOutgoingMessage {
            if let _ = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) { return nil }
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
        }
        else {
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

