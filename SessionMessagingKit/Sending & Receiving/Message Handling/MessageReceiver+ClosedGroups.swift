// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import SessionUtilitiesKit

extension MessageReceiver {
    public static func handleClosedGroupControlMessage(_ db: Database, _ message: ClosedGroupControlMessage) throws {
        switch message.kind {
            case .new: try handleNewClosedGroup(db, message: message)
            case .encryptionKeyPair: try handleClosedGroupEncryptionKeyPair(db, message: message)
            case .nameChange: try handleClosedGroupNameChanged(db, message: message)
            case .membersAdded: try handleClosedGroupMembersAdded(db, message: message)
            case .membersRemoved: try handleClosedGroupMembersRemoved(db, message: message)
            case .memberLeft: try handleClosedGroupMemberLeft(db, message: message)
            case .encryptionKeyPairRequest:
                handleClosedGroupEncryptionKeyPairRequest(db, message: message) // Currently not used
            
            default: throw MessageReceiverError.invalidMessage
        }
    }
    
    // MARK: - Specific Handling
    
    private static func handleNewClosedGroup(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case let .new(publicKeyAsData, name, encryptionKeyPair, membersAsData, adminsAsData, expirationTimer) = message.kind else {
            return
        }
        guard let sentTimestamp: UInt64 = message.sentTimestamp else { return }
        
        try handleNewClosedGroup(
            db,
            groupPublicKey: publicKeyAsData.toHexString(),
            name: name,
            encryptionKeyPair: encryptionKeyPair,
            members: membersAsData.map { $0.toHexString() },
            admins: adminsAsData.map { $0.toHexString() },
            expirationTimer: expirationTimer,
            messageSentTimestamp: sentTimestamp
        )
    }

    internal static func handleNewClosedGroup(
        _ db: Database,
        groupPublicKey: String,
        name: String,
        encryptionKeyPair: Box.KeyPair,
        members: [String],
        admins: [String],
        expirationTimer: UInt32,
        messageSentTimestamp: UInt64
    ) throws {
        // With new closed groups we only want to create them if the admin creating the closed group is an
        // approved contact (to prevent spam via closed groups getting around message requests if users are
        // on old or modified clients)
        var hasApprovedAdmin: Bool = false
        
        for adminId in admins {
            if let contact: Contact = try? Contact.fetchOne(db, id: adminId), contact.isApproved {
                hasApprovedAdmin = true
                break
            }
        }
        
        guard hasApprovedAdmin else { return }
        
        // Create the group
        let groupAlreadyExisted: Bool = ((try? SessionThread.exists(db, id: groupPublicKey)) ?? false)
        let thread: SessionThread = try SessionThread
            .fetchOrCreate(db, id: groupPublicKey, variant: .closedGroup)
            .with(shouldBeVisible: true)
            .saved(db)
        let closedGroup: ClosedGroup = try ClosedGroup(
            threadId: groupPublicKey,
            name: name,
            formationTimestamp: (TimeInterval(messageSentTimestamp) / 1000)
        ).saved(db)
        
        // Clear the zombie list if the group wasn't active (ie. had no keys)
        if ((try? closedGroup.keyPairs.fetchCount(db)) ?? 0) == 0 {
            try closedGroup.zombies.deleteAll(db)
        }
        
        // Notify the user
        if !groupAlreadyExisted {
            // Create the GroupMember records
            try members.forEach { memberId in
                try GroupMember(
                    groupId: groupPublicKey,
                    profileId: memberId,
                    role: .standard,
                    isHidden: false
                ).save(db)
            }
            
            try admins.forEach { adminId in
                try GroupMember(
                    groupId: groupPublicKey,
                    profileId: adminId,
                    role: .admin,
                    isHidden: false
                ).save(db)
            }
            
            // Note: We don't provide a `serverHash` in this case as we want to allow duplicates
            // to avoid the following situation:
            // • The app performed a background poll or received a push notification
            // • This method was invoked and the received message timestamps table was updated
            // • Processing wasn't finished
            // • The user doesn't see the new closed group
            _ = try Interaction(
                threadId: thread.id,
                authorId: getUserHexEncodedPublicKey(db),
                variant: .infoClosedGroupCreated,
                timestampMs: Int64(messageSentTimestamp)
            ).inserted(db)
        }
        
        // Update the DisappearingMessages config
        try thread.disappearingMessagesConfiguration
            .fetchOne(db)
            .defaulting(to: DisappearingMessagesConfiguration.defaultWith(thread.id))
            .with(
                isEnabled: (expirationTimer > 0),
                durationSeconds: TimeInterval(expirationTimer > 0 ?
                    expirationTimer :
                    (24 * 60 * 60)
                )
            )
            .save(db)
        
        // Store the key pair
        try ClosedGroupKeyPair(
            threadId: groupPublicKey,
            publicKey: Data(encryptionKeyPair.publicKey),
            secretKey: Data(encryptionKeyPair.secretKey),
            receivedTimestamp: Date().timeIntervalSince1970
        ).insert(db)
        
        // Start polling
        ClosedGroupPoller.shared.startPolling(for: groupPublicKey)
        
        // Notify the PN server
        let _ = PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: getUserHexEncodedPublicKey(db))
    }

    /// Extracts and adds the new encryption key pair to our list of key pairs if there is one for our public key, AND the message was
    /// sent by the group admin.
    private static func handleClosedGroupEncryptionKeyPair(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard
            case let .encryptionKeyPair(explicitGroupPublicKey, wrappers) = message.kind,
            let groupPublicKey: String = (explicitGroupPublicKey?.toHexString() ?? message.groupPublicKey)
        else { return }
        guard let userKeyPair: Box.KeyPair = Identity.fetchUserKeyPair(db) else {
            return SNLog("Couldn't find user X25519 key pair.")
        }
        guard let thread: SessionThread = try? SessionThread.fetchOne(db, id: groupPublicKey) else {
            return SNLog("Ignoring closed group encryption key pair for nonexistent group.")
        }
        guard let closedGroup: ClosedGroup = try? thread.closedGroup.fetchOne(db) else { return }
        guard let groupAdmins: [GroupMember] = try? closedGroup.admins.fetchAll(db) else { return }
        guard let sender: String = message.sender, groupAdmins.contains(where: { $0.profileId == sender }) else {
            return SNLog("Ignoring closed group encryption key pair from non-admin.")
        }
        // Find our wrapper and decrypt it if possible
        let userPublicKey: String = SessionId(.standard, publicKey: userKeyPair.publicKey).hexString
        
        guard
            let wrapper = wrappers.first(where: { $0.publicKey == userPublicKey }),
            let encryptedKeyPair = wrapper.encryptedKeyPair
        else { return }
        
        let plaintext: Data
        do {
            plaintext = try MessageReceiver.decryptWithSessionProtocol(
                ciphertext: encryptedKeyPair,
                using: userKeyPair
            ).plaintext
        }
        catch {
            return SNLog("Couldn't decrypt closed group encryption key pair.")
        }
        
        // Parse it
        let proto: SNProtoKeyPair
        do {
            proto = try SNProtoKeyPair.parseData(plaintext)
        }
        catch {
            return SNLog("Couldn't parse closed group encryption key pair.")
        }
        
        do {
            try ClosedGroupKeyPair(
                threadId: groupPublicKey,
                publicKey: proto.publicKey.removingIdPrefixIfNeeded(),
                secretKey: proto.privateKey,
                receivedTimestamp: Date().timeIntervalSince1970
            ).insert(db)
        }
        catch {
            if case DatabaseError.SQLITE_CONSTRAINT_UNIQUE = error {
                return SNLog("Ignoring duplicate closed group encryption key pair.")
            }
            
            throw error
        }
        
        SNLog("Received a new closed group encryption key pair.")
    }
    
    private static func handleClosedGroupNameChanged(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case let .nameChange(name) = message.kind else { return }
        
        try performIfValid(db, message: message) { id, sender, thread, closedGroup in
            _ = try ClosedGroup
                .filter(id: id)
                .updateAll(db, ClosedGroup.Columns.name.set(to: name))
            
            // Notify the user if needed
            guard name != closedGroup.name else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: sender,
                variant: .infoClosedGroupUpdated,
                body: ClosedGroupControlMessage.Kind
                    .nameChange(name: name)
                    .infoMessage(db, sender: sender),
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
    }
    
    private static func handleClosedGroupMembersAdded(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case let .membersAdded(membersAsData) = message.kind else { return }
        
        try performIfValid(db, message: message) { id, sender, thread, closedGroup in
            guard let groupMembers: [GroupMember] = try? closedGroup.members.fetchAll(db) else { return }
            guard let groupAdmins: [GroupMember] = try? closedGroup.admins.fetchAll(db) else { return }
            
            // Update the group
            let addedMembers: [String] = membersAsData.map { $0.toHexString() }
            let currentMemberIds: Set<String> = groupMembers.map { $0.profileId }.asSet()
            let members: Set<String> = currentMemberIds.union(addedMembers)
        
            // Create records for any new members
            try addedMembers
                .filter { !currentMemberIds.contains($0) }
                .forEach { memberId in
                    try GroupMember(
                        groupId: id,
                        profileId: memberId,
                        role: .standard,
                        isHidden: false
                    ).insert(db)
                }
            
            // Send the latest encryption key pair to the added members if the current user is
            // the admin of the group
            //
            // This fixes a race condition where:
            // • A member removes another member.
            // • A member adds someone to the group and sends them the latest group key pair.
            // • The admin is offline during all of this.
            // • When the admin comes back online they see the member removed message and generate +
            //   distribute a new key pair, but they don't know about the added member yet.
            // • Now they see the member added message.
            //
            // Without the code below, the added member(s) would never get the key pair that was
            // generated by the admin when they saw the member removed message.
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            
            if groupAdmins.contains(where: { $0.profileId == userPublicKey }) {
                addedMembers.forEach { memberId in
                    MessageSender.sendLatestEncryptionKeyPair(db, to: memberId, for: id)
                }
            }
            
            // Remove any 'zombie' versions of the added members (in case they were re-added)
            _ = try GroupMember
                .filter(GroupMember.Columns.groupId == id)
                .filter(GroupMember.Columns.role == GroupMember.Role.zombie)
                .filter(addedMembers.contains(GroupMember.Columns.profileId))
                .deleteAll(db)
            
            // Notify the user if needed
            guard members != Set(groupMembers.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: sender,
                variant: .infoClosedGroupUpdated,
                body: ClosedGroupControlMessage.Kind
                    .membersAdded(
                        members: addedMembers
                            .asSet()
                            .subtracting(groupMembers.map { $0.profileId })
                            .map { Data(hex: $0) }
                    )
                    .infoMessage(db, sender: sender),
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
    }
 
    /// Removes the given members from the group IF
    /// • it wasn't the admin that was removed (that should happen through a `MEMBER_LEFT` message).
    /// • the admin sent the message (only the admin can truly remove members).
    /// If we're among the users that were removed, delete all encryption key pairs and the group public key, unsubscribe
    /// from push notifications for this closed group, and remove the given members from the zombie list for this group.
    private static func handleClosedGroupMembersRemoved(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case let .membersRemoved(membersAsData) = message.kind else { return }
        
        try performIfValid(db, message: message) { id, sender, thread, closedGroup in
            // Check that the admin wasn't removed
            guard let groupMembers: [GroupMember] = try? closedGroup.members.fetchAll(db) else { return }
            guard let groupAdmins: [GroupMember] = try? closedGroup.admins.fetchAll(db) else { return }
            
            let removedMembers = membersAsData.map { $0.toHexString() }
            let members = Set(groupMembers.map { $0.profileId }).subtracting(removedMembers)
            
            guard let firstAdminId: String = groupAdmins.first?.profileId, members.contains(firstAdminId) else {
                return SNLog("Ignoring invalid closed group update.")
            }
            // Check that the message was sent by the group admin
            guard groupAdmins.contains(where: { $0.profileId == sender }) else {
                return SNLog("Ignoring invalid closed group update.")
            }
            
            // Delete the removed members
            try GroupMember
                .filter(GroupMember.Columns.groupId == id)
                .filter(removedMembers.contains(GroupMember.Columns.profileId))
                .filter([ GroupMember.Role.standard, GroupMember.Role.zombie ].contains(GroupMember.Columns.role))
                .deleteAll(db)
            
            // If the current user was removed:
            // • Stop polling for the group
            // • Remove the key pairs associated with the group
            // • Notify the PN server
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            let wasCurrentUserRemoved: Bool = !members.contains(userPublicKey)
            
            if wasCurrentUserRemoved {
                ClosedGroupPoller.shared.stopPolling(for: id)
                
                _ = try closedGroup
                    .keyPairs
                    .deleteAll(db)
                
                let _ = PushNotificationAPI.performOperation(
                    .unsubscribe,
                    for: id,
                    publicKey: userPublicKey
                )
            }
            
            // Notify the user if needed
            guard members != Set(groupMembers.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: sender,
                variant: (wasCurrentUserRemoved ? .infoClosedGroupCurrentUserLeft : .infoClosedGroupUpdated),
                body: ClosedGroupControlMessage.Kind
                    .membersRemoved(
                        members: removedMembers
                            .asSet()
                            .intersection(groupMembers.map { $0.profileId })
                            .map { Data(hex: $0) }
                    )
                    .infoMessage(db, sender: sender),
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
    }
    
    /// If a regular member left:
    /// • Mark them as a zombie (to be removed by the admin later).
    /// If the admin left:
    /// • Unsubscribe from PNs, delete the group public key, etc. as the group will be disbanded.
    private static func handleClosedGroupMemberLeft(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case .memberLeft = message.kind else { return }
        
        try performIfValid(db, message: message) { id, sender, thread, closedGroup in
            guard let allGroupMembers: [GroupMember] = try? closedGroup.allMembers.fetchAll(db) else {
                return
            }
            
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            let didAdminLeave: Bool = allGroupMembers.contains(where: { member in
                member.role == .admin && member.profileId == sender
            })
            let members: [GroupMember] = allGroupMembers.filter { $0.role == .standard }
            let membersToRemove: [GroupMember] = members
                .filter { member in
                    didAdminLeave || // If the admin leaves the group is disbanded
                    member.profileId == sender
                }
            let updatedMemberIds: Set<String> = members
                .map { $0.profileId }
                .asSet()
                .subtracting(membersToRemove.map { $0.profileId })
            
            // Delete the members to remove
            try GroupMember
                .filter(GroupMember.Columns.groupId == id)
                .filter(updatedMemberIds.contains(GroupMember.Columns.profileId))
                .deleteAll(db)
            
            if didAdminLeave || sender == userPublicKey {
                // Remove the group from the database and unsubscribe from PNs
                ClosedGroupPoller.shared.stopPolling(for: id)
                
                _ = try closedGroup
                    .keyPairs
                    .deleteAll(db)
                
                let _ = PushNotificationAPI.performOperation(
                    .unsubscribe,
                    for: id,
                    publicKey: userPublicKey
                )
            }
            
            // Re-add the removed member as a zombie (unless the admin left which disbands the
            // group)
            if !didAdminLeave {
                try GroupMember(
                    groupId: id,
                    profileId: sender,
                    role: .zombie,
                    isHidden: false
                ).insert(db)
            }
            
            // Notify the user if needed
            guard updatedMemberIds != Set(members.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: sender,
                variant: .infoClosedGroupUpdated,
                body: ClosedGroupControlMessage.Kind
                    .memberLeft
                    .infoMessage(db, sender: sender),
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
    }
    
    private static func handleClosedGroupEncryptionKeyPairRequest(_ db: Database, message: ClosedGroupControlMessage) {
        /*
        guard case .encryptionKeyPairRequest = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, _, group in
            let publicKey = message.sender!
            // Guard against self-sends
            guard publicKey != getUserHexEncodedPublicKey() else {
                return SNLog("Ignoring invalid closed group update.")
            }
            MessageSender.sendLatestEncryptionKeyPair(to: publicKey, for: groupPublicKey, using: transaction)
        }
         */
    }
    
    // MARK: - Convenience
    
    private static func performIfValid(
        _ db: Database,
        message: ClosedGroupControlMessage,
        _ update: (String, String, SessionThread, ClosedGroup
    ) throws -> Void) throws {
        guard let groupPublicKey: String = message.groupPublicKey else { return }
        guard let thread: SessionThread = try? SessionThread.fetchOne(db, id: groupPublicKey) else {
            return SNLog("Ignoring closed group update for nonexistent group.")
        }
        guard let closedGroup: ClosedGroup = try? thread.closedGroup.fetchOne(db) else { return }
        
        // Check that the message isn't from before the group was created
        guard Double(message.sentTimestamp ?? 0) > closedGroup.formationTimestamp else {
            return SNLog("Ignoring closed group update from before thread was created.")
        }
        
        guard let sender: String = message.sender else { return }
        guard let members: [GroupMember] = try? closedGroup.members.fetchAll(db) else { return }
        
        // Check that the sender is a member of the group
        guard members.contains(where: { $0.profileId == sender }) else {
            return SNLog("Ignoring closed group update from non-member.")
        }
        
        try update(groupPublicKey, sender, thread, closedGroup)
    }
}
