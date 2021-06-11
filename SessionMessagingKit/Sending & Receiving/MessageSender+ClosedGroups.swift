import PromiseKit

extension MessageSender {
    public static var distributingClosedGroupEncryptionKeyPairs: [String:[ECKeyPair]] = [:]
    
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
            let thread = TSContactThread.getOrCreateThread(withContactSessionID: member, transaction: transaction)
            thread.save(with: transaction)
            let closedGroupControlMessageKind = ClosedGroupControlMessage.Kind.new(publicKey: Data(hex: groupPublicKey), name: name,
                encryptionKeyPair: encryptionKeyPair, members: membersAsData, admins: adminsAsData, expirationTimer: 0)
            let closedGroupControlMessage = ClosedGroupControlMessage(kind: closedGroupControlMessageKind)
            // Sending this non-durably is okay because we show a loader to the user. If they close the app while the
            // loader is still showing, it's within expectation that the group creation might be incomplete.
            let promise = MessageSender.sendNonDurably(closedGroupControlMessage, in: thread, using: transaction)
            promises.append(promise)
        }
        // Add the group to the user's set of public keys to poll for
        Storage.shared.addClosedGroupPublicKey(groupPublicKey, using: transaction)
        // Store the key pair
        Storage.shared.addClosedGroupEncryptionKeyPair(encryptionKeyPair, for: groupPublicKey, using: transaction)
        // Notify the PN server
        promises.append(PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: userPublicKey))
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .groupCreated)
        infoMessage.save(with: transaction)
        // Start polling
        ClosedGroupPoller.shared.startPolling(for: groupPublicKey)
        // Return
        return when(fulfilled: promises).map2 { thread }
    }

    /// Generates and distributes a new encryption key pair for the group with the given `groupPublicKey`. This sends a `ENCRYPTION_KEY_PAIR` message to the group. The
    /// message contains a list of key pair wrappers. Each key pair wrapper consists of the public key for which the wrapper is intended along with the newly generated key pair
    /// encrypted for that public key.
    ///
    /// The returned promise is fulfilled when the message has been sent to the group.
    public static func generateAndSendNewEncryptionKeyPair(for groupPublicKey: String, to targetMembers: Set<String>, using transaction: Any) -> Promise<Void> {
        // Prepare
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't distribute new encryption key pair for nonexistent closed group.")
            return Promise(error: Error.noThread)
        }
        guard thread.groupModel.groupAdminIds.contains(getUserHexEncodedPublicKey()) else {
            SNLog("Can't distribute new encryption key pair as a non-admin.")
            return Promise(error: Error.invalidClosedGroupUpdate)
        }
        // Generate the new encryption key pair
        let newKeyPair = Curve25519.generateKeyPair()
        // Distribute it
        let proto = try! SNProtoKeyPair.builder(publicKey: newKeyPair.publicKey,
            privateKey: newKeyPair.privateKey).build()
        let plaintext = try! proto.serializedData()
        let wrappers = targetMembers.compactMap { publicKey -> ClosedGroupControlMessage.KeyPairWrapper in
            let ciphertext = try! MessageSender.encryptWithSessionProtocol(plaintext, for: publicKey)
            return ClosedGroupControlMessage.KeyPairWrapper(publicKey: publicKey, encryptedKeyPair: ciphertext)
        }
        let closedGroupControlMessage = ClosedGroupControlMessage(kind: .encryptionKeyPair(publicKey: nil, wrappers: wrappers))
        var distributingKeyPairs = distributingClosedGroupEncryptionKeyPairs[groupPublicKey] ?? []
        distributingKeyPairs.append(newKeyPair)
        distributingClosedGroupEncryptionKeyPairs[groupPublicKey] = distributingKeyPairs
        return MessageSender.sendNonDurably(closedGroupControlMessage, in: thread, using: transaction).done {
            // Store it * after * having sent out the message to the group
            SNMessagingKitConfiguration.shared.storage.write { transaction in
                Storage.shared.addClosedGroupEncryptionKeyPair(newKeyPair, for: groupPublicKey, using: transaction)
            }
            var distributingKeyPairs = distributingClosedGroupEncryptionKeyPairs[groupPublicKey] ?? []
            if let index = distributingKeyPairs.firstIndex(of: newKeyPair) {
                distributingKeyPairs.remove(at: index)
            }
            distributingClosedGroupEncryptionKeyPairs[groupPublicKey] = distributingKeyPairs
        }.map { _ in }
    }
    
    public static func update(_ groupPublicKey: String, with members: Set<String>, name: String, transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        // Get the group, check preconditions & prepare
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't update nonexistent closed group.")
            return Promise(error: Error.noThread)
        }
        let group = thread.groupModel
        var promises: [Promise<Void>] = []
        let zombies = SNMessagingKitConfiguration.shared.storage.getZombieMembers(for: groupPublicKey)
        // Update name if needed
        if name != group.groupName { promises.append(setName(to: name, for: groupPublicKey, using: transaction)) }
        // Add members if needed
        let addedMembers = members.subtracting(group.groupMemberIds + zombies)
        if !addedMembers.isEmpty { promises.append(addMembers(addedMembers, to: groupPublicKey, using: transaction)) }
        // Remove members if needed
        let removedMembers = Set(group.groupMemberIds + zombies).subtracting(members)
        if !removedMembers.isEmpty{ promises.append(removeMembers(removedMembers, to: groupPublicKey, using: transaction)) }
        // Return
        return when(fulfilled: promises).map2 { _ in }
    }
    
    /// Sets the name to `name` for the group with the given `groupPublicKey`. This sends a `NAME_CHANGE` message to the group.
    public static func setName(to name: String, for groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        // Get the group, check preconditions & prepare
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't change name for nonexistent closed group.")
            return Promise(error: Error.noThread)
        }
        guard !name.isEmpty else {
            SNLog("Can't set closed group name to an empty value.")
            return Promise(error: Error.invalidClosedGroupUpdate)
        }
        let group = thread.groupModel
        // Send the update to the group
        let closedGroupControlMessage = ClosedGroupControlMessage(kind: .nameChange(name: name))
        MessageSender.send(closedGroupControlMessage, in: thread, using: transaction)
        // Update the group
        let newGroupModel = TSGroupModel(title: name, memberIds: group.groupMemberIds, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user
        let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .groupUpdated, customMessage: updateInfo)
        infoMessage.save(with: transaction)
        // Return
        return Promise.value(())
    }
    
    /// Adds `newMembers` to the group with the given `groupPublicKey`. This sends a `MEMBERS_ADDED` message to the group, and a
    /// `NEW` message to the members that were added (using one-on-one channels).
    public static func addMembers(_ newMembers: Set<String>, to groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        // Get the group, check preconditions & prepare
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't add members to nonexistent closed group.")
            return Promise(error: Error.noThread)
        }
        guard !newMembers.isEmpty else {
            SNLog("Invalid closed group update.")
            return Promise(error: Error.invalidClosedGroupUpdate)
        }
        let group = thread.groupModel
        let members = [String](Set(group.groupMemberIds).union(newMembers))
        let membersAsData = members.map { Data(hex: $0) }
        let adminsAsData = group.groupAdminIds.map { Data(hex: $0) }
        let expirationTimer = thread.disappearingMessagesDuration(with: transaction)
        guard let encryptionKeyPair = Storage.shared.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else {
            SNLog("Couldn't find encryption key pair for closed group: \(groupPublicKey).")
            return Promise(error: Error.noKeyPair)
        }
        // Send the update to the group
        let closedGroupControlMessage = ClosedGroupControlMessage(kind: .membersAdded(members: newMembers.map { Data(hex: $0) }))
        MessageSender.send(closedGroupControlMessage, in: thread, using: transaction)
        // Send updates to the new members individually
        for member in newMembers {
            let thread = TSContactThread.getOrCreateThread(withContactSessionID: member, transaction: transaction)
            thread.save(with: transaction)
            let closedGroupControlMessageKind = ClosedGroupControlMessage.Kind.new(publicKey: Data(hex: groupPublicKey), name: group.groupName!,
                encryptionKeyPair: encryptionKeyPair, members: membersAsData, admins: adminsAsData, expirationTimer: expirationTimer)
            let closedGroupControlMessage = ClosedGroupControlMessage(kind: closedGroupControlMessageKind)
            MessageSender.send(closedGroupControlMessage, in: thread, using: transaction)
        }
        // Update the group
        let newGroupModel = TSGroupModel(title: group.groupName, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user
        let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .groupUpdated, customMessage: updateInfo)
        infoMessage.save(with: transaction)
        // Return
        return Promise.value(())
    }
    
    /// Removes `membersToRemove` from the group with the given `groupPublicKey`. Only the admin can remove members, and when they do
    /// they generate and distribute a new encryption key pair for the group. A member cannot leave a group using this method. For that they should use
    /// `leave(:using:)`.
    ///
    /// The returned promise is fulfilled when the `MEMBERS_REMOVED` message has been sent to the group AND the new encryption key pair has been
    /// generated and distributed.
    public static func removeMembers(_ membersToRemove: Set<String>, to groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        // Get the group, check preconditions & prepare
        let userPublicKey = getUserHexEncodedPublicKey()
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        let storage = SNMessagingKitConfiguration.shared.storage
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't remove members from nonexistent closed group.")
            return Promise(error: Error.noThread)
        }
        guard !membersToRemove.isEmpty else {
            SNLog("Invalid closed group update.")
            return Promise(error: Error.invalidClosedGroupUpdate)
        }
        guard !membersToRemove.contains(userPublicKey) else {
            SNLog("Invalid closed group update.")
            return Promise(error: Error.invalidClosedGroupUpdate)
        }
        let group = thread.groupModel
        guard group.groupAdminIds.contains(userPublicKey) else {
            SNLog("Only an admin can remove members from a group.")
            return Promise(error: Error.invalidClosedGroupUpdate)
        }
        let members = Set(group.groupMemberIds).subtracting(membersToRemove)
        // Update zombie list
        let oldZombies = storage.getZombieMembers(for: groupPublicKey)
        let newZombies = oldZombies.subtracting(membersToRemove)
        storage.setZombieMembers(for: groupPublicKey, to: newZombies, using: transaction)
        // Send the update to the group and generate + distribute a new encryption key pair
        let closedGroupControlMessage = ClosedGroupControlMessage(kind: .membersRemoved(members: membersToRemove.map { Data(hex: $0) }))
        let promise = MessageSender.sendNonDurably(closedGroupControlMessage, in: thread, using: transaction).map {
            generateAndSendNewEncryptionKeyPair(for: groupPublicKey, to: members, using: transaction)
        }.map { _ in }
        // Update the group
        let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user if needed (not if only zombie members were removed)
        if !membersToRemove.subtracting(oldZombies).isEmpty {
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .groupUpdated, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
        // Return
        return promise
    }
    
    @objc(leaveClosedGroupWithPublicKey:using:)
    public static func objc_leave(_ groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(leave(groupPublicKey, using: transaction))
    }
    
    /// Leave the group with the given `groupPublicKey`. If the current user is the admin, the group is disbanded entirely. If the user is a regular
    /// member they'll be marked as a "zombie" member by the other users in the group (upon receiving the leave message). The admin can then truly
    /// remove them later.
    ///
    /// This function also removes all encryption key pairs associated with the closed group and the group's public key, and unregisters from push notifications.
    ///
    /// The returned promise is fulfilled when the `MEMBER_LEFT` message has been sent to the group.
    public static func leave(_ groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        // Get the group, check preconditions & prepare
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't leave nonexistent closed group.")
            return Promise(error: Error.noThread)
        }
        let group = thread.groupModel
        let userPublicKey = getUserHexEncodedPublicKey()
        let isCurrentUserAdmin = group.groupAdminIds.contains(userPublicKey)
        let members: Set<String> = isCurrentUserAdmin ? [] : Set(group.groupMemberIds).subtracting([ userPublicKey ]) // If the admin leaves the group is disbanded
        let admins: Set<String> = isCurrentUserAdmin ? [] : Set(group.groupAdminIds)
        // Send the update to the group
        let closedGroupControlMessage = ClosedGroupControlMessage(kind: .memberLeft)
        let promise = MessageSender.sendNonDurably(closedGroupControlMessage, in: thread, using: transaction).done {
            SNMessagingKitConfiguration.shared.storage.write { transaction in
                // Remove the group from the database and unsubscribe from PNs
                Storage.shared.removeAllClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
                Storage.shared.removeClosedGroupPublicKey(groupPublicKey, using: transaction)
                ClosedGroupPoller.shared.stopPolling(for: groupPublicKey)
                let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
            }
        }.map { _ in }
        // Update the group
        let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: [String](admins))
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user
        let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .groupCurrentUserLeft, customMessage: updateInfo)
        infoMessage.save(with: transaction)
        // Return
        return promise
    }
    
    /*
    public static func requestEncryptionKeyPair(for groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) throws {
        #if DEBUG
        preconditionFailure("Shouldn't currently be in use.")
        #endif
        // Get the group, check preconditions & prepare
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            SNLog("Can't request encryption key pair for nonexistent closed group.")
            throw Error.noThread
        }
        let group = thread.groupModel
        guard group.groupMemberIds.contains(getUserHexEncodedPublicKey()) else { return }
        // Send the request to the group
        let closedGroupControlMessage = ClosedGroupControlMessage(kind: .encryptionKeyPairRequest)
        MessageSender.send(closedGroupControlMessage, in: thread, using: transaction)
    }
     */
    
    public static func sendLatestEncryptionKeyPair(to publicKey: String, for groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        // Check that the user in question is part of the closed group
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let groupThread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            return SNLog("Couldn't send key pair for nonexistent closed group.")
        }
        let group = groupThread.groupModel
        guard group.groupMemberIds.contains(publicKey) else {
            return SNLog("Refusing to send latest encryption key pair to non-member.")
        }
        // Get the latest encryption key pair
        guard let encryptionKeyPair = distributingClosedGroupEncryptionKeyPairs[groupPublicKey]?.last
            ?? Storage.shared.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else { return }
        // Send it
        guard let proto = try? SNProtoKeyPair.builder(publicKey: encryptionKeyPair.publicKey,
            privateKey: encryptionKeyPair.privateKey).build(), let plaintext = try? proto.serializedData() else { return }
        let contactThread = TSContactThread.getOrCreateThread(withContactSessionID: publicKey, transaction: transaction)
        guard let ciphertext = try? MessageSender.encryptWithSessionProtocol(plaintext, for: publicKey) else { return }
        SNLog("Sending latest encryption key pair to: \(publicKey).")
        let wrapper = ClosedGroupControlMessage.KeyPairWrapper(publicKey: publicKey, encryptedKeyPair: ciphertext)
        let closedGroupControlMessage = ClosedGroupControlMessage(kind: .encryptionKeyPair(publicKey: Data(hex: groupPublicKey), wrappers: [ wrapper ]))
        MessageSender.send(closedGroupControlMessage, in: contactThread, using: transaction)
    }
}
