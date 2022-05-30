// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import AVKit
import GRDB
import Curve25519Kit
import SessionUtilitiesKit
import SessionSnodeKit

// Note: Looks like the oldest iOS device we support (min iOS 13.0) has 2Gb of RAM, processing
// ~250k messages and ~1000 threads seems to take up
enum _003_YDBToGRDBMigration: Migration {
    static let identifier: String = "YDBToGRDBMigration"
    static let minExpectedRunDuration: TimeInterval = 20
    static let needsConfigSync: Bool = true
    
    static func migrate(_ db: Database) throws {
        let targetIdentifier: TargetMigrations.Identifier = .messagingKit
        
        // MARK: - Process Contacts, Threads & Interactions
        print("RAWR [\(Date().timeIntervalSince1970)] - SessionMessagingKit migration - Start")
        var shouldFailMigration: Bool = false
        var legacyMigrations: Set<SMKLegacy._DBMigration> = []
        var contacts: Set<SMKLegacy._Contact> = []
        var legacyBlockedSessionIds: Set<String> = []
        var validProfileIds: Set<String> = []
        var contactThreadIds: Set<String> = []
        
        var legacyThreadIdToIdMap: [String: String] = [:]
        var legacyThreads: Set<SMKLegacy._Thread> = []
        var disappearingMessagesConfiguration: [String: SMKLegacy._DisappearingMessagesConfiguration] = [:]
        
        var closedGroupKeys: [String: [TimeInterval: SUKLegacy.KeyPair]] = [:]
        var closedGroupName: [String: String] = [:]
        var closedGroupFormation: [String: UInt64] = [:]
        var closedGroupModel: [String: SMKLegacy._GroupModel] = [:]
        var closedGroupZombieMemberIds: [String: Set<String>] = [:]
        
        var openGroupInfo: [String: OpenGroupV2] = [:]
        var openGroupUserCount: [String: Int] = [:]
        var openGroupImage: [String: Data] = [:]
        var openGroupLastMessageServerId: [String: Int64] = [:]    // Optional
        var openGroupLastDeletionServerId: [String: Int64] = [:]   // Optional
        
        var interactions: [String: [SMKLegacy._DBInteraction]] = [:]
        var attachments: [String: SMKLegacy._Attachment] = [:]
        var processedAttachmentIds: Set<String> = []
        var outgoingReadReceiptsTimestampsMs: [String: Set<Int64>] = [:]
        var receivedMessageTimestamps: Set<UInt64> = []
        
        // Map the Legacy types for the NSKeyedUnarchiver
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Thread.self,
            forClassName: "TSThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ContactThread.self,
            forClassName: "TSContactThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._GroupThread.self,
            forClassName: "TSGroupThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._GroupModel.self,
            forClassName: "TSGroupModel"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Contact.self,
            forClassName: "SNContact"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBInteraction.self,
            forClassName: "TSInteraction"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBMessage.self,
            forClassName: "TSMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBQuotedMessage.self,
            forClassName: "TSQuotedMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBQuotedMessage._DBAttachmentInfo.self,
            forClassName: "OWSAttachmentInfo"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBLinkPreview.self,
            forClassName: "SessionServiceKit.OWSLinkPreview"    // Very old legacy name
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBLinkPreview.self,
            forClassName: "SessionMessagingKit.OWSLinkPreview"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBIncomingMessage.self,
            forClassName: "TSIncomingMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBOutgoingMessage.self,
            forClassName: "TSOutgoingMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBOutgoingMessageRecipientState.self,
            forClassName: "TSOutgoingMessageRecipientState"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DBInfoMessage.self,
            forClassName: "TSInfoMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DisappearingConfigurationUpdateInfoMessage.self,
            forClassName: "OWSDisappearingConfigurationUpdateInfoMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Attachment.self,
            forClassName: "TSAttachment"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._AttachmentStream.self,
            forClassName: "TSAttachmentStream"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._AttachmentPointer.self,
            forClassName: "TSAttachmentPointer"
        )
        
        Storage.read { transaction in
            // Process the migrations (we don't want to bother running the old migrations as it would be
            // a waste of time, rather we include the logic from the old migrations in here and make the
            // same changes if the migration hasn't already run)
            transaction.enumerateRows(inCollection: SMKLegacy.databaseMigrationCollection) { key, _, _, _ in
                guard let legacyMigration: SMKLegacy._DBMigration = SMKLegacy._DBMigration(rawValue: key) else {
                    SNLog("[Migration Error] Found unknown migration")
                    shouldFailMigration = true
                    return
                }
                
                legacyMigrations.insert(legacyMigration)
            }
            
            // Process the Contacts
            transaction.enumerateRows(inCollection: SMKLegacy.contactCollection) { _, object, _, _ in
                guard let contact = object as? SMKLegacy._Contact else { return }
                contacts.insert(contact)
                validProfileIds.insert(contact.sessionID)
            }
            
            // Process legacy blocked contacts
            legacyBlockedSessionIds = Set(transaction.object(
                forKey: SMKLegacy.blockedPhoneNumbersKey,
                inCollection: SMKLegacy.blockListCollection
            ) as? [String] ?? [])
        
            print("RAWR [\(Date().timeIntervalSince1970)] - Process threads - Start")
            
            // Process the threads
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.threadCollection) { key, object, _ in
                guard let thread: SMKLegacy._Thread = object as? SMKLegacy._Thread else { return }
                
                legacyThreads.insert(thread)
                
                // Want to exclude threads which aren't visible (ie. threads which we started
                // but the user never ended up sending a message)
                if key.starts(with: SMKLegacy.contactThreadPrefix) && thread.shouldBeVisible {
                    contactThreadIds.insert(key)
                }
             
                // Get the disappearing messages config
                disappearingMessagesConfiguration[thread.uniqueId] = transaction
                    .object(forKey: thread.uniqueId, inCollection: SMKLegacy.disappearingMessagesCollection)
                    .asType(SMKLegacy._DisappearingMessagesConfiguration.self)
                
                // Process group-specific info
                guard let groupThread: SMKLegacy._GroupThread = thread as? SMKLegacy._GroupThread else {
                    legacyThreadIdToIdMap[thread.uniqueId] = thread.uniqueId.substring(
                        from: SMKLegacy.contactThreadPrefix.count
                    )
                    return
                }
                
                if groupThread.isClosedGroup {
                    // The old threadId for closed groups was in the below format, we don't
                    // really need the unnecessary complexity so process the key and extract
                    // the publicKey from it
                    // `g{base64String(Data(__textsecure_group__!{publicKey}))}
                    let base64GroupId: String = String(thread.uniqueId.suffix(from: thread.uniqueId.index(after: thread.uniqueId.startIndex)))
                    guard
                        let groupIdData: Data = Data(base64Encoded: base64GroupId),
                        let groupId: String = String(data: groupIdData, encoding: .utf8),
                        let publicKey: String = groupId.split(separator: "!").last.map({ String($0) })
                    else {
                        SNLog("[Migration Error] Unable to decode Closed Group")
                        shouldFailMigration = true
                        return
                    }
                    
                    legacyThreadIdToIdMap[thread.uniqueId] = publicKey
                    closedGroupName[thread.uniqueId] = groupThread.groupModel.groupName
                    closedGroupModel[thread.uniqueId] = groupThread.groupModel
                    closedGroupFormation[thread.uniqueId] = ((transaction.object(forKey: publicKey, inCollection: SMKLegacy.closedGroupFormationTimestampCollection) as? UInt64) ?? 0)
                    closedGroupZombieMemberIds[thread.uniqueId] = transaction.object(
                        forKey: publicKey,
                        inCollection: SMKLegacy.closedGroupZombieMembersCollection
                    ) as? Set<String>
                    
                    // Note: If the user is no longer in a closed group then the group will still exist but the user
                    // won't have the closed group public key anymore
                    let keyCollection: String = "\(SMKLegacy.closedGroupKeyPairPrefix)\(publicKey)"
                    
                    transaction.enumerateKeysAndObjects(inCollection: keyCollection) { key, object, _ in
                        guard
                            let timestamp: TimeInterval = TimeInterval(key),
                            let keyPair: SUKLegacy.KeyPair = object as? SUKLegacy.KeyPair
                        else { return }
                        
                        closedGroupKeys[thread.uniqueId] = (closedGroupKeys[thread.uniqueId] ?? [:])
                            .setting(timestamp, keyPair)
                    }
                }
                else if groupThread.isOpenGroup {
                    guard let openGroup: OpenGroupV2 = transaction.object(forKey: thread.uniqueId, inCollection: SMKLegacy.openGroupCollection) as? OpenGroupV2 else {
                        SNLog("[Migration Error] Unable to find open group info")
                        shouldFailMigration = true
                        return
                    }
                    
                    legacyThreadIdToIdMap[thread.uniqueId] = OpenGroup.idFor(
                        room: openGroup.room,
                        server: openGroup.server
                    )
                    openGroupInfo[thread.uniqueId] = openGroup
                    openGroupUserCount[thread.uniqueId] = ((transaction.object(forKey: openGroup.id, inCollection: SMKLegacy.openGroupUserCountCollection) as? Int) ?? 0)
                    openGroupImage[thread.uniqueId] = transaction.object(forKey: openGroup.id, inCollection: SMKLegacy.openGroupImageCollection) as? Data
                    openGroupLastMessageServerId[thread.uniqueId] = transaction.object(forKey: openGroup.id, inCollection: SMKLegacy.openGroupLastMessageServerIDCollection) as? Int64
                    openGroupLastDeletionServerId[thread.uniqueId] = transaction.object(forKey: openGroup.id, inCollection: SMKLegacy.openGroupLastDeletionServerIDCollection) as? Int64
                }
            }
            print("RAWR [\(Date().timeIntervalSince1970)] - Process threads - End")
            
            // Process interactions
            print("RAWR [\(Date().timeIntervalSince1970)] - Process interactions - Start")
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.interactionCollection) { _, object, _ in
                guard let interaction: SMKLegacy._DBInteraction = object as? SMKLegacy._DBInteraction else {
                    SNLog("[Migration Error] Unable to process interaction")
                    shouldFailMigration = true
                    return
                }
                
                interactions[interaction.uniqueThreadId] = (interactions[interaction.uniqueThreadId] ?? [])
                    .appending(interaction)
            }
            print("RAWR [\(Date().timeIntervalSince1970)] - Process interactions - End")
            
            // Process attachments
            print("RAWR [\(Date().timeIntervalSince1970)] - Process attachments - Start")
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.attachmentsCollection) { key, object, _ in
                guard let attachment: SMKLegacy._Attachment = object as? SMKLegacy._Attachment else {
                    SNLog("[Migration Error] Unable to process attachment")
                    shouldFailMigration = true
                    return
                }
                
                attachments[key] = attachment
            }
            print("RAWR [\(Date().timeIntervalSince1970)] - Process attachments - End")
            
            // Process read receipts
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.outgoingReadReceiptManagerCollection) { key, object, _ in
                guard let timestampsMs: Set<Int64> = object as? Set<Int64> else { return }
                
                outgoingReadReceiptsTimestampsMs[key] = (outgoingReadReceiptsTimestampsMs[key] ?? Set())
                    .union(timestampsMs)
            }
            
            receivedMessageTimestamps = receivedMessageTimestamps.inserting(
                contentsOf: transaction
                    .object(
                        forKey: SMKLegacy.receivedMessageTimestampsKey,
                        inCollection: SMKLegacy.receivedMessageTimestampsCollection
                    )
                    .asType([UInt64].self)
                    .defaulting(to: [])
                    .asSet()
            )
        }
        
        // We can't properly throw within the 'enumerateKeysAndObjects' block so have to throw here
        guard !shouldFailMigration else { throw StorageError.migrationFailed }
        
        // Insert the data into GRDB
        
        let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
        
        // MARK: - Insert Contacts
        
        try autoreleasepool {
            let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
            
            try contacts.forEach { legacyContact in
                let isCurrentUser: Bool = (legacyContact.sessionID == currentUserPublicKey)
                let contactThreadId: String = SMKLegacy._ContactThread.threadId(from: legacyContact.sessionID)
                
                // Create the "Profile" for the legacy contact
                try Profile(
                    id: legacyContact.sessionID,
                    name: (legacyContact.name ?? legacyContact.sessionID),
                    nickname: legacyContact.nickname,
                    profilePictureUrl: legacyContact.profilePictureURL,
                    profilePictureFileName: legacyContact.profilePictureFileName,
                    profileEncryptionKey: legacyContact.profileEncryptionKey
                ).insert(db)
                
                /// **Note:** The blow "shouldForce" flags are here to allow us to avoid having to run legacy migrations they
                /// replicate the behaviour of a number of the migrations and perform the changes if the migrations had never run
                
                /// `ContactsMigration` - Marked all existing contacts as trusted
                let shouldForceTrustContact: Bool = (!legacyMigrations.contains(.contactsMigration))
                
                /// `MessageRequestsMigration` - Marked all existing contacts as isApproved and didApproveMe
                let shouldForceApproveContact: Bool = (!legacyMigrations.contains(.messageRequestsMigration))
                
                /// `BlockingManagerRemovalMigration` - Removed the old blocking manager and updated contacts isBlocked flag accordingly
                let shouldForceBlockContact: Bool = (
                    !legacyMigrations.contains(.messageRequestsMigration) &&
                    legacyBlockedSessionIds.contains(legacyContact.sessionID)
                )
                
                // Determine if this contact is a "real" contact (don't want to create contacts for
                // every user in the new structure but still want profiles for every user)
                if
                    isCurrentUser ||
                    contactThreadIds.contains(contactThreadId) ||
                    legacyContact.isApproved ||
                    legacyContact.didApproveMe ||
                    legacyContact.isBlocked ||
                    legacyContact.hasBeenBlocked ||
                    shouldForceTrustContact ||
                    shouldForceApproveContact ||
                    shouldForceBlockContact
                {
                    // Create the contact
                    // TODO: Closed group admins???
                    try Contact(
                        id: legacyContact.sessionID,
                        isTrusted: (
                            isCurrentUser ||
                            legacyContact.isTrusted ||
                            shouldForceTrustContact
                        ),
                        isApproved: (
                            isCurrentUser ||
                            legacyContact.isApproved ||
                            shouldForceApproveContact
                        ),
                        isBlocked: (
                            !isCurrentUser && (
                                legacyContact.isBlocked ||
                                shouldForceBlockContact
                            )
                        ),
                        didApproveMe: (
                            isCurrentUser ||
                            legacyContact.didApproveMe ||
                            shouldForceApproveContact
                        ),
                        hasBeenBlocked: (!isCurrentUser && (legacyContact.hasBeenBlocked || legacyContact.isBlocked))
                    ).insert(db)
                }
            }
        }
        
        // MARK: - Insert Threads
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process thread inserts - Start")
        var legacyInteractionToIdMap: [String: Int64] = [:]
        var legacyInteractionIdentifierToIdMap: [String: Int64] = [:]
        var legacyInteractionIdentifierToIdFallbackMap: [String: Int64] = [:]
        
        func identifier(
            for threadId: String,
            sentTimestamp: UInt64,
            recipients: [String],
            destination: Message.Destination?,
            variant: Interaction.Variant?,
            useFallback: Bool
        ) -> String {
            let recipientString: String = {
                if let destination: Message.Destination = destination {
                    switch destination {
                        case .contact(let publicKey): return publicKey
                        default: break
                    }
                }
                
                return (recipients.first ?? "0")
            }()
            
            return [
                (useFallback ?
                    // Fallback to seconds-based accuracy (instead of milliseconds)
                    String("\(sentTimestamp)".prefix("\(Int(Date().timeIntervalSince1970))".count)) :
                    "\(sentTimestamp)"
                ),
                (useFallback ? variant.map { "\($0)" } : nil),
                recipientString,
                threadId
            ]
            .compactMap { $0 }
            .joined(separator: "-")
        }
        
        // Sort by id just so we can make the migration process more determinstic
        try legacyThreads.sorted(by: { lhs, rhs in lhs.uniqueId < rhs.uniqueId }).forEach { legacyThread in
            guard let threadId: String = legacyThreadIdToIdMap[legacyThread.uniqueId] else {
                SNLog("[Migration Error] Unable to migrate thread with no id mapping")
                throw StorageError.migrationFailed
            }
            
            let threadVariant: SessionThread.Variant
            let onlyNotifyForMentions: Bool
            
            switch legacyThread {
                case let groupThread as SMKLegacy._GroupThread:
                    threadVariant = (groupThread.isOpenGroup ? .openGroup : .closedGroup)
                    onlyNotifyForMentions = groupThread.isOnlyNotifyingForMentions
                    
                default:
                    threadVariant = .contact
                    onlyNotifyForMentions = false
            }
            
            try autoreleasepool {
                try SessionThread(
                    id: threadId,
                    variant: threadVariant,
                    creationDateTimestamp: legacyThread.creationDate.timeIntervalSince1970,
                    shouldBeVisible: legacyThread.shouldBeVisible,
                    isPinned: legacyThread.isPinned,
                    messageDraft: ((legacyThread.messageDraft ?? "").isEmpty ?
                        nil :
                        legacyThread.messageDraft
                    ),
                    mutedUntilTimestamp: legacyThread.mutedUntilDate?.timeIntervalSince1970,
                    onlyNotifyForMentions: onlyNotifyForMentions
                ).insert(db)
                
                // Disappearing Messages Configuration
                if let config: SMKLegacy._DisappearingMessagesConfiguration = disappearingMessagesConfiguration[threadId] {
                    try DisappearingMessagesConfiguration(
                        threadId: threadId,
                        isEnabled: config.isEnabled,
                        durationSeconds: TimeInterval(config.durationSeconds)
                    ).insert(db)
                }
                else {
                    try DisappearingMessagesConfiguration
                        .defaultWith(threadId)
                        .insert(db)
                }
                
                // Closed Groups
                if legacyThread.isClosedGroup {
                    guard
                        let name: String = closedGroupName[legacyThread.uniqueId],
                        let groupModel: SMKLegacy._GroupModel = closedGroupModel[legacyThread.uniqueId],
                        let formationTimestamp: UInt64 = closedGroupFormation[legacyThread.uniqueId]
                    else {
                        SNLog("[Migration Error] Closed group missing required data")
                        throw StorageError.migrationFailed
                    }
                    
                    try ClosedGroup(
                        threadId: threadId,
                        name: name,
                        formationTimestamp: TimeInterval(formationTimestamp)
                    ).insert(db)
                    
                    // Note: If a user has left a closed group then they won't actually have any keys
                    // but they should still be able to browse the old messages so we do want to allow
                    // this case and migrate the rest of the info
                    try closedGroupKeys[legacyThread.uniqueId]?.forEach { timestamp, legacyKeys in
                        try ClosedGroupKeyPair(
                            threadId: threadId,
                            publicKey: legacyKeys.publicKey,
                            secretKey: legacyKeys.privateKey,
                            receivedTimestamp: timestamp
                        ).insert(db)
                    }
                    
                    // Only create the 'GroupMember' models if the current user is actually a member
                    // of the group (if the user has left the group or been removed from it we now
                    // delete all of these records so want this to behave the same way)
                    if groupModel.groupMemberIds.contains(currentUserPublicKey) {
                        try groupModel.groupMemberIds.forEach { memberId in
                            try GroupMember(
                                groupId: threadId,
                                profileId: memberId,
                                role: .standard
                            ).insert(db)
                        }
                        
                        try groupModel.groupAdminIds.forEach { adminId in
                            try GroupMember(
                                groupId: threadId,
                                profileId: adminId,
                                role: .admin
                            ).insert(db)
                        }
                        
                        try (closedGroupZombieMemberIds[legacyThread.uniqueId] ?? []).forEach { zombieId in
                            try GroupMember(
                                groupId: threadId,
                                profileId: zombieId,
                                role: .zombie
                            ).insert(db)
                        }
                    }
                }
                
                // Open Groups
                if legacyThread.isOpenGroup {
                    guard let openGroup: OpenGroupV2 = openGroupInfo[legacyThread.uniqueId] else {
                        SNLog("[Migration Error] Open group missing required data")
                        throw StorageError.migrationFailed
                    }
                    
                    try OpenGroup(
                        server: openGroup.server,
                        room: openGroup.room,
                        publicKey: openGroup.publicKey,
                        name: openGroup.name,
                        groupDescription: nil,  // TODO: Add with SOGS V4.
                        imageId: nil,  // TODO: Add with SOGS V4.
                        imageData: openGroupImage[legacyThread.uniqueId],
                        userCount: (openGroupUserCount[legacyThread.uniqueId] ?? 0),  // Will be updated next poll
                        infoUpdates: 0  // TODO: Add with SOGS V4.
                    ).insert(db)
                }
            }
            
            try autoreleasepool {
                try interactions[legacyThread.uniqueId]?
                    .sorted(by: { lhs, rhs in lhs.timestamp < rhs.timestamp }) // Maintain sort order
                    .forEach { legacyInteraction in
                        let serverHash: String?
                        let variant: Interaction.Variant
                        let authorId: String
                        let body: String?
                        let wasRead: Bool
                        let expiresInSeconds: UInt32?
                        let expiresStartedAtMs: UInt64?
                        let openGroupServerMessageId: UInt64?
                        let recipientStateMap: [String: SMKLegacy._DBOutgoingMessageRecipientState]?
                        let mostRecentFailureText: String?
                        let quotedMessage: SMKLegacy._DBQuotedMessage?
                        let linkPreview: SMKLegacy._DBLinkPreview?
                        let linkPreviewVariant: LinkPreview.Variant
                        var attachmentIds: [String]
                        
                        // Handle the common 'SMKLegacy._DBMessage' values first
                        if let legacyMessage: SMKLegacy._DBMessage = legacyInteraction as? SMKLegacy._DBMessage {
                            serverHash = legacyMessage.serverHash
                            
                            // The legacy code only considered '!= 0' ids as valid so set those
                            // values to be null to avoid the unique constraint (it's also more
                            // correct for the values to be null)
                            openGroupServerMessageId = (legacyMessage.openGroupServerMessageID == 0 ?
                                nil :
                                legacyMessage.openGroupServerMessageID
                            )
                            quotedMessage = legacyMessage.quotedMessage
                            
                            // Convert the 'OpenGroupInvitation' into a LinkPreview
                            if let openGroupInvitationName: String = legacyMessage.openGroupInvitationName, let openGroupInvitationUrl: String = legacyMessage.openGroupInvitationURL {
                                linkPreviewVariant = .openGroupInvitation
                                linkPreview = SMKLegacy._DBLinkPreview(
                                    urlString: openGroupInvitationUrl,
                                    title: openGroupInvitationName,
                                    imageAttachmentId: nil
                                )
                            }
                            else {
                                linkPreviewVariant = .standard
                                linkPreview = legacyMessage.linkPreview
                            }
                            
                            // Attachments for deleted messages won't exist
                            attachmentIds = (legacyMessage.isDeleted ?
                                [] :
                                legacyMessage.attachmentIds
                            )
                        }
                        else {
                            serverHash = nil
                            openGroupServerMessageId = nil
                            quotedMessage = nil
                            linkPreviewVariant = .standard
                            linkPreview = nil
                            attachmentIds = []
                        }
                        
                        // Then handle the behaviours for each message type
                        switch legacyInteraction {
                            case let incomingMessage as SMKLegacy._DBIncomingMessage:
                                // Note: We want to distinguish deleted messages from normal ones
                                variant = (incomingMessage.isDeleted ?
                                    .standardIncomingDeleted :
                                    .standardIncoming
                                )
                                authorId = incomingMessage.authorId
                                body = incomingMessage.body
                                wasRead = incomingMessage.wasRead
                                expiresInSeconds = incomingMessage.expiresInSeconds
                                expiresStartedAtMs = incomingMessage.expireStartedAt
                                recipientStateMap = [:]
                                mostRecentFailureText = nil
                                
                            case let outgoingMessage as SMKLegacy._DBOutgoingMessage:
                                variant = .standardOutgoing
                                authorId = currentUserPublicKey
                                body = outgoingMessage.body
                                wasRead = true // Outgoing messages are read by default
                                expiresInSeconds = outgoingMessage.expiresInSeconds
                                expiresStartedAtMs = outgoingMessage.expireStartedAt
                                recipientStateMap = outgoingMessage.recipientStateMap
                                mostRecentFailureText = outgoingMessage.mostRecentFailureText
                                
                            case let infoMessage as SMKLegacy._DBInfoMessage:
                                // Note: The legacy 'TSInfoMessage' didn't store the author id so there is no
                                // way to determine who actually triggered the info message
                                authorId = currentUserPublicKey
                                body = {
                                    // Note: The 'DisappearingConfigurationUpdateInfoMessage' stored additional info and constructed
                                    // a string at display time so we want to continue that behaviour
                                    guard
                                        infoMessage.messageType == .disappearingMessagesUpdate,
                                        let updateMessage: SMKLegacy._DisappearingConfigurationUpdateInfoMessage = infoMessage as? SMKLegacy._DisappearingConfigurationUpdateInfoMessage,
                                        let infoMessageData: Data = try? JSONEncoder().encode(
                                            DisappearingMessagesConfiguration.MessageInfo(
                                                senderName: updateMessage.createdByRemoteName,
                                                isEnabled: updateMessage.configurationIsEnabled,
                                                durationSeconds: TimeInterval(updateMessage.configurationDurationSeconds)
                                            )
                                        ),
                                        let infoMessageString: String = String(data: infoMessageData, encoding: .utf8)
                                    else {
                                        return ((infoMessage.body ?? "").isEmpty ?
                                            infoMessage.customMessage :
                                            infoMessage.body
                                        )
                                    }
                                    
                                    return infoMessageString
                                }()
                                wasRead = infoMessage.wasRead
                                expiresInSeconds = nil    // Info messages don't expire
                                expiresStartedAtMs = nil  // Info messages don't expire
                                recipientStateMap = [:]
                                mostRecentFailureText = nil
                                
                                switch infoMessage.messageType {
                                    case .groupCreated: variant = .infoClosedGroupCreated
                                    case .groupUpdated: variant = .infoClosedGroupUpdated
                                    case .groupCurrentUserLeft: variant = .infoClosedGroupCurrentUserLeft
                                    case .disappearingMessagesUpdate: variant = .infoDisappearingMessagesUpdate
                                    case .messageRequestAccepted: variant = .infoMessageRequestAccepted
                                    case .screenshotNotification: variant = .infoScreenshotNotification
                                    case .mediaSavedNotification: variant = .infoMediaSavedNotification
                                    
                                    @unknown default:
                                        SNLog("[Migration Error] Unsupported info message type")
                                        throw GRDBStorageError.migrationFailed
                                }
                                
                            default:
                                // TODO: What message types have no body?
                                SNLog("[Migration Error] Unsupported interaction type")
                                throw StorageError.migrationFailed
                        }
                        
                        // Insert the data
                        let interaction: Interaction = try Interaction(
                            serverHash: {
                                switch variant {
                                    // Don't store the 'serverHash' for these so sync messages
                                    // are seen as duplicates
                                    case .infoDisappearingMessagesUpdate: return nil
                                        
                                    default: return serverHash
                                }
                            }(),
                            threadId: threadId,
                            authorId: authorId,
                            variant: variant,
                            body: body,
                            timestampMs: Int64(legacyInteraction.timestamp),
                            receivedAtTimestampMs: Int64(legacyInteraction.receivedAtTimestamp),
                            wasRead: wasRead,
                            hasMention: (
                                body?.contains("@\(currentUserPublicKey)") == true ||
                                quotedMessage?.authorId == currentUserPublicKey
                            ),
                            // For both of these '0' used to be equivalent to null
                            expiresInSeconds: ((expiresInSeconds ?? 0) > 0 ?
                                expiresInSeconds.map { TimeInterval($0) } :
                                nil
                            ),
                            expiresStartedAtMs: ((expiresStartedAtMs ?? 0) > 0 ?
                                expiresStartedAtMs.map { Double($0) } :
                                nil
                            ),
                            linkPreviewUrl: linkPreview?.urlString, // Only a soft link so save to set
                            openGroupServerMessageId: openGroupServerMessageId.map { Int64($0) },
                            openGroupWhisperMods: false, // TODO: This in SOGSV4
                            openGroupWhisperTo: nil // TODO: This in SOGSV4
                        ).inserted(db)
                        
                        // Insert a 'ControlMessageProcessRecord' if needed (for duplication prevention)
                        try ControlMessageProcessRecord(
                            threadId: threadId,
                            variant: variant,
                            timestampMs: Int64(legacyInteraction.timestamp)
                        )?.insert(db)
                        
                        // Remove timestamps we created records for (they will be protected by unique
                        // constraints so don't need legacy process records)
                        receivedMessageTimestamps.remove(legacyInteraction.timestamp)
                        
                        guard let interactionId: Int64 = interaction.id else {
                            // TODO: Is it possible the old database has duplicates which could hit this case?
                            SNLog("[Migration Error] Failed to insert interaction")
                            throw StorageError.migrationFailed
                        }
                        
                        // Store the interactionId in the lookup map to simplify job creation later
                        let legacyIdentifier: String = identifier(
                            for: threadId,
                            sentTimestamp: legacyInteraction.timestamp,
                            recipients: ((legacyInteraction as? SMKLegacy._DBOutgoingMessage)?
                                .recipientStateMap?
                                .keys
                                .map { $0 })
                                .defaulting(to: []),
                            destination: (threadVariant == .contact ? .contact(publicKey: threadId) : nil),
                            variant: variant,
                            useFallback: false
                        )
                        let legacyIdentifierFallback: String = identifier(
                            for: threadId,
                            sentTimestamp: legacyInteraction.timestamp,
                            recipients: ((legacyInteraction as? SMKLegacy._DBOutgoingMessage)?
                                .recipientStateMap?
                                .keys
                                .map { $0 })
                                .defaulting(to: []),
                            destination: (threadVariant == .contact ? .contact(publicKey: threadId) : nil),
                            variant: variant,
                            useFallback: true
                        )
                        
                        legacyInteractionToIdMap[legacyInteraction.uniqueId] = interactionId
                        legacyInteractionIdentifierToIdMap[legacyIdentifier] = interactionId
                        legacyInteractionIdentifierToIdFallbackMap[legacyIdentifierFallback] = interactionId
                        
                        // Handle the recipient states
                        
                        // Note: Inserting an Interaction into the database will automatically create a 'RecipientState'
                        // for outgoing messages
                        try recipientStateMap?.forEach { recipientId, legacyState in
                            try RecipientState(
                                interactionId: interactionId,
                                recipientId: recipientId,
                                state: {
                                    switch legacyState.state {
                                        case .failed: return .failed
                                        case .sending: return .sending
                                        case .skipped: return .skipped
                                        case .sent: return .sent
                                    }
                                }(),
                                readTimestampMs: legacyState.readTimestamp,
                                mostRecentFailureText: (legacyState.state == .failed ?
                                    mostRecentFailureText :
                                    nil
                                )
                            ).save(db)
                        }
                        
                        // Handle any quote
                        
                        if let quotedMessage: SMKLegacy._DBQuotedMessage = quotedMessage {
                            var quoteAttachmentId: String? = quotedMessage.quotedAttachments
                                .flatMap { attachmentInfo in
                                    return [
                                        // Prioritise the thumbnail as it means we won't
                                        // need to generate a new one
                                        attachmentInfo.thumbnailAttachmentStreamId,
                                        attachmentInfo.thumbnailAttachmentPointerId,
                                        attachmentInfo.attachmentId
                                    ]
                                    .compactMap { $0 }
                                }
                                .first { attachmentId -> Bool in attachments[attachmentId] != nil }
                            
                            // It looks like there can be cases where a quote can be quoting an
                            // interaction that isn't associated with a profile we know about (eg.
                            // if you join an open group and one of the first messages is a quote of
                            // an older message not cached to the device) - this will cause a foreign
                            // key constraint violation so in these cases just create an empty profile
                            if !validProfileIds.contains(quotedMessage.authorId) {
                                SNLog("[Migration Warning] Quote with unknown author found - Creating empty profile")
                                
                                // Note: Need to upsert here because it's possible multiple quotes
                                // will use the same invalid 'authorId' value resulting in a unique
                                // constraint violation
                                try Profile(
                                    id: quotedMessage.authorId,
                                    name: quotedMessage.authorId
                                ).save(db)
                            }
                            
                            // Note: It looks like there is a way for a quote to not have it's
                            // associated attachmentId so let's try our best to track down the
                            // original interaction and re-create the attachment link before
                            // falling back to having no attachment in the quote
                            if quoteAttachmentId == nil && !quotedMessage.quotedAttachments.isEmpty {
                                quoteAttachmentId = interactions[legacyThread.uniqueId]?
                                    .first(where: {
                                        $0.timestamp == quotedMessage.timestamp &&
                                        (
                                            // Outgoing messages don't store the 'authorId' so we
                                            // need to compare against the 'currentUserPublicKey'
                                            // for those or cast to a TSIncomingMessage otherwise
                                            quotedMessage.authorId == currentUserPublicKey ||
                                            quotedMessage.authorId == ($0 as? SMKLegacy._DBIncomingMessage)?.authorId
                                        )
                                    })
                                    .asType(SMKLegacy._DBMessage.self)?
                                    .attachmentIds
                                    .first
                                
                                SNLog([
                                    "[Migration Warning] Quote with invalid attachmentId found",
                                    (quoteAttachmentId == nil ?
                                        "Unable to reconcile, leaving attachment blank" :
                                        "Original interaction found, using source attachment"
                                    )
                                ].joined(separator: " - "))
                            }
                            
                            // Setup the attachment and add it to the lookup (if it exists)
                            let attachmentId: String? = try attachmentId(
                                db,
                                for: quoteAttachmentId,
                                isQuotedMessage: true,
                                attachments: attachments,
                                processedAttachmentIds: &processedAttachmentIds
                            )
                            
                            // Create the quote
                            try Quote(
                                interactionId: interactionId,
                                authorId: quotedMessage.authorId,
                                timestampMs: Int64(quotedMessage.timestamp),
                                body: quotedMessage.body,
                                attachmentId: attachmentId
                            ).insert(db)
                        }
                        
                        // Handle any LinkPreview
                        
                        if let linkPreview: SMKLegacy._DBLinkPreview = linkPreview, let urlString: String = linkPreview.urlString {
                            // Note: The `legacyInteraction.timestamp` value is in milliseconds
                            let timestamp: TimeInterval = LinkPreview.timestampFor(sentTimestampMs: Double(legacyInteraction.timestamp))
                            
                            guard linkPreview.imageAttachmentId == nil || attachments[linkPreview.imageAttachmentId ?? ""] != nil else {
                                // TODO: Is it possible to hit this case if a quoted attachment hasn't been downloaded?
                                SNLog("[Migration Error] Missing link preview attachment")
                                throw StorageError.migrationFailed
                            }
                            
                            // Setup the attachment and add it to the lookup (if it exists)
                            let attachmentId: String? = try attachmentId(
                                db,
                                for: linkPreview.imageAttachmentId,
                                attachments: attachments,
                                processedAttachmentIds: &processedAttachmentIds
                            )
                            
                            // Note: It's possible for there to be duplicate values here so we use 'save'
                            // instead of insert (ie. upsert)
                            try LinkPreview(
                                url: urlString,
                                timestamp: timestamp,
                                variant: linkPreviewVariant,
                                title: linkPreview.title,
                                attachmentId: attachmentId
                            ).save(db)
                        }
                        
                        // Handle any attachments
                        
                        try attachmentIds.enumerated().forEach { index, legacyAttachmentId in
                            guard let attachmentId: String = try attachmentId(
                                db,
                                for: legacyAttachmentId,
                                interactionVariant: variant,
                                attachments: attachments,
                                processedAttachmentIds: &processedAttachmentIds
                            ) else {
                                SNLog("[Migration Error] Missing interaction attachment")
                                throw GRDBStorageError.migrationFailed
                            }
                            
                            // Link the attachment to the interaction and add to the id lookup
                            try InteractionAttachment(
                                albumIndex: index,
                                interactionId: interactionId,
                                attachmentId: attachmentId
                            ).insert(db)
                        }
                }
            }
        }
        
        // Insert a 'ControlMessageProcessRecord' for any remaining 'receivedMessageTimestamp'
        // entries as "legacy"
        try ControlMessageProcessRecord.generateLegacyProcessRecords(
            db,
            receivedMessageTimestamps: receivedMessageTimestamps.map { Int64($0) }
        )
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process thread inserts - End")
        
        // Clear out processed data (give the memory a change to be freed)
        
        contacts = []
        legacyBlockedSessionIds = []
        contactThreadIds = []
        
        legacyThreads = []
        disappearingMessagesConfiguration = [:]
        
        closedGroupKeys = [:]
        closedGroupName = [:]
        closedGroupFormation = [:]
        closedGroupModel = [:]
        closedGroupZombieMemberIds = [:]
        
        openGroupInfo = [:]
        openGroupUserCount = [:]
        openGroupImage = [:]
        openGroupLastMessageServerId = [:]
        openGroupLastDeletionServerId = [:]
        
        interactions = [:]
        attachments = [:]
        receivedMessageTimestamps = []
        
        // MARK: - Process Legacy Jobs
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process jobs - Start")
        
        var notifyPushServerJobs: Set<SMKLegacy._NotifyPNServerJob> = []
        var messageReceiveJobs: Set<SMKLegacy._MessageReceiveJob> = []
        var messageSendJobs: Set<SMKLegacy._MessageSendJob> = []
        var attachmentUploadJobs: Set<SMKLegacy._AttachmentUploadJob> = []
        var attachmentDownloadJobs: Set<SMKLegacy._AttachmentDownloadJob> = []
        
        // Map the Legacy types for the NSKeyedUnarchiver
        NSKeyedUnarchiver.setClass(
            SMKLegacy._NotifyPNServerJob.self,
            forClassName: "SessionMessagingKit.NotifyPNServerJob"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._NotifyPNServerJob._SnodeMessage.self,
            forClassName: "SessionSnodeKit.SnodeMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._MessageSendJob.self,
            forClassName: "SessionMessagingKit.SNMessageSendJob"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._MessageReceiveJob.self,
            forClassName: "SessionMessagingKit.MessageReceiveJob"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._AttachmentUploadJob.self,
            forClassName: "SessionMessagingKit.AttachmentUploadJob"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._AttachmentDownloadJob.self,
            forClassName: "SessionMessagingKit.AttachmentDownloadJob"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Message.self,
            forClassName: "SNMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._VisibleMessage.self,
            forClassName: "SNVisibleMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Quote.self,
            forClassName: "SNQuote"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._LinkPreview.self,
            forClassName: "SNLinkPreview"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Profile.self,
            forClassName: "SNProfile"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._OpenGroupInvitation.self,
            forClassName: "SNOpenGroupInvitation"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ControlMessage.self,
            forClassName: "SNControlMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ReadReceipt.self,
            forClassName: "SNReadReceipt"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._TypingIndicator.self,
            forClassName: "SNTypingIndicator"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ClosedGroupControlMessage.self,
            forClassName: "SessionMessagingKit.ClosedGroupControlMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ClosedGroupControlMessage._KeyPairWrapper.self,
            forClassName: "ClosedGroupControlMessage.SNKeyPairWrapper"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._DataExtractionNotification.self,
            forClassName: "SessionMessagingKit.DataExtractionNotification"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ExpirationTimerUpdate.self,
            forClassName: "SNExpirationTimerUpdate"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ConfigurationMessage.self,
            forClassName: "SNConfigurationMessage"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._CMClosedGroup.self,
            forClassName: "SNClosedGroup"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._CMContact.self,
            forClassName: "SNConfigurationMessage.SNConfigurationMessageContact"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._UnsendRequest.self,
            forClassName: "SNUnsendRequest"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._MessageRequestResponse.self,
            forClassName: "SNMessageRequestResponse"
        )
        
        Storage.read { transaction in
            transaction.enumerateRows(inCollection: SMKLegacy.notifyPushServerJobCollection) { _, object, _, _ in
                guard let job = object as? SMKLegacy._NotifyPNServerJob else { return }
                notifyPushServerJobs.insert(job)
            }
            
            transaction.enumerateRows(inCollection: SMKLegacy.messageReceiveJobCollection) { _, object, _, _ in
                guard let job = object as? SMKLegacy._MessageReceiveJob else { return }
                messageReceiveJobs.insert(job)
            }
            
            transaction.enumerateRows(inCollection: SMKLegacy.messageSendJobCollection) { _, object, _, _ in
                guard let job = object as? SMKLegacy._MessageSendJob else { return }
                messageSendJobs.insert(job)
            }
            
            transaction.enumerateRows(inCollection: SMKLegacy.attachmentUploadJobCollection) { _, object, _, _ in
                guard let job = object as? SMKLegacy._AttachmentUploadJob else { return }
                attachmentUploadJobs.insert(job)
            }
            
            transaction.enumerateRows(inCollection: SMKLegacy.attachmentDownloadJobCollection) { _, object, _, _ in
                guard let job = object as? SMKLegacy._AttachmentDownloadJob else { return }
                attachmentDownloadJobs.insert(job)
            }
        }
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process jobs - End")
        
        // MARK: - Insert Jobs
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process job inserts - Start")
        
        // MARK: - --notifyPushServer
        
        try autoreleasepool {
            try notifyPushServerJobs.forEach { legacyJob in
                _ = try Job(
                    failureCount: legacyJob.failureCount,
                    variant: .notifyPushServer,
                    behaviour: .runOnce,
                    nextRunTimestamp: 0,
                    details: NotifyPushServerJob.Details(
                        message: SnodeMessage(
                            recipient: legacyJob.message.recipient,
                            // Note: The legacy type had 'LosslessStringConvertible' so we need
                            // to use '.description' to get it as a basic string
                            data: legacyJob.message.data.description,
                            ttl: legacyJob.message.ttl,
                            timestampMs: legacyJob.message.timestamp
                        )
                    )
                )?.inserted(db)
            }
        }
        
        // MARK: - --messageReceive
        
        try autoreleasepool {
            try messageReceiveJobs.forEach { legacyJob in
                // We haven't supported OpenGroup messageReceive jobs for a long time so if
                // we see any then just ignore them
                if legacyJob.openGroupID != nil && legacyJob.openGroupMessageServerID != nil {
                    return
                }
                
                // We need to extract the `threadId` from the legacyJob data as the new
                // MessageReceiveJob requires it for multi-threading and garbage collection purposes
                guard let envelope: SNProtoEnvelope = try? SNProtoEnvelope.parseData(legacyJob.data) else {
                    return
                }
                
                let threadId: String?

                switch envelope.type {
                    // For closed group messages the 'groupPublicKey' is stored in the
                    // 'envelope.source' value and that should be used for the 'threadId'
                    case .closedGroupMessage:
                        threadId = envelope.source
                        break
                        
                    default:
                        threadId = MessageReceiver.extractSenderPublicKey(db, from: envelope)
                }

                _ = try Job(
                    failureCount: legacyJob.failureCount,
                    variant: .messageReceive,
                    behaviour: .runOnce,
                    nextRunTimestamp: 0,
                    threadId: threadId,
                    details: MessageReceiveJob.Details(
                        messages: [
                            MessageReceiveJob.Details.MessageInfo(
                                data: legacyJob.data,
                                serverHash: legacyJob.serverHash,
                                serverExpirationTimestamp: (Date().timeIntervalSince1970 + ControlMessageProcessRecord.defaultExpirationSeconds)
                            )
                        ],
                        isBackgroundPoll: legacyJob.isBackgroundPoll
                    )
                )?.inserted(db)
            }
        }
        
        // MARK: - --messageSend
        
        var messageSendJobLegacyMap: [String: Job] = [:]

        try autoreleasepool {
            try messageSendJobs.forEach { legacyJob in
                // Fetch the threadId and interactionId this job should be associated with
                let threadId: String = {
                    switch legacyJob.destination {
                        case .contact(let publicKey): return publicKey
                        case .closedGroup(let groupPublicKey): return groupPublicKey
                        case .openGroupV2(let room, let server):
                            return OpenGroup.idFor(room: room, server: server)
                            
                        case .openGroup: return ""
                    }
                }()
                let interactionId: Int64? = {
                    // The 'Legacy.Job' 'id' value was "(timestamp)(num jobs for this timestamp)"
                    // so we can reverse-engineer an approximate timestamp by extracting it from
                    // the id (this value is unlikely to match exactly though)
                    let fallbackTimestamp: UInt64 = legacyJob.id
                        .map { UInt64($0.prefix("\(Int(Date().timeIntervalSince1970 * 1000))".count)) }
                        .defaulting(to: 0)
                    let legacyIdentifier: String = identifier(
                        for: threadId,
                        sentTimestamp: (legacyJob.message.sentTimestamp ?? fallbackTimestamp),
                        recipients: (legacyJob.message.recipient.map { [$0] } ?? []),
                        destination: legacyJob.destination,
                        variant: nil,
                        useFallback: false
                    )
                    
                    if let matchingId: Int64 = legacyInteractionIdentifierToIdMap[legacyIdentifier] {
                        return matchingId
                    }

                    // If we didn't find the correct interaction then we need to try the "fallback"
                    // identifier which is less accurate (during testing this only happened for
                    // 'ExpirationTimerUpdate' send jobs)
                    let fallbackIdentifier: String = identifier(
                        for: threadId,
                        sentTimestamp: (legacyJob.message.sentTimestamp ?? fallbackTimestamp),
                        recipients: (legacyJob.message.recipient.map { [$0] } ?? []),
                        destination: legacyJob.destination,
                        variant: {
                            switch legacyJob.message {
                                case is SMKLegacy._ExpirationTimerUpdate:
                                    return .infoDisappearingMessagesUpdate
                                default: return nil
                            }
                        }(),
                        useFallback: true
                    )
                    
                    return legacyInteractionIdentifierToIdFallbackMap[fallbackIdentifier]
                }()
                
                // Don't botther adding any 'MessageSend' jobs VisibleMessages which don't have associated
                // interactions
                switch legacyJob.message {
                    case is SMKLegacy._VisibleMessage:
                        guard interactionId != nil else {
                            SNLog("[Migration Warning] Unable to find associated interaction to messageSend job, ignoring.")
                            return
                        }
                        
                        break
                        
                    default: break
                }
                
                let job: Job? = try Job(
                    failureCount: legacyJob.failureCount,
                    variant: .messageSend,
                    behaviour: .runOnce,
                    nextRunTimestamp: 0,
                    threadId: threadId,
                    // Note: There are some cases where there isn't a link between a
                    // 'MessageSendJob' and an interaction (eg. ConfigurationMessage),
                    // in these cases the 'interactionId' value will be nil
                    interactionId: interactionId,
                    details: MessageSendJob.Details(
                        destination: legacyJob.destination,
                        message: legacyJob.message.toNonLegacy()
                    )
                )?.inserted(db)
                
                if let oldId: String = legacyJob.id {
                    messageSendJobLegacyMap[oldId] = job
                }
            }
        }
        
        // MARK: - --attachmentUpload

        try autoreleasepool {
            try attachmentUploadJobs.forEach { legacyJob in
                guard let sendJob: Job = messageSendJobLegacyMap[legacyJob.messageSendJobID], let sendJobId: Int64 = sendJob.id else {
                    SNLog("[Migration Error] attachmentUpload job missing associated MessageSendJob")
                    throw StorageError.migrationFailed
                }

                let uploadJob: Job? = try Job(
                    failureCount: legacyJob.failureCount,
                    variant: .attachmentUpload,
                    behaviour: .runOnce,
                    threadId: legacyJob.threadID,
                    interactionId: sendJob.interactionId,
                    details: AttachmentUploadJob.Details(
                        messageSendJobId: sendJobId,
                        attachmentId: legacyJob.attachmentID
                    )
                )?.inserted(db)
                
                // Add the dependency to the relevant MessageSendJob
                guard let uploadJobId: Int64 = uploadJob?.id else {
                    SNLog("[Migration Error] attachmentUpload job was not created")
                    throw StorageError.migrationFailed
                }
                
                try JobDependencies(
                    jobId: sendJobId,
                    dependantId: uploadJobId
                ).insert(db)
            }
        }
        
        // MARK: - --attachmentDownload
        
        try autoreleasepool {
            try attachmentDownloadJobs.forEach { legacyJob in
                guard let interactionId: Int64 = legacyInteractionToIdMap[legacyJob.tsMessageID] else {
                    SNLog("[Migration Error] attachmentDownload job unable to find interaction")
                    throw StorageError.migrationFailed
                }
                guard processedAttachmentIds.contains(legacyJob.attachmentID) else {
                    SNLog("[Migration Error] attachmentDownload job unable to find attachment")
                    throw GRDBStorageError.migrationFailed
                }
                
                _ = try Job(
                    failureCount: legacyJob.failureCount,
                    variant: .attachmentDownload,
                    behaviour: .runOnce,
                    nextRunTimestamp: 0,
                    threadId: legacyThreadIdToIdMap[legacyJob.threadID],
                    interactionId: interactionId,
                    details: AttachmentDownloadJob.Details(
                        attachmentId: legacyJob.attachmentID
                    )
                )?.inserted(db)
            }
        }
        
        // MARK: - --sendReadReceipts
        
        try autoreleasepool {
            try outgoingReadReceiptsTimestampsMs.forEach { threadId, timestampsMs in
                _ = try Job(
                    variant: .sendReadReceipts,
                    behaviour: .recurring,
                    threadId: threadId,
                    details: SendReadReceiptsJob.Details(
                        destination: .contact(publicKey: threadId),
                        timestampMsValues: timestampsMs
                    )
                )?.inserted(db)
            }
        }
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process job inserts - End")
        
        // MARK: - Process Preferences
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process preferences inserts - Start")
        
        var legacyPreferences: [String: Any] = [:]
        
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.preferencesCollection) { key, object, _ in
                legacyPreferences[key] = object
            }
            
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.additionalPreferencesCollection) { key, object, _ in
                legacyPreferences[key] = object
            }
            
            // Note: The 'int(forKey:inCollection:)' defaults to `0` which is an incorrect value
            // for the notification sound so catch it and default
            let globalNotificationSoundValue: Int32 = transaction.int(
                forKey: SMKLegacy.soundsGlobalNotificationKey,
                inCollection: SMKLegacy.soundsStorageNotificationCollection
            )
            legacyPreferences[SMKLegacy.soundsGlobalNotificationKey] = (globalNotificationSoundValue > 0 ?
                Int(globalNotificationSoundValue) :
                Preferences.Sound.defaultNotificationSound.rawValue
            )
            
            legacyPreferences[SMKLegacy.readReceiptManagerAreReadReceiptsEnabled] = transaction.bool(
                forKey: SMKLegacy.readReceiptManagerAreReadReceiptsEnabled,
                inCollection: SMKLegacy.readReceiptManagerCollection,
                defaultValue: false
            )
            
            legacyPreferences[SMKLegacy.typingIndicatorsEnabledKey] = transaction.bool(
                forKey: SMKLegacy.typingIndicatorsEnabledKey,
                inCollection: SMKLegacy.typingIndicatorsCollection,
                defaultValue: false
            )
            
            legacyPreferences[SMKLegacy.screenLockIsScreenLockEnabledKey] = transaction.bool(
                forKey: SMKLegacy.screenLockIsScreenLockEnabledKey,
                inCollection: SMKLegacy.screenLockCollection,
                defaultValue: false
            )
            
            legacyPreferences[SMKLegacy.screenLockScreenLockTimeoutSecondsKey] = transaction.double(
                forKey: SMKLegacy.screenLockScreenLockTimeoutSecondsKey,
                inCollection: SMKLegacy.screenLockCollection,
                defaultValue: (15 * 60)
            )
        }
        
        db[.defaultNotificationSound] = Preferences.Sound(rawValue: legacyPreferences[SMKLegacy.soundsGlobalNotificationKey] as? Int ?? -1)
            .defaulting(to: Preferences.Sound.defaultNotificationSound)
        db[.playNotificationSoundInForeground] = (legacyPreferences[SMKLegacy.preferencesKeyNotificationSoundInForeground] as? Bool == true)
        db[.preferencesNotificationPreviewType] = Preferences.NotificationPreviewType(rawValue: legacyPreferences[SMKLegacy.preferencesKeyNotificationPreviewType] as? Int ?? -1)
            .defaulting(to: .nameAndPreview)
        
        if let lastPushToken: String = legacyPreferences[SMKLegacy.preferencesKeyLastRecordedPushToken] as? String {
            db[.lastRecordedPushToken] = lastPushToken
        }
        
        if let lastVoipToken: String = legacyPreferences[SMKLegacy.preferencesKeyLastRecordedVoipToken] as? String {
            db[.lastRecordedVoipToken] = lastVoipToken
        }
        
        // Note: The 'preferencesKeyScreenSecurityDisabled' value previously controlled whether the
        // setting was disabled, this has been inverted to 'appSwitcherPreviewEnabled' so it can default
        // to 'false' (as most Bool values do)
        db[.areReadReceiptsEnabled] = (legacyPreferences[SMKLegacy.readReceiptManagerAreReadReceiptsEnabled] as? Bool == true)
        db[.typingIndicatorsEnabled] = (legacyPreferences[SMKLegacy.typingIndicatorsEnabledKey] as? Bool == true)
        db[.isScreenLockEnabled] = (legacyPreferences[SMKLegacy.screenLockIsScreenLockEnabledKey] as? Bool == true)
        db[.screenLockTimeoutSeconds] = (legacyPreferences[SMKLegacy.screenLockScreenLockTimeoutSecondsKey] as? Double)
            .defaulting(to: (15 * 60))
        db[.appSwitcherPreviewEnabled] = (legacyPreferences[SMKLegacy.preferencesKeyScreenSecurityDisabled] as? Bool == false)
        db[.areLinkPreviewsEnabled] = (legacyPreferences[SMKLegacy.preferencesKeyAreLinkPreviewsEnabled] as? Bool == true)
        db[.hasHiddenMessageRequests] = CurrentAppContext().appUserDefaults()
            .bool(forKey: SMKLegacy.userDefaultsHasHiddenMessageRequests)
        db[.hasSavedThread] = (legacyPreferences[SMKLegacy.preferencesKeyHasSavedThreadKey] as? Bool == true)
        db[.hasSentAMessage] = (legacyPreferences[SMKLegacy.preferencesKeyHasSentAMessageKey] as? Bool == true)
        db[.isReadyForAppExtensions] = CurrentAppContext().appUserDefaults().bool(forKey: SMKLegacy.preferencesKeyIsReadyForAppExtensions)
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process preferences inserts - End")
        
        print("RAWR Done!!!")
    }
    
    // MARK: - Convenience
    
    private static func attachmentId(
        _ db: Database,
        for legacyAttachmentId: String?,
        interactionVariant: Interaction.Variant? = nil,
        isQuotedMessage: Bool = false,
        attachments: [String: SMKLegacy._Attachment],
        processedAttachmentIds: inout Set<String>
    ) throws -> String? {
        guard let legacyAttachmentId: String = legacyAttachmentId else { return nil }
        guard !processedAttachmentIds.contains(legacyAttachmentId) else {
            guard isQuotedMessage else {
                SNLog("[Migration Error] Attempted to process duplicate attachment")
                throw StorageError.migrationFailed
            }
            
            return legacyAttachmentId
        }
        
        guard let legacyAttachment: SMKLegacy._Attachment = attachments[legacyAttachmentId] else {
            SNLog("[Migration Warning] Missing attachment - interaction will appear as blank")
            return nil
        }

        let processedLocalRelativeFilePath: String? = (legacyAttachment as? SMKLegacy._AttachmentStream)?
            .localRelativeFilePath
            .map { filePath -> String in
                // The old 'localRelativeFilePath' seemed to have a leading forward slash (want
                // to get rid of it so we can correctly use 'appendingPathComponent')
                guard filePath.starts(with: "/") else { return filePath }
                
                return String(filePath.suffix(from: filePath.index(after: filePath.startIndex)))
            }
        let state: Attachment.State = {
            switch legacyAttachment {
                case let stream as SMKLegacy._AttachmentStream:  // Outgoing or already downloaded
                    switch interactionVariant {
                        case .standardOutgoing: return (stream.isUploaded ? .uploaded : .uploading)
                        default: return .downloaded
                    }
                
                // All other cases can just be set to 'pendingDownload'
                default: return .pendingDownload
            }
        }()
        let size: CGSize = {
            switch legacyAttachment {
                case let stream as SMKLegacy._AttachmentStream:
                    // First try to get an image size using the 'localRelativeFilePath' value
                    if
                        let localRelativeFilePath: String = processedLocalRelativeFilePath,
                        let specificImageSize: CGSize = Attachment.imageSize(
                            contentType: stream.contentType,
                            originalFilePath: URL(fileURLWithPath: Attachment.attachmentsFolder)
                                .appendingPathComponent(localRelativeFilePath)
                                .path
                        ),
                        specificImageSize != .zero
                    {
                        return specificImageSize
                    }
                    
                    // Then fallback to trying to get the size from the 'originalFilePath'
                    guard let originalFilePath: String = Attachment.originalFilePath(id: legacyAttachmentId, mimeType: stream.contentType, sourceFilename: stream.sourceFilename) else {
                        return .zero
                    }
                    
                    return Attachment
                        .imageSize(
                            contentType: stream.contentType,
                            originalFilePath: originalFilePath
                        )
                        .defaulting(to: .zero)
                    
                case let pointer as SMKLegacy._AttachmentPointer: return pointer.mediaSize
                default: return CGSize.zero
            }
        }()
        let (isValid, duration): (Bool, TimeInterval?) = {
            guard
                let stream: SMKLegacy._AttachmentStream = legacyAttachment as? SMKLegacy._AttachmentStream,
                let originalFilePath: String = Attachment.originalFilePath(
                    id: legacyAttachmentId,
                    mimeType: stream.contentType,
                    sourceFilename: stream.sourceFilename
                )
            else {
                return (false, nil)
            }
            
            if stream.isAudio {
                if let cachedDuration: TimeInterval = stream.cachedAudioDurationSeconds?.doubleValue, cachedDuration > 0 {
                    return (true, cachedDuration)
                }
                
                let attachmentVailidityInfo = Attachment.determineValidityAndDuration(
                    contentType: stream.contentType,
                    localRelativeFilePath: processedLocalRelativeFilePath,
                    originalFilePath: originalFilePath
                )
                
                return (attachmentVailidityInfo.isValid, attachmentVailidityInfo.duration)
            }
            
            if stream.isVideo {
                let attachmentVailidityInfo = Attachment.determineValidityAndDuration(
                    contentType: stream.contentType,
                    localRelativeFilePath: processedLocalRelativeFilePath,
                    originalFilePath: originalFilePath
                )
                
                return (attachmentVailidityInfo.isValid, attachmentVailidityInfo.duration)
            }
            
            if stream.isVisualMedia {
                return (stream.isValidVisualMedia, nil)
            }
            
            return (true, nil)
        }()
        
        
        _ = try Attachment(
            // Note: The legacy attachment object used a UUID string for it's id as well
            // and saved files using these id's so just used the existing id so we don't
            // need to bother renaming files as part of the migration
            id: legacyAttachmentId,
            serverId: "\(legacyAttachment.serverId)",
            variant: (legacyAttachment.attachmentType == .voiceMessage ? .voiceMessage : .standard),
            state: state,
            contentType: legacyAttachment.contentType,
            byteCount: UInt(legacyAttachment.byteCount),
            creationTimestamp: (legacyAttachment as? SMKLegacy._AttachmentStream)?
                .creationTimestamp.timeIntervalSince1970,
            sourceFilename: legacyAttachment.sourceFilename,
            downloadUrl: legacyAttachment.downloadURL,
            localRelativeFilePath: processedLocalRelativeFilePath,
            width: (size == .zero ? nil : UInt(size.width)),
            height: (size == .zero ? nil : UInt(size.height)),
            duration: duration,
            isValid: isValid,
            encryptionKey: legacyAttachment.encryptionKey,
            digest: (legacyAttachment as? SMKLegacy._AttachmentStream)?.digest,
            caption: legacyAttachment.caption
        ).inserted(db)
        
        processedAttachmentIds.insert(legacyAttachmentId)
        
        return legacyAttachmentId
    }
}
