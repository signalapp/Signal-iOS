import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • For write transactions, consider making it the caller's responsibility to manage the database transaction (this helps avoid unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases in which a function will be used.
// • Express those cases in tests.

/// See [the documentation](https://github.com/loki-project/session-protocol-docs/wiki/Medium-Size-Groups) for more information.
@objc(LKClosedGroupsProtocol)
public final class ClosedGroupsProtocol : NSObject {

    /// - Note: It's recommended to batch fetch the device links for the given set of members before invoking this, to avoid
    /// the message sending pipeline making a request for each member.
    public static func createClosedGroup(name: String, members membersAsSet: Set<String>, transaction: YapDatabaseReadWriteTransaction) -> TSGroupThread {
        var membersAsSet = membersAsSet
        let userPublicKey = getUserHexEncodedPublicKey()
        // Generate a key pair for the group
        let groupKeyPair = Curve25519.generateKeyPair()
        let groupPublicKey = groupKeyPair.hexEncodedPublicKey
        // Ensure the current user's master device is included in the member list
        membersAsSet.remove(userPublicKey)
        membersAsSet.insert(UserDefaults.standard[.masterHexEncodedPublicKey] ?? userPublicKey)
        // Create ratchets for all users involved
        let members = [String](membersAsSet)
        let ratchets = members.map {
            SharedSenderKeysImplementation.shared.generateRatchet(for: groupPublicKey, senderPublicKey: $0, using: transaction)
        }
        // Create the group
        let admins = [ UserDefaults.standard[.masterHexEncodedPublicKey] ?? userPublicKey ]
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
        thread.usesSharedSenderKeys = true
        thread.save(with: transaction)
        SSKEnvironment.shared.profileManager.addThread(toProfileWhitelist: thread)
        // Send a closed group update message to all members involved
        let chainKeys = ratchets.map { Data(hex: $0.chainKey) }
        for member in members {
            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
            thread.save(with: transaction)
            let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.new(groupPublicKey: Data(hex: groupPublicKey), name: name, groupPrivateKey: groupKeyPair.privateKey, chainKeys: chainKeys, members: members, admins: admins)
            let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
            let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
            messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        }
        // Store the group's key pair
        Storage.setClosedGroupPrivateKey(groupKeyPair.privateKey.toHexString(), for: groupPublicKey, using: transaction)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
        // The user can only pick from existing contacts when selecting closed group
        // members so there's no need to establish sessions
        // Return
        return thread
    }

    public static func addUser(_ publicKey: String, to groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        // Prepare
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        let groupID = LKGroupUtilities.getEncodedClosedGroupID(groupPublicKey)
        guard let thread1 = TSGroupThread.fetch(uniqueId: groupID, transaction: transaction) else {
            return print("[Loki] Can't add user to nonexistent closed group.")
        }
        let group = thread1.groupModel
        let name = group.groupName!
        let admins = group.groupAdminIds
        // Add the user
        var members = group.groupMemberIds
        members.append(publicKey)
        // Establish sessions if needed (it's important that this happens before the code below)
        establishSessionsIfNeeded(with: members, using: transaction)
        // Generate a ratchet for the new member
        let ratchet = SharedSenderKeysImplementation.shared.generateRatchet(for: groupPublicKey, senderPublicKey: publicKey, using: transaction)
        let chainKey = Data(hex: ratchet.chainKey)
        // Send the update to the group
        let closedGroupUpdateMessageKind1 = ClosedGroupUpdateMessage.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, chainKeys: [ chainKey ], members: members, admins: admins)
        let closedGroupUpdateMessage1 = ClosedGroupUpdateMessage(thread: thread1, kind: closedGroupUpdateMessageKind1)
        messageSenderJobQueue.add(message: closedGroupUpdateMessage1, transaction: transaction)
        // Notify the added user
        let allChainKeys = Storage.getAllClosedGroupRatchets(for: groupPublicKey).map { Data(hex: $0.chainKey) } + [ chainKey ] // TODO: I think we need to include the key index here as well
        let closedGroupUpdateMessageKind2 = ClosedGroupUpdateMessage.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, chainKeys: allChainKeys, members: members, admins: admins)
        let thread2 = TSContactThread.getOrCreateThread(contactId: publicKey)
        thread2.save(with: transaction)
        let closedGroupUpdateMessage2 = ClosedGroupUpdateMessage(thread: thread2, kind: closedGroupUpdateMessageKind2)
        messageSenderJobQueue.add(message: closedGroupUpdateMessage2, transaction: transaction)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread1, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
    }

    public static func removeUser(_ publicKey: String, from groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        // Prepare
        let groupID = LKGroupUtilities.getEncodedClosedGroupID(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: groupID, transaction: transaction) else {
            return print("[Loki] Can't remove user from nonexistent closed group.")
        }
        let group = thread.groupModel
        let name = group.groupName!
        let admins = group.groupAdminIds
        // Remove the user
        var members = group.groupMemberIds
        guard let indexOfUser = members.firstIndex(of: publicKey) else {
            return print("[Loki] Can't remove user from group.")
        }
        members.remove(at: indexOfUser)
        // Establish sessions if needed (it's important that this happens before the code below)
        establishSessionsIfNeeded(with: members, using: transaction)
        // Generate new ratchets for everyone except the member that was removed
        let ratchets = members.map {
            SharedSenderKeysImplementation.shared.generateRatchet(for: groupPublicKey, senderPublicKey: $0, using: transaction)
        }
        let chainKeys = ratchets.map { Data(hex: $0.chainKey) }
        // Send a closed group update message to all members involved
        for member in members {
            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
            thread.save(with: transaction)
            let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, chainKeys: chainKeys, members: members, admins: admins)
            let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
            let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
            messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        }
        // Notify the removed user
        SessionManagementProtocol.establishSessionIfNeeded(with: publicKey, using: transaction)
        let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, chainKeys: [], members: members, admins: admins)
        let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
    }

    public static func leave(_ groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        // Prepare
        let groupID = LKGroupUtilities.getEncodedClosedGroupID(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: groupID, transaction: transaction) else {
            return print("[Loki] Can't leave nonexistent closed group.")
        }
        let group = thread.groupModel
        let name = group.groupName!
        // Leave the group
        var members = group.groupMemberIds
        guard let indexOfSelf = members.firstIndex(of: getUserHexEncodedPublicKey()) else {
            return print("[Loki] Can't leave group.")
        }
        members.remove(at: indexOfSelf)
        let admins = group.groupAdminIds
        // Send the update to the group (don't include new ratchets as everyone should generate new ratchets
        // individually in this case)
        let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, chainKeys: [], members: members, admins: admins)
        let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        // Delete all ratchets
        Storage.removeAllClosedGroupRatchets(for: groupPublicKey, using: transaction)
    }

    @objc(handleSharedSenderKeysUpdateIfNeeded:from:transaction:)
    public static func handleSharedSenderKeysUpdateIfNeeded(_ dataMessage: SSKProtoDataMessage, from publicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        // Note that `publicKey` is either the public key of the group or the public key of the
        // sender, depending on how the message was sent
        guard let closedGroupUpdate = dataMessage.closedGroupUpdate else { return }
        switch closedGroupUpdate.type {
        case .new: handleNewGroupMessage(closedGroupUpdate, using: transaction)
        case .info: handleInfoMessage(closedGroupUpdate, using: transaction)
        case .chainKey: handleChainKeyMessage(closedGroupUpdate, from: publicKey, using: transaction)
        }
    }

    private static func handleNewGroupMessage(_ closedGroupUpdate: SSKProtoDataMessageClosedGroupUpdate, using transaction: YapDatabaseReadWriteTransaction) {
        // Unwrap the message
        let groupPublicKey = closedGroupUpdate.groupPublicKey.toHexString()
        let name = closedGroupUpdate.name
        let groupPrivateKey = closedGroupUpdate.groupPrivateKey!
        let chainKeys = closedGroupUpdate.chainKeys
        let members = closedGroupUpdate.members
        let admins = closedGroupUpdate.admins
        // Persist the ratchets
        zip(members, chainKeys).forEach { (member, chainKey) in
            let ratchet = ClosedGroupRatchet(chainKey: chainKey.toHexString(), keyIndex: 0, messageKeys: [])
            Storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: member, ratchet: ratchet, using: transaction)
        }
        // Create the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
        thread.usesSharedSenderKeys = true
        thread.save(with: transaction)
        SSKEnvironment.shared.profileManager.addThread(toProfileWhitelist: thread)
        // Add the group to the user's set of public keys to poll for
        Storage.setClosedGroupPrivateKey(groupPrivateKey.toHexString(), for: groupPublicKey, using: transaction)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
        // Establish sessions if needed
        establishSessionsIfNeeded(with: members, using: transaction)
    }

    /// Invoked upon receiving a group update. A group update is sent out when a group's name is changed, when new users
    /// are added, when users leave or are kicked, or if the group admins are changed.
    private static func handleInfoMessage(_ closedGroupUpdate: SSKProtoDataMessageClosedGroupUpdate, using transaction: YapDatabaseReadWriteTransaction) {
        // TODO: Check that the sender was an admin
        // Unwrap the message
        let groupPublicKey = closedGroupUpdate.groupPublicKey.toHexString()
        let name = closedGroupUpdate.name
        let chainKeys = closedGroupUpdate.chainKeys
        let members = closedGroupUpdate.members
        let admins = closedGroupUpdate.admins
        // Get the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupID(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: groupID, transaction: transaction) else {
            return print("[Loki] Ignoring closed group update for nonexistent group.")
        }
        let group = thread.groupModel
        // Establish sessions if needed (it's important that this happens before the code below)
        establishSessionsIfNeeded(with: members, using: transaction)
        // Parse out any new members and store their ratchets (it's important that
        // this happens before handling removed members)
        let oldMembers = group.groupMemberIds
        let newMembers = members.filter { !oldMembers.contains($0) }
        if newMembers.count == chainKeys.count { // If someone was kicked the message won't have any chain keys
            zip(newMembers, chainKeys).forEach { (member, chainKey) in
                let ratchet = ClosedGroupRatchet(chainKey: chainKey.toHexString(), keyIndex: 0, messageKeys: [])
                Storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: member, ratchet: ratchet, using: transaction)
            }
        }
        // Delete all ratchets and send out the user's new ratchet using established
        // channels if any member of the group left or was removed
        if Set(members).intersection(oldMembers) != Set(oldMembers) {
            Storage.removeAllClosedGroupRatchets(for: groupPublicKey, using: transaction)
            let userPublicKey = getUserHexEncodedPublicKey()
            let newRatchet = SharedSenderKeysImplementation.shared.generateRatchet(for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
            Storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: userPublicKey, ratchet: newRatchet, using: transaction)
            for member in members {
                let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                thread.save(with: transaction)
                let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.chainKey(groupPublicKey: Data(hex: groupPublicKey), chainKey: Data(hex: newRatchet.chainKey))
                let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
                let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
                messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
            }
        }
        // Update the group
        let groupIDAsData = groupID.data(using: String.Encoding.utf8)!
        let newGroupModel = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupIDAsData, groupType: .closedGroup, adminIds: admins)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
    }

    /// Invoked upon receiving a chain key from another user.
    private static func handleChainKeyMessage(_ closedGroupUpdate: SSKProtoDataMessageClosedGroupUpdate, from senderPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        let groupPublicKey = closedGroupUpdate.groupPublicKey.toHexString()
        guard let chainKey = closedGroupUpdate.chainKeys.first else {
            return print("[Loki] Ignoring invalid closed group update.")
        }
        let ratchet = ClosedGroupRatchet(chainKey: chainKey.toHexString(), keyIndex: 0, messageKeys: [])
        Storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: ratchet, using: transaction)
    }

    @objc(establishSessionsIfNeededWithClosedGroupMembers:transaction:)
    public static func establishSessionsIfNeeded(with closedGroupMembers: [String], using transaction: YapDatabaseReadWriteTransaction) {
        closedGroupMembers.forEach { publicKey in
            SessionManagementProtocol.establishSessionIfNeeded(with: publicKey, using: transaction)
        }
    }

    @objc(shouldIgnoreClosedGroupMessage:inThread:wrappedIn:)
    public static func shouldIgnoreClosedGroupMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSGroupThread, wrappedIn envelope: SSKProtoEnvelope) -> Bool {
        guard thread.groupModel.groupType == .closedGroup else { return true }
        let publicKey = envelope.source! // Set during UD decryption
        var result = false
        Storage.read { transaction in
            result = !thread.isUserMember(inGroup: publicKey, transaction: transaction)
        }
        return result
    }

    @objc(shouldIgnoreClosedGroupUpdateMessage:inThread:wrappedIn:)
    public static func shouldIgnoreClosedGroupUpdateMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSGroupThread, wrappedIn envelope: SSKProtoEnvelope) -> Bool {
        guard thread.groupModel.groupType == .closedGroup else { return true }
        let publicKey = envelope.source! // Set during UD decryption
        var result = false
        Storage.read { transaction in
            result = !thread.isUserAdmin(inGroup: publicKey, transaction: transaction)
        }
        return result
    }
}

