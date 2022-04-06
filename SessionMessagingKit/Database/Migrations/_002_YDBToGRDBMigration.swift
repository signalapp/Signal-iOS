// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Curve25519Kit
import SessionUtilitiesKit

enum _002_YDBToGRDBMigration: Migration {
    static let identifier: String = "YDBToGRDBMigration"
    
    // TODO: Autorelease pool???.
    static func migrate(_ db: Database) throws {
        // MARK: - Contacts & Threads
        
        var shouldFailMigration: Bool = false
        var contacts: Set<Legacy.Contact> = []
        var contactThreadIds: Set<String> = []
        var threads: Set<TSThread> = []
        var disappearingMessagesConfiguration: [String: Legacy.DisappearingMessagesConfiguration] = [:]
        var closedGroupKeys: [String: (timestamp: TimeInterval, keys: SessionUtilitiesKit.Legacy.KeyPair)] = [:]
        var closedGroupName: [String: String] = [:]
        var closedGroupFormation: [String: UInt64] = [:]
        var closedGroupModel: [String: TSGroupModel] = [:]
        var closedGroupZombieMemberIds: [String: Set<String>] = [:]
        var openGroupInfo: [String: OpenGroupV2] = [:]
        
        Storage.read { transaction in
            // Process the Contacts
            transaction.enumerateRows(inCollection: Legacy.contactCollection) { _, object, _, _ in
                guard let contact = object as? Legacy.Contact else { return }
                contacts.insert(contact)
            }
            
            let userClosedGroupPublicKeys: [String] = transaction.allKeys(inCollection: Legacy.closedGroupPublicKeyCollection)
            
            // Process the threads
            transaction.enumerateKeysAndObjects(inCollection: Legacy.threadCollection) { key, object, _ in
                guard let thread: TSThread = object as? TSThread else { return }
                guard let threadId: String = thread.uniqueId else { return }
                
                threads.insert(thread)
                
                // Want to exclude threads which aren't visible (ie. threads which we started
                // but the user never ended up sending a message)
                if key.starts(with: Legacy.contactThreadPrefix) && thread.shouldBeVisible {
                    contactThreadIds.insert(key)
                }
             
                // Get the disappearing messages config
                disappearingMessagesConfiguration[threadId] = transaction
                    .object(forKey: threadId, inCollection: Legacy.disappearingMessagesCollection)
                    .asType(Legacy.DisappearingMessagesConfiguration.self)
                    .defaulting(to: Legacy.DisappearingMessagesConfiguration.defaultWith(threadId))
                
                // Process group-specific info
                guard let groupThread: TSGroupThread = thread as? TSGroupThread else { return }
                
                if groupThread.isClosedGroup {
                    // The old threadId for closed groups was in the below format, we don't
                    // really need the unnecessary complexity so process the key and extract
                    // the publicKey from it
                    // `g{base64String(Data(__textsecure_group__!{publicKey}))}
                    let base64GroupId: String = String(threadId.suffix(from: threadId.index(after: threadId.startIndex)))
                    guard
                        let groupIdData: Data = Data(base64Encoded: base64GroupId),
                        let groupId: String = String(data: groupIdData, encoding: .utf8),
                        let publicKey: String = groupId.split(separator: "!").last.map({ String($0) }),
                        let formationTimestamp: UInt64 = transaction.object(forKey: publicKey, inCollection: Legacy.closedGroupFormationTimestampCollection) as? UInt64
                    else {
                        SNLog("Unable to decode Closed Group during migration")
                        shouldFailMigration = true
                        return
                    }
                    guard userClosedGroupPublicKeys.contains(publicKey) else {
                        SNLog("Found unexpected invalid closed group public key during migration")
                        shouldFailMigration = true
                        return
                    }
                    
                    let keyCollection: String = "\(Legacy.closedGroupKeyPairPrefix)\(publicKey)"
                    
                    closedGroupName[threadId] = groupThread.name(with: transaction)
                    closedGroupModel[threadId] = groupThread.groupModel
                    closedGroupFormation[threadId] = formationTimestamp
                    closedGroupZombieMemberIds[threadId] = transaction.object(
                        forKey: publicKey,
                        inCollection: Legacy.closedGroupZombieMembersCollection
                    ) as? Set<String>
                    
                    transaction.enumerateKeysAndObjects(inCollection: keyCollection) { key, object, _ in
                        guard let timestamp: TimeInterval = TimeInterval(key), let keyPair: SessionUtilitiesKit.Legacy.KeyPair = object as? SessionUtilitiesKit.Legacy.KeyPair else {
                            return
                        }
                        
                        closedGroupKeys[threadId] = (timestamp, keyPair)
                    }
                }
                else if groupThread.isOpenGroup {
                    
                }
                
                
                
            }
        }
        
        // We can't properly throw within the 'enumerateKeysAndObjects' block so have to throw here
        guard !shouldFailMigration else { throw GRDBStorageError.migrationFailed }
        
        // Insert the data into GRDB
        
        // MARK: - Insert Contacts
        
        let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
        
        try contacts.forEach { contact in
            let isCurrentUser: Bool = (contact.sessionID == currentUserPublicKey)
            let contactThreadId: String = TSContactThread.threadID(fromContactSessionID: contact.sessionID)
            
            // Create the "Profile" for the legacy contact
            try Profile(
                id: contact.sessionID,
                name: (contact.name ?? contact.sessionID),
                nickname: contact.nickname,
                profilePictureUrl: contact.profilePictureURL,
                profilePictureFileName: contact.profilePictureFileName,
                profileEncryptionKey: contact.profileEncryptionKey
            ).insert(db)
            
            // Determine if this contact is a "real" contact (don't want to create contacts for
            // every user in the new structure but still want profiles for every user)
            if
                isCurrentUser ||
                contactThreadIds.contains(contactThreadId) ||
                contact.isApproved ||
                contact.didApproveMe ||
                contact.isBlocked ||
                contact.hasBeenBlocked {
                // Create the contact
                // TODO: Closed group admins???
                try Contact(
                    id: contact.sessionID,
                    isTrusted: (isCurrentUser || contact.isTrusted),
                    isApproved: (isCurrentUser || contact.isApproved),
                    isBlocked: (!isCurrentUser && contact.isBlocked),
                    didApproveMe: (isCurrentUser || contact.didApproveMe),
                    hasBeenBlocked: (!isCurrentUser && (contact.hasBeenBlocked || contact.isBlocked))
                ).insert(db)
            }
        }
        
        // MARK: - Insert Threads
        
        try threads.forEach { thread in
            guard let legacyThreadId: String = thread.uniqueId else { return }
            
            let id: String
            let variant: SessionThread.Variant
            let notificationMode: SessionThread.NotificationMode
            
            switch thread {
                case let groupThread as TSGroupThread:
                    if groupThread.isOpenGroup {
                        id = legacyThreadId//openGroup.id
                        variant = .openGroup
                    }
                    else {
                        guard let publicKey: Data = closedGroupKeys[legacyThreadId]?.keys.publicKey else {
                            throw GRDBStorageError.migrationFailed
                        }
                        
                        id = publicKey.toHexString()
                        variant = .closedGroup
                    }
                    
                    notificationMode = (thread.isMuted ? .none :
                        (groupThread.isOnlyNotifyingForMentions ?
                            .mentionsOnly :
                            .all
                        )
                    )
                    
                default:
                    id = legacyThreadId.substring(from: Legacy.contactThreadPrefix.count)
                    variant = .contact
                    notificationMode = (thread.isMuted ? .none : .all)
            }
            
            try SessionThread(
                id: id,
                variant: variant,
                creationDateTimestamp: thread.creationDate.timeIntervalSince1970,
                shouldBeVisible: thread.shouldBeVisible,
                isPinned: thread.isPinned,
                messageDraft: thread.messageDraft,
                notificationMode: notificationMode,
                mutedUntilTimestamp: thread.mutedUntilDate?.timeIntervalSince1970
            ).insert(db)
            
            // Disappearing Messages Configuration
            if let config: Legacy.DisappearingMessagesConfiguration = disappearingMessagesConfiguration[id] {
                try DisappearingMessagesConfiguration(
                    id: id,
                    isEnabled: config.isEnabled,
                    durationSeconds: TimeInterval(config.durationSeconds)
                ).insert(db)
            }
            
            // Closed Groups
            if (thread as? TSGroupThread)?.isClosedGroup == true {
                guard
                    let keyInfo = closedGroupKeys[legacyThreadId],
                    let name: String = closedGroupName[legacyThreadId],
                    let groupModel: TSGroupModel = closedGroupModel[legacyThreadId],
                    let formationTimestamp: UInt64 = closedGroupFormation[legacyThreadId]
                else { throw GRDBStorageError.migrationFailed }
                
                try ClosedGroup(
                    publicKey: keyInfo.keys.publicKey.toHexString(),
                    name: name,
                    formationTimestamp: TimeInterval(formationTimestamp)
                ).insert(db)
                
                try ClosedGroupKeyPair(
                    publicKey: keyInfo.keys.publicKey.toHexString(),
                    secretKey: keyInfo.keys.privateKey,
                    receivedTimestamp: keyInfo.timestamp
                ).insert(db)
                
                try groupModel.groupMemberIds.forEach { memberId in
                    try GroupMember(
                        groupId: id,
                        profileId: memberId,
                        role: .standard
                    ).insert(db)
                }
                
                try groupModel.groupAdminIds.forEach { adminId in
                    try GroupMember(
                        groupId: id,
                        profileId: adminId,
                        role: .admin
                    ).insert(db)
                }
                
                try (closedGroupZombieMemberIds[legacyThreadId] ?? []).forEach { zombieId in
                    try GroupMember(
                        groupId: id,
                        profileId: zombieId,
                        role: .zombie
                    ).insert(db)
                }
            }
        }
    }
}
