import SessionUtilitiesKit

extension ConfigurationMessage {

    public static func getCurrent(with transaction: YapDatabaseReadTransaction) -> ConfigurationMessage? {
        let storage = Storage.shared
        guard let user = storage.getUser(using: transaction) else { return nil }
        
        let displayName = user.name
        let profilePictureURL = user.profilePictureURL
        let profileKey = user.profileEncryptionKey?.keyData
        var closedGroups: Set<ClosedGroup> = []
        var openGroups: Set<String> = []
        var contacts: Set<ConfigurationMessage.Contact> = []
        
        TSGroupThread.enumerateCollectionObjects(with: transaction) { object, _ in
            guard let thread = object as? TSGroupThread else { return }
            
            switch thread.groupModel.groupType {
                case .closedGroup:
                    guard thread.isCurrentUserMemberInGroup() else { return }
                    
                    let groupID = thread.groupModel.groupId
                    let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                    
                    guard
                        storage.isClosedGroup(groupPublicKey, using: transaction),
                        let encryptionKeyPair = storage.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey, using: transaction)
                    else {
                        return
                    }
                    
                    let closedGroup = ClosedGroup(
                        publicKey: groupPublicKey,
                        name: (thread.groupModel.groupName ?? ""),
                        encryptionKeyPair: encryptionKeyPair,
                        members: Set(thread.groupModel.groupMemberIds),
                        admins: Set(thread.groupModel.groupAdminIds),
                        expirationTimer: thread.disappearingMessagesDuration(with: transaction)
                    )
                    closedGroups.insert(closedGroup)
                    
                case .openGroup:
                    if let threadId: String = thread.uniqueId, let v2OpenGroup = storage.getV2OpenGroup(for: threadId) {
                        openGroups.insert("\(v2OpenGroup.server)/\(v2OpenGroup.room)?public_key=\(v2OpenGroup.publicKey)")
                    }

                default: break
            }
        }
        
        let currentUserPublicKey: String = getUserHexEncodedPublicKey()
        
        contacts = storage.getAllContacts(with: transaction)
            .compactMap { contact -> ConfigurationMessage.Contact? in
                let threadID = TSContactThread.threadID(fromContactSessionID: contact.sessionID)
                
                guard
                    // Skip the current user
                    contact.sessionID != currentUserPublicKey &&
                    // Contacts which have visible threads
                    TSContactThread.fetch(uniqueId: threadID, transaction: transaction)?.shouldBeVisible == true && (
                        
                        // Include already approved contacts
                        contact.isApproved ||
                        contact.didApproveMe ||
                        
                        // Sync blocked contacts
                        contact.isBlocked ||
                        contact.hasBeenBlocked
                    )
                else {
                    return nil
                }
                
                // Can just default the 'hasX' values to true as they will be set to this
                // when converting to proto anyway
                let profilePictureURL = contact.profilePictureURL
                let profileKey = contact.profileEncryptionKey?.keyData
                
                return ConfigurationMessage.Contact(
                    publicKey: contact.sessionID,
                    displayName: (contact.name ?? contact.sessionID),
                    profilePictureURL: profilePictureURL,
                    profileKey: profileKey,
                    hasIsApproved: true,
                    isApproved: contact.isApproved,
                    hasIsBlocked: true,
                    isBlocked: contact.isBlocked,
                    hasDidApproveMe: true,
                    didApproveMe: contact.didApproveMe
                )
            }
            .asSet()
        
        return ConfigurationMessage(
            displayName: displayName,
            profilePictureURL: profilePictureURL,
            profileKey: profileKey,
            closedGroups: closedGroups,
            openGroups: openGroups,
            contacts: contacts
        )
    }
}
