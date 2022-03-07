import SessionUtilitiesKit

extension ConfigurationMessage {

    public static func getCurrent(with transaction: YapDatabaseReadWriteTransaction? = nil) -> ConfigurationMessage? {
        let storage = Storage.shared
        guard let user = storage.getUser() else { return nil }
        
        let displayName = user.name
        let profilePictureURL = user.profilePictureURL
        let profileKey = user.profileEncryptionKey?.keyData
        var closedGroups: Set<ClosedGroup> = []
        var openGroups: Set<String> = []
        var contacts: Set<ConfigurationMessage.Contact> = []
        
        let populateDataClosure: (YapDatabaseReadTransaction) -> () = { transaction in
            TSGroupThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSGroupThread else { return }
                
                switch thread.groupModel.groupType {
                    case .closedGroup:
                        guard thread.isCurrentUserMemberInGroup() else { return }
                        
                        let groupID = thread.groupModel.groupId
                        let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                        
                        guard storage.isClosedGroup(groupPublicKey), let encryptionKeyPair = storage.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else {
                            return
                        }
                        
                        let closedGroup = ClosedGroup(
                            publicKey: groupPublicKey,
                            name: thread.groupModel.groupName!,
                            encryptionKeyPair: encryptionKeyPair,
                            members: Set(thread.groupModel.groupMemberIds),
                            admins: Set(thread.groupModel.groupAdminIds),
                            expirationTimer: thread.disappearingMessagesDuration(with: transaction)
                        )
                        closedGroups.insert(closedGroup)
                        
                    case .openGroup:
                        if let v2OpenGroup = storage.getV2OpenGroup(for: thread.uniqueId!) {
                            openGroups.insert("\(v2OpenGroup.server)/\(v2OpenGroup.room)?public_key=\(v2OpenGroup.publicKey)")
                        }
                        
                    default: break
                }
            }
            
            let currentUserPublicKey: String = getUserHexEncodedPublicKey()
            
            contacts = storage.getAllContacts(with: transaction)
                .filter { contact -> Bool in
                    let threadID = TSContactThread.threadID(fromContactSessionID: contact.sessionID)
                    
                    return (
                        // Skip the current user
                        contact.sessionID != currentUserPublicKey && (
                            
                            // Include already approved contacts
                            contact.isApproved ||
                            contact.didApproveMe ||
                            
                            // Sync blocked contacts
                            SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(contact.sessionID) ||
                            
                            // Contacts which have visible threads (sanity check - should be included as already approved)
                            TSContactThread.fetch(uniqueId: threadID, transaction: transaction)?.shouldBeVisible == true
                        )
                    )
                }
                .map { contact -> ConfigurationMessage.Contact in
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
            }
        
        // If we are provided with a transaction then read the data based on the state of the database
        // from within the transaction rather than the state in disk
        if let transaction: YapDatabaseReadWriteTransaction = transaction {
            populateDataClosure(transaction)
        }
        else {
            Storage.read { transaction in populateDataClosure(transaction) }
        }
        
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
