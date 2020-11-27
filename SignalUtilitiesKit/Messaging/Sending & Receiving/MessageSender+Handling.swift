import SessionProtocolKit
import PromiseKit

extension MessageSender : SharedSenderKeysDelegate {

    // MARK: - Sending Convenience
    
    private static func prep(_ attachments: [SignalAttachment], for message: Message, using transaction: YapDatabaseReadWriteTransaction) {
        guard let message = message as? VisibleMessage else { return }
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else {
            #if DEBUG
            preconditionFailure()
            #endif
            return
        }
        var streams: [TSAttachmentStream] = []
        attachments.forEach {
            let stream = TSAttachmentStream(contentType: $0.mimeType, byteCount: UInt32($0.dataLength), sourceFilename: $0.sourceFilename,
                caption: $0.captionText, albumMessageId: tsMessage.uniqueId!)
            streams.append(stream)
            stream.write($0.dataSource)
            stream.save(with: transaction)
        }
        tsMessage.quotedMessage?.createThumbnailAttachmentsIfNecessary(with: transaction)
        if let linkPreviewAttachmentID = tsMessage.linkPreview?.imageAttachmentId,
            let stream = TSAttachment.fetch(uniqueId: linkPreviewAttachmentID, transaction: transaction) as? TSAttachmentStream {
            streams.append(stream)
        }
        message.attachmentIDs = streams.map { $0.uniqueId! }
        tsMessage.attachmentIds.addObjects(from: message.attachmentIDs)
        tsMessage.save(with: transaction)
    }
    
    @objc(send:withAttachments:inThread:usingTransaction:)
    public static func send(_ message: Message, with attachments: [SignalAttachment], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        prep(attachments, for: message, using: transaction)
        send(message, in: thread, using: transaction)
    }
    
    @objc(send:inThread:usingTransaction:)
    public static func send(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        if message is VisibleMessage { prep([], for: message, using: transaction) } // To handle quotes & link previews
        message.threadID = thread.uniqueId!
        let destination = Message.Destination.from(thread)
        let job = MessageSendJob(message: message, destination: destination)
        JobQueue.shared.add(job, using: transaction)
    }

    @objc(sendNonDurably:withAttachments:inThread:usingTransaction:)
    public static func objc_sendNonDurably(_ message: Message, with attachments: [SignalAttachment], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(sendNonDurably(message, with: attachments, in: thread, using: transaction))
    }
    
    @objc(sendNonDurably:inThread:usingTransaction:)
    public static func objc_sendNonDurably(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(sendNonDurably(message, in: thread, using: transaction))
    }
    
    public static func sendNonDurably(_ message: Message, with attachments: [SignalAttachment], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        prep(attachments, for: message, using: transaction)
        return sendNonDurably(message, in: thread, using: transaction)
    }

    public static func sendNonDurably(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        message.threadID = thread.uniqueId!
        let destination = Message.Destination.from(thread)
        return MessageSender.send(message, to: destination, using: transaction)
    }
    
    
    
    // MARK: - Success & Failure Handling
    
    public static func handleSuccessfulMessageSend(_ message: Message, using transaction: Any) {
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else { return }
        tsMessage.openGroupServerMessageID = message.openGroupServerMessageID ?? 0
        tsMessage.isOpenGroupMessage = tsMessage.openGroupServerMessageID != 0
        tsMessage.update(withSentRecipient: message.recipient!, wasSentByUD: true, transaction: transaction as! YapDatabaseReadWriteTransaction)
        OWSDisappearingMessagesJob.shared().startAnyExpiration(for: tsMessage, expirationStartedAt: NSDate.millisecondTimestamp(), transaction: transaction as! YapDatabaseReadWriteTransaction)
    }

    public static func handleFailedMessageSend(_ message: Message, with error: Swift.Error, using transaction: Any) {
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else { return }
        tsMessage.update(sendingError: error, transaction: transaction as! YapDatabaseReadWriteTransaction)
    }

    
    
    // MARK: - Closed Groups
    
    public static func createClosedGroup(name: String, members: Set<String>, transaction: YapDatabaseReadWriteTransaction) -> Promise<TSGroupThread> {
        // Prepare
        var members = members
        let userPublicKey = getUserHexEncodedPublicKey()
        // Generate a key pair for the group
        let groupKeyPair = Curve25519.generateKeyPair()
        let groupPublicKey = groupKeyPair.hexEncodedPublicKey // Includes the "05" prefix
        // Ensure the current user is included in the member list
        members.insert(userPublicKey)
        let membersAsData = members.map { Data(hex: $0) }
        // Create ratchets for all members
        let senderKeys: [ClosedGroupSenderKey] = members.map { publicKey in
            let ratchet = SharedSenderKeys.generateRatchet(for: groupPublicKey, senderPublicKey: publicKey, using: transaction)
            return ClosedGroupSenderKey(chainKey: Data(hex: ratchet.chainKey), keyIndex: ratchet.keyIndex, publicKey: Data(hex: publicKey))
        }
        // Create the group
        let admins = [ userPublicKey ]
        let adminsAsData = admins.map { Data(hex: $0) }
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
        thread.usesSharedSenderKeys = true
        thread.save(with: transaction)
        // Send a closed group update message to all members using established channels
        var promises: [Promise<Void>] = []
        for member in members {
            guard member != userPublicKey else { continue }
            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
            thread.save(with: transaction)
            let closedGroupUpdateKind = ClosedGroupUpdate.Kind.new(groupPublicKey: Data(hex: groupPublicKey), name: name,
                groupPrivateKey: groupKeyPair.privateKey, senderKeys: senderKeys, members: membersAsData, admins: adminsAsData)
            let closedGroupUpdate = ClosedGroupUpdate()
            closedGroupUpdate.kind = closedGroupUpdateKind
            let promise = MessageSender.sendNonDurably(closedGroupUpdate, in: thread, using: transaction)
            promises.append(promise)
        }
        // Add the group to the user's set of public keys to poll for
        Storage.shared.setClosedGroupPrivateKey(groupKeyPair.privateKey.toHexString(), for: groupPublicKey, using: transaction)
        // Notify the PN server
        promises.append(PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: userPublicKey))
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
        // Return
        return when(fulfilled: promises).map2 { thread }
    }

    /// - Note: The returned promise is only relevant for group leaving.
    public static func update(_ groupPublicKey: String, with members: Set<String>, name: String, transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let userPublicKey = getUserHexEncodedPublicKey()
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction) else {
            SNLog("Can't update nonexistent closed group.")
            return Promise(error: Error.noThread)
        }
        let group = thread.groupModel
        let oldMembers = Set(group.groupMemberIds)
        let newMembers = members.subtracting(oldMembers)
        let membersAsData = members.map { Data(hex: $0) }
        let admins = group.groupAdminIds
        let adminsAsData = admins.map { Data(hex: $0) }
        guard let groupPrivateKey = Storage.shared.getClosedGroupPrivateKey(for: groupPublicKey) else {
            SNLog("Couldn't get private key for closed group.")
            return Promise(error: Error.noPrivateKey)
        }
        let wasAnyUserRemoved = Set(members).intersection(oldMembers) != oldMembers
        let removedMembers = oldMembers.subtracting(members)
        let isUserLeaving = removedMembers.contains(userPublicKey)
        var newSenderKeys: [ClosedGroupSenderKey] = []
        if wasAnyUserRemoved {
            if isUserLeaving && removedMembers.count != 1 {
                SNLog("Can't remove self and others simultaneously.")
                return Promise(error: Error.invalidClosedGroupUpdate)
            }
            // Send the update to the existing members using established channels (don't include new ratchets as everyone should regenerate new ratchets individually)
            let promises: [Promise<Void>] = oldMembers.map { member in
                let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                thread.save(with: transaction)
                let closedGroupUpdateKind = ClosedGroupUpdate.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, senderKeys: [],
                    members: membersAsData, admins: adminsAsData)
                let closedGroupUpdate = ClosedGroupUpdate()
                closedGroupUpdate.kind = closedGroupUpdateKind
                return MessageSender.sendNonDurably(closedGroupUpdate, in: thread, using: transaction)
            }
            when(resolved: promises).done2 { _ in seal.fulfill(()) }.catch2 { seal.reject($0) }
            let _ = promise.done {
                Storage.writeSync { transaction in
                    let allOldRatchets = Storage.shared.getAllClosedGroupRatchets(for: groupPublicKey)
                    for (senderPublicKey, oldRatchet) in allOldRatchets {
                        let collection = ClosedGroupRatchetCollectionType.old
                        Storage.shared.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: oldRatchet, in: collection, using: transaction)
                    }
                    // Delete all ratchets (it's important that this happens * after * sending out the update)
                    Storage.shared.removeAllClosedGroupRatchets(for: groupPublicKey, using: transaction)
                    // Remove the group from the user's set of public keys to poll for if the user is leaving. Otherwise generate a new ratchet and
                    // send it out to all members (minus the removed ones) using established channels.
                    if isUserLeaving {
                        Storage.shared.removeClosedGroupPrivateKey(for: groupPublicKey, using: transaction)
                        // Notify the PN server
                        let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
                    } else {
                        // Send closed group update messages to any new members using established channels
                        for member in newMembers {
                            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                            thread.save(with: transaction)
                            let closedGroupUpdateKind = ClosedGroupUpdate.Kind.new(groupPublicKey: Data(hex: groupPublicKey), name: name,
                                groupPrivateKey: Data(hex: groupPrivateKey), senderKeys: [], members: membersAsData, admins: adminsAsData)
                            let closedGroupUpdate = ClosedGroupUpdate()
                            closedGroupUpdate.kind = closedGroupUpdateKind
                            MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
                        }
                        // Send out the user's new ratchet to all members (minus the removed ones) using established channels
                        let userRatchet = SharedSenderKeys.generateRatchet(for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
                        let userSenderKey = ClosedGroupSenderKey(chainKey: Data(hex: userRatchet.chainKey), keyIndex: userRatchet.keyIndex, publicKey: Data(hex: userPublicKey))
                        for member in members {
                            guard member != userPublicKey else { continue }
                            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                            thread.save(with: transaction)
                            let closedGroupUpdateKind = ClosedGroupUpdate.Kind.senderKey(groupPublicKey: Data(hex: groupPublicKey), senderKey: userSenderKey)
                            let closedGroupUpdate = ClosedGroupUpdate()
                            closedGroupUpdate.kind = closedGroupUpdateKind
                            MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
                        }
                    }
                }
            }
        } else if !newMembers.isEmpty {
            seal.fulfill(())
            // Generate ratchets for any new members
            newSenderKeys = newMembers.map { publicKey in
                let ratchet = SharedSenderKeys.generateRatchet(for: groupPublicKey, senderPublicKey: publicKey, using: transaction)
                return ClosedGroupSenderKey(chainKey: Data(hex: ratchet.chainKey), keyIndex: ratchet.keyIndex, publicKey: Data(hex: publicKey))
            }
            // Send a closed group update message to the existing members with the new members' ratchets (this message is aimed at the group)
            let closedGroupUpdateKind = ClosedGroupUpdate.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, senderKeys: newSenderKeys,
                members: membersAsData, admins: adminsAsData)
            let closedGroupUpdate = ClosedGroupUpdate()
            closedGroupUpdate.kind = closedGroupUpdateKind
            MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
            // Send closed group update messages to the new members using established channels
            var allSenderKeys = Storage.shared.getAllClosedGroupSenderKeys(for: groupPublicKey)
            allSenderKeys.formUnion(newSenderKeys)
            for member in newMembers {
                let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                thread.save(with: transaction)
                let closedGroupUpdateKind = ClosedGroupUpdate.Kind.new(groupPublicKey: Data(hex: groupPublicKey), name: name,
                    groupPrivateKey: Data(hex: groupPrivateKey), senderKeys: [ClosedGroupSenderKey](allSenderKeys), members: membersAsData, admins: adminsAsData)
                let closedGroupUpdate = ClosedGroupUpdate()
                closedGroupUpdate.kind = closedGroupUpdateKind
                MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
            }
        } else {
            seal.fulfill(())
            let allSenderKeys = Storage.shared.getAllClosedGroupSenderKeys(for: groupPublicKey)
            let closedGroupUpdateKind = ClosedGroupUpdate.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name,
                senderKeys: [ClosedGroupSenderKey](allSenderKeys), members: membersAsData, admins: adminsAsData)
            let closedGroupUpdate = ClosedGroupUpdate()
            closedGroupUpdate.kind = closedGroupUpdateKind
            MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
        }
        // Update the group
        let newGroupModel = TSGroupModel(title: name, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user
        let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate, customMessage: updateInfo)
        infoMessage.save(with: transaction)
        // Return
        return promise
    }

    /// The returned promise is fulfilled when the group update message has been sent. It doesn't wait for the user's new ratchet to be distributed.
    @objc(leaveGroupWithPublicKey:transaction:)
    public static func objc_leave(_ groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(leave(groupPublicKey, using: transaction))
    }

    /// The returned promise is fulfilled when the group update message has been sent. It doesn't wait for the user's new ratchet to be distributed.
    public static func leave(_ groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        let userPublicKey = getUserHexEncodedPublicKey()
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction) else {
            SNLog("Can't leave nonexistent closed group.")
            return Promise(error: Error.noThread)
        }
        let group = thread.groupModel
        var newMembers = Set(group.groupMemberIds)
        newMembers.remove(userPublicKey)
        return update(groupPublicKey, with: newMembers, name: group.groupName!, transaction: transaction)
    }
    
    public func requestSenderKey(for groupPublicKey: String, senderPublicKey: String, using transaction: Any) { // FIXME: This should be static
        SNLog("Requesting sender key for group public key: \(groupPublicKey), sender public key: \(senderPublicKey).")
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let thread = TSContactThread.getOrCreateThread(withContactId: senderPublicKey, transaction: transaction)
        thread.save(with: transaction)
        let closedGroupUpdateKind = ClosedGroupUpdate.Kind.senderKeyRequest(groupPublicKey: Data(hex: groupPublicKey))
        let closedGroupUpdate = ClosedGroupUpdate()
        closedGroupUpdate.kind = closedGroupUpdateKind
        MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
    }
}
