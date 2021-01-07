import PromiseKit
import SessionProtocolKit

extension MessageSender : SharedSenderKeysDelegate {

    // MARK: - V2

    public static func createV2ClosedGroup(name: String, members: Set<String>, transaction: YapDatabaseReadWriteTransaction) -> Promise<TSGroupThread> {
        // Prepare
        var members = members
        let userPublicKey = getUserHexEncodedPublicKey()
        // Generate the group's public key
        let groupPublicKey = Curve25519.generateKeyPair().hexEncodedPublicKey // Includes the "05" prefix
        // Generate the key pair that'll be used for encryption and decryption
        let encryptionKeyPair = Curve25519.generateKeyPair()
        // Ensure the current user is included in the member list
        members.insert(userPublicKey)
        let membersAsData = members.map { Data(hex: $0) }
        // Create the group
        let admins = [ userPublicKey ]
        let adminsAsData = admins.map { Data(hex: $0) }
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
        thread.usesSharedSenderKeys = true // TODO: We should be able to safely deprecate this
        thread.save(with: transaction)
        // Send a closed group update message to all members individually
        var promises: [Promise<Void>] = []
        for member in members {
            guard member != userPublicKey else { continue }
            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
            thread.save(with: transaction)
            let closedGroupUpdateKind = ClosedGroupUpdateV2.Kind.new(publicKey: Data(hex: groupPublicKey), name: name,
                encryptionKeyPair: encryptionKeyPair, members: membersAsData, admins: adminsAsData)
            let closedGroupUpdate = ClosedGroupUpdateV2(kind: closedGroupUpdateKind)
            let promise = MessageSender.sendNonDurably(closedGroupUpdate, in: thread, using: transaction)
            promises.append(promise)
        }
        // Add the group to the user's set of public keys to poll for
        Storage.shared.addClosedGroupPublicKey(groupPublicKey, using: transaction)
        Storage.shared.addClosedGroupEncryptionKeyPair(encryptionKeyPair, for: groupPublicKey, using: transaction)
        // Notify the PN server
        promises.append(PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: userPublicKey))
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
        // Return
        return when(fulfilled: promises).map2 { thread }
    }
    
    public static func updateV2(_ groupPublicKey: String, with members: Set<String>, name: String, transaction: YapDatabaseReadWriteTransaction) throws {
        // Prepare
        let userPublicKey = getUserHexEncodedPublicKey()
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't update nonexistent closed group.")
            throw Error.noThread
        }
        let group = thread.groupModel
        let oldMembers = Set(group.groupMemberIds)
        let newMembers = members.subtracting(oldMembers)
        let membersAsData = members.map { Data(hex: $0) }
        let admins = group.groupAdminIds
        let adminsAsData = admins.map { Data(hex: $0) }
        guard let encryptionKeyPair = Storage.shared.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else {
            SNLog("Couldn't get key pair for closed group.")
            throw Error.noKeyPair
        }
        let removedMembers = oldMembers.subtracting(members)
        guard !removedMembers.contains(admins.first!) else {
            SNLog("Can't remove admin from closed group.")
            throw Error.invalidClosedGroupUpdate
        }
        let isUserLeaving = removedMembers.contains(userPublicKey)
        if isUserLeaving && (removedMembers.count != 1 || !newMembers.isEmpty) {
            SNLog("Can't remove self and add or remove others simultaneously.")
            throw Error.invalidClosedGroupUpdate
        }
        // Send the update to the group
        let mainClosedGroupUpdate = ClosedGroupUpdateV2(kind: .update(name: name, members: membersAsData))
        if isUserLeaving {
            let _ = MessageSender.sendNonDurably(mainClosedGroupUpdate, in: thread, using: transaction).done {
                SNMessagingKitConfiguration.shared.storage.write { transaction in
                    // Remove the group private key and unsubscribe from PNs
                    Storage.shared.removeAllClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
                    Storage.shared.removeClosedGroupPublicKey(groupPublicKey, using: transaction)
                    let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
                }
            }
        } else {
            MessageSender.send(mainClosedGroupUpdate, in: thread, using: transaction)
            // Generate and distribute a new encryption key pair if needed
            let wasAnyUserRemoved = !removedMembers.isEmpty
            let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
            if wasAnyUserRemoved && isCurrentUserAdmin {
                try generateAndSendNewEncryptionKeyPair(for: groupPublicKey, to: members.subtracting(newMembers), using: transaction)
            }
            // Send closed group update messages to any new members individually
            for member in newMembers {
                let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                thread.save(with: transaction)
                let closedGroupUpdateKind = ClosedGroupUpdateV2.Kind.new(publicKey: Data(hex: groupPublicKey), name: name,
                    encryptionKeyPair: encryptionKeyPair, members: membersAsData, admins: adminsAsData)
                let closedGroupUpdate = ClosedGroupUpdateV2(kind: closedGroupUpdateKind)
                MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
            }
        }
        // Update the group
        let newGroupModel = TSGroupModel(title: name, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user
        let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate, customMessage: updateInfo)
        infoMessage.save(with: transaction)
    }
    
    public static func leaveV2(_ groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) throws {
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't leave nonexistent closed group.")
            throw Error.noThread
        }
        let group = thread.groupModel
        var newMembers = Set(group.groupMemberIds)
        newMembers.remove(getUserHexEncodedPublicKey())
        return try updateV2(groupPublicKey, with: newMembers, name: group.groupName!, transaction: transaction)
    }

    public static func generateAndSendNewEncryptionKeyPair(for groupPublicKey: String, to targetMembers: Set<String>, using transaction: Any) throws {
        // Prepare
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't distribute new encryption key pair for nonexistent closed group.")
            throw Error.noThread
        }
        guard thread.groupModel.groupAdminIds.contains(getUserHexEncodedPublicKey()) else {
            SNLog("Can't distribute new encryption key pair as a non-admin.")
            throw Error.invalidClosedGroupUpdate
        }
        // Generate the new encryption key pair
        let newKeyPair = Curve25519.generateKeyPair()
        // Distribute it
        let proto = try SNProtoDataMessageClosedGroupUpdateV2KeyPair.builder(publicKey: newKeyPair.publicKey,
            privateKey: newKeyPair.privateKey).build()
        let plaintext = try proto.serializedData()
        let wrappers = try targetMembers.compactMap { publicKey -> ClosedGroupUpdateV2.KeyPairWrapper in
            let ciphertext = try MessageSender.encryptWithSessionProtocol(plaintext, for: publicKey)
            return ClosedGroupUpdateV2.KeyPairWrapper(publicKey: publicKey, encryptedKeyPair: ciphertext)
        }
        let closedGroupUpdate = ClosedGroupUpdateV2(kind: .encryptionKeyPair(wrappers))
        let _ = MessageSender.sendNonDurably(closedGroupUpdate, in: thread, using: transaction).done { // FIXME: It'd be great if we could make this a durable operation
            // Store it * after * having sent out the message to the group
            SNMessagingKitConfiguration.shared.storage.write { transaction in
                Storage.shared.addClosedGroupEncryptionKeyPair(newKeyPair, for: groupPublicKey, using: transaction)
            }
        }
    }
    

    
    // MARK: - V1
    
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
            return Promise(error: Error.noKeyPair)
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
                SNMessagingKitConfiguration.shared.storage.writeSync { transaction in
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
                            let transaction = transaction as! YapDatabaseReadWriteTransaction
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
                            let transaction = transaction as! YapDatabaseReadWriteTransaction
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
