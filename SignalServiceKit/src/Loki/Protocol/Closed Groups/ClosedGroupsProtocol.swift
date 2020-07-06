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
    public static let isSharedSenderKeysEnabled = true

    /// - Note: It's recommended to batch fetch the device links for the given set of members before invoking this, to avoid
    /// the message sending pipeline making a request for each member.
    public static func createClosedGroup(name: String, members membersAsSet: Set<String>, transaction: YapDatabaseReadWriteTransaction) -> TSGroupThread {
        var membersAsSet = membersAsSet
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        let userPublicKey = getUserHexEncodedPublicKey()
        // Generate a key pair for the group
        let groupKeyPair = Curve25519.generateKeyPair()
        let groupPublicKey = groupKeyPair.hexEncodedPublicKey
        // Ensure the current user's master device is included in the member list
        membersAsSet.remove(userPublicKey)
        membersAsSet.insert(UserDefaults.standard[.masterHexEncodedPublicKey] ?? userPublicKey)
        // Create ratchets for all users involved
        let members = [String](membersAsSet) // On the receiving side it's assumed that the member list and chain key list are ordered the same
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
        // Establish sessions if needed (shouldn't be necessary under normal circumstances as
        // the user can only pick from existing contacts)
        establishSessionsIfNeeded(with: members, using: transaction)
        // Send a closed group update message to all members involved using established channels
        let senderKeys = ratchets.map { ClosedGroupSenderKey(chainKey: Data(hex: $0.chainKey), keyIndex: $0.keyIndex) }
        for member in members {
            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
            thread.save(with: transaction)
            let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.new(groupPublicKey: Data(hex: groupPublicKey), name: name, groupPrivateKey: groupKeyPair.privateKey, senderKeys: senderKeys, members: members, admins: admins)
            let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
            messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        }
        // Add the group to the user's set of public keys to poll for
        Storage.setClosedGroupPrivateKey(groupKeyPair.privateKey.toHexString(), for: groupPublicKey, using: transaction)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
        // Return
        return thread
    }

    public static func addMembers(_ newMembersAsSet: Set<String>, to groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        // Prepare
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        let groupID = LKGroupUtilities.getEncodedClosedGroupID(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: groupID, transaction: transaction) else {
            return print("[Loki] Can't add users to nonexistent closed group.")
        }
        let group = thread.groupModel
        let name = group.groupName!
        let admins = group.groupAdminIds
        guard let groupPrivateKey = Storage.getClosedGroupPrivateKey(for: groupPublicKey) else {
            return print("[Loki] Can't get private key for closed group.")
        }
        // Add the members to the member list
        var members = group.groupMemberIds
        members.append(contentsOf: newMembersAsSet)
        // Establish sessions if needed (shouldn't be necessary under normal circumstances as
        // the user can only pick from existing contacts)
        establishSessionsIfNeeded(with: members, using: transaction)
        // Generate ratchets for the new members
        let newMembers = [String](newMembersAsSet) // On the receiving side it's assumed that the member list and chain key list are ordered the same
        let ratchets = newMembers.map {
            SharedSenderKeysImplementation.shared.generateRatchet(for: groupPublicKey, senderPublicKey: $0, using: transaction)
        }
        // Send a closed group update message to the existing members with the new members' ratchets (this message is
        // aimed at the group)
        let senderKeys = ratchets.map { ClosedGroupSenderKey(chainKey: Data(hex: $0.chainKey), keyIndex: $0.keyIndex) }
        let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, senderKeys: senderKeys, members: members, admins: admins)
        let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
        messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        // Send closed group update messages to the new members using established channels
        let allSenderKeys = Storage.getAllClosedGroupRatchets(for: groupPublicKey).map { // This includes the newly generated ratchets
            ClosedGroupSenderKey(chainKey: Data(hex: $0.chainKey), keyIndex: $0.keyIndex)
        }
        for member in newMembers {
            let thread = TSContactThread.getOrCreateThread(contactId: member)
            thread.save(with: transaction)
            let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.new(groupPublicKey: Data(hex: groupPublicKey), name: name, groupPrivateKey: Data(hex: groupPrivateKey), senderKeys: allSenderKeys, members: members, admins: admins)
            let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
            messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        }
        // Update the group
        let groupIDAsData = groupID.data(using: String.Encoding.utf8)!
        let newGroupModel = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupIDAsData, groupType: .closedGroup, adminIds: admins)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
    }

    public static func leave(_ groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        removeMembers([ getUserHexEncodedPublicKey() ], from: groupPublicKey, using: transaction)
    }

    public static func removeMembers(_ membersToRemove: Set<String>, from groupPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        let userPublicKey = getUserHexEncodedPublicKey()
        let isUserLeaving = membersToRemove.contains(userPublicKey)
        guard !isUserLeaving || membersToRemove.count == 1 else {
            return print("[Loki] Can't remove self and others simultaneously.")
        }
        // Prepare
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        let groupID = LKGroupUtilities.getEncodedClosedGroupID(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: groupID, transaction: transaction) else {
            return print("[Loki] Can't remove users from nonexistent closed group.")
        }
        let group = thread.groupModel
        let name = group.groupName!
        let admins = group.groupAdminIds
        // Remove the members from the member list
        var members = group.groupMemberIds
        let indexes = membersToRemove.compactMap { members.firstIndex(of: $0) }
        guard indexes.count == membersToRemove.count else {
            return print("[Loki] Can't remove users from group.")
        }
        indexes.forEach { members.remove(at: $0) }
        // Send the update to the group (don't include new ratchets as everyone should generate new ratchets individually)
        let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, senderKeys: [], members: members, admins: admins)
        let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
        messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        // Delete all ratchets (it's important that this happens after sending out the update)
        Storage.removeAllClosedGroupRatchets(for: groupPublicKey, using: transaction)
        // Remove the group from the user's set of public keys to poll for if the user is leaving. Otherwise generate
        // a new ratchet and send it out to all members (minus the removed ones) using established channels.
        if isUserLeaving {
            Storage.removeClosedGroupPrivateKey(for: groupPublicKey, using: transaction)
        } else {
            // Establish sessions if needed (shouldn't be necessary under normal circumstances as
            // sessions would've already been established previously)
            establishSessionsIfNeeded(with: members, using: transaction)
            // Send out the user's new ratchet to all members (minus the removed ones) using established channels
            let newRatchet = SharedSenderKeysImplementation.shared.generateRatchet(for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
            let newSenderKey = ClosedGroupSenderKey(chainKey: Data(hex: newRatchet.chainKey), keyIndex: newRatchet.keyIndex)
            for member in members {
                let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                thread.save(with: transaction)
                let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.senderKey(groupPublicKey: Data(hex: groupPublicKey), senderKey: newSenderKey)
                let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
                messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
            }
        }
        // Update the group
        let groupIDAsData = groupID.data(using: String.Encoding.utf8)!
        let newGroupModel = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupIDAsData, groupType: .closedGroup, adminIds: admins)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user
        let infoMessageType: TSInfoMessageType = isUserLeaving ? .typeGroupQuit : .typeGroupUpdate
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: infoMessageType)
        infoMessage.save(with: transaction)
    }

    @objc(handleSharedSenderKeysUpdateIfNeeded:from:transaction:)
    public static func handleSharedSenderKeysUpdateIfNeeded(_ dataMessage: SSKProtoDataMessage, from publicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard isSharedSenderKeysEnabled else { return }
        // Note that `publicKey` is either the public key of the group or the public key of the
        // sender, depending on how the message was sent
        guard let closedGroupUpdate = dataMessage.closedGroupUpdate else { return }
        switch closedGroupUpdate.type {
        case .new: handleNewGroupMessage(closedGroupUpdate, using: transaction)
        case .info: handleInfoMessage(closedGroupUpdate, from: publicKey, using: transaction)
        case .chainKey: handleChainKeyMessage(closedGroupUpdate, from: publicKey, using: transaction)
        }
    }

    private static func handleNewGroupMessage(_ closedGroupUpdate: SSKProtoDataMessageClosedGroupUpdate, using transaction: YapDatabaseReadWriteTransaction) {
        // Unwrap the message
        let groupPublicKey = closedGroupUpdate.groupPublicKey.toHexString()
        let name = closedGroupUpdate.name
        let groupPrivateKey = closedGroupUpdate.groupPrivateKey!
        let senderKeys = closedGroupUpdate.senderKeys
        let members = closedGroupUpdate.members
        let admins = closedGroupUpdate.admins
        // Persist the ratchets
        zip(members, senderKeys).forEach { (member, senderKey) in
            let ratchet = ClosedGroupRatchet(chainKey: senderKey.chainKey.toHexString(), keyIndex: UInt(senderKey.keyIndex), messageKeys: [])
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
    private static func handleInfoMessage(_ closedGroupUpdate: SSKProtoDataMessageClosedGroupUpdate, from senderPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        // Unwrap the message
        let groupPublicKey = closedGroupUpdate.groupPublicKey.toHexString()
        let name = closedGroupUpdate.name
        let senderKeys = closedGroupUpdate.senderKeys
        let members = closedGroupUpdate.members
        let admins = closedGroupUpdate.admins
        // Get the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupID(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: groupID, transaction: transaction) else {
            return print("[Loki] Ignoring closed group update for nonexistent group.")
        }
        let group = thread.groupModel
        // Check that the sender is an admin (before the update)
        var isSenderAdmin = false
        Storage.read { transaction in
            isSenderAdmin = !thread.isUserAdmin(inGroup: senderPublicKey, transaction: transaction)
        }
        guard isSenderAdmin else {
            return print("[Loki] Ignoring closed group update from non-admin.")
        }
        // Establish sessions if needed (it's important that this happens before the code below)
        establishSessionsIfNeeded(with: members, using: transaction)
        // Parse out any new members and store their ratchets (it's important that
        // this happens before the code below)
        let oldMembers = group.groupMemberIds
        let newMembers = members.filter { !oldMembers.contains($0) }
        if newMembers.count == senderKeys.count { // If someone left or was kicked the message won't have any sender keys
            zip(newMembers, senderKeys).forEach { (member, senderKey) in
                let ratchet = ClosedGroupRatchet(chainKey: senderKey.chainKey.toHexString(), keyIndex: UInt(senderKey.keyIndex), messageKeys: [])
                Storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: member, ratchet: ratchet, using: transaction)
            }
        }
        // Delete all ratchets and send out the user's new ratchet using established
        // channels if any member of the group left or was removed
        if Set(members).intersection(oldMembers) != Set(oldMembers) {
            Storage.removeAllClosedGroupRatchets(for: groupPublicKey, using: transaction)
            let userPublicKey = getUserHexEncodedPublicKey()
            let userRatchet = SharedSenderKeysImplementation.shared.generateRatchet(for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
            let userSenderKey = ClosedGroupSenderKey(chainKey: Data(hex: userRatchet.chainKey), keyIndex: userRatchet.keyIndex)
            for member in members {
                let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                thread.save(with: transaction)
                let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.senderKey(groupPublicKey: Data(hex: groupPublicKey), senderKey: userSenderKey)
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
        guard let senderKey = closedGroupUpdate.senderKeys.first else {
            return print("[Loki] Ignoring invalid closed group update.")
        }
        let ratchet = ClosedGroupRatchet(chainKey: senderKey.chainKey.toHexString(), keyIndex: UInt(senderKey.keyIndex), messageKeys: [])
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

