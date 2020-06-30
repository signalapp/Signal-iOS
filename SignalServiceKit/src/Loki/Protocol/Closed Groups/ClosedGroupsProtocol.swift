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

    @objc(handleSharedSenderKeysUpdateIfNeeded:transaction:)
    public static func handleSharedSenderKeysUpdateIfNeeded(_ dataMessage: SSKProtoDataMessage, using transaction: YapDatabaseReadWriteTransaction) -> Bool {
        guard let closedGroupUpdate = dataMessage.closedGroupUpdate else { return false }
        switch closedGroupUpdate.type {
        case .new:
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
                Storage.setClosedGroupRatchet(groupPublicKey: groupPublicKey, senderPublicKey: member, ratchet: ratchet, using: transaction)
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
            establishSessionsIfNeeded(with: members, in: thread, using: transaction)
            // Return
            return true
        }
    }

    @objc(shouldIgnoreClosedGroupMessage:inThread:wrappedIn:)
    public static func shouldIgnoreClosedGroupMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSThread, wrappedIn envelope: SSKProtoEnvelope) -> Bool {
        guard let thread = thread as? TSGroupThread, thread.groupModel.groupType == .closedGroup,
            dataMessage.group?.type == .deliver else { return false }
        let publicKey = envelope.source! // Set during UD decryption
        var result = false
        Storage.read { transaction in
            result = !thread.isUser(inGroup: publicKey, transaction: transaction)
        }
        return result
    }

    @objc(shouldIgnoreClosedGroupUpdateMessage:inThread:wrappedIn:)
    public static func shouldIgnoreClosedGroupUpdateMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSGroupThread?, wrappedIn envelope: SSKProtoEnvelope) -> Bool {
        guard let thread = thread else { return false }
        let publicKey = envelope.source! // Set during UD decryption
        var result = false
        Storage.read { transaction in
            result = !thread.isUserAdmin(inGroup: publicKey, transaction: transaction)
        }
        return result
    }

    @objc(establishSessionsIfNeededWithClosedGroupMembers:inThread:transaction:)
    public static func establishSessionsIfNeeded(with closedGroupMembers: [String], in thread: TSGroupThread, using transaction: YapDatabaseReadWriteTransaction) {
        guard thread.groupModel.groupType == .closedGroup else { return }
        closedGroupMembers.forEach { member in
            SessionManagementProtocol.establishSessionIfNeeded(with: member, using: transaction)
        }
    }
}

