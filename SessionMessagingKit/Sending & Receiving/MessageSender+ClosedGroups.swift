import PromiseKit
import SessionProtocolKit

extension MessageSender {

    public static func createClosedGroup(name: String, members: Set<String>, transaction: YapDatabaseReadWriteTransaction) -> Promise<TSGroupThread> {
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
        // Store the key pair
        Storage.shared.addClosedGroupEncryptionKeyPair(encryptionKeyPair, for: groupPublicKey, using: transaction)
        // Notify the PN server
        promises.append(PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: userPublicKey))
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
        // Return
        return when(fulfilled: promises).map2 { thread }
    }
    
    public static func update(_ groupPublicKey: String, with members: Set<String>, name: String, transaction: YapDatabaseReadWriteTransaction) throws {
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
        let removedMembers = oldMembers.subtracting(members)
        let admins = group.groupAdminIds
        let adminsAsData = admins.map { Data(hex: $0) }
        let isUserLeaving = !members.contains(userPublicKey)
        let wasAnyUserRemoved = !removedMembers.isEmpty
        let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
        // Check preconditions
        guard let encryptionKeyPair = Storage.shared.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else {
            SNLog("Couldn't get key pair for closed group.")
            throw Error.noKeyPair
        }
        if removedMembers.contains(admins.first!) && !members.isEmpty {
            SNLog("Can't remove admin from closed group without removing everyone.")
            throw Error.invalidClosedGroupUpdate
        }
        if isUserLeaving && !members.isEmpty {
            guard removedMembers.count == 1 && newMembers.isEmpty else {
                SNLog("Can't remove self and add or remove others simultaneously.")
                throw Error.invalidClosedGroupUpdate
            }
        }
        // Send the update to the group
        let mainClosedGroupUpdate = ClosedGroupUpdateV2(kind: .update(name: name, members: membersAsData))
        if isUserLeaving {
            let _ = MessageSender.sendNonDurably(mainClosedGroupUpdate, in: thread, using: transaction).done {
                SNMessagingKitConfiguration.shared.storage.write { transaction in
                    // Remove the group from the database and unsubscribe from PNs
                    Storage.shared.removeAllClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
                    Storage.shared.removeClosedGroupPublicKey(groupPublicKey, using: transaction)
                    let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
                }
            }
        } else {
            MessageSender.send(mainClosedGroupUpdate, in: thread, using: transaction)
            // Generate and distribute a new encryption key pair if needed
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

    @objc(leaveClosedGroupWithPublicKey:using:error:)
    public static func leave(_ groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) throws {
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't leave nonexistent closed group.")
            throw Error.noThread
        }
        let group = thread.groupModel
        let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
        var newMembers: Set<String>
        if !isCurrentUserAdmin {
            newMembers = Set(group.groupMemberIds)
            newMembers.remove(getUserHexEncodedPublicKey())
        } else {
            newMembers = [] // If the admin leaves the group is destroyed
        }
        return try update(groupPublicKey, with: newMembers, name: group.groupName!, transaction: transaction)
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
        let proto = try SNProtoKeyPair.builder(publicKey: newKeyPair.publicKey,
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
}
