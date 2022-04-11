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
        var openGroupUserCount: [String: Int] = [:]
        var openGroupImage: [String: Data] = [:]
        var openGroupLastMessageServerId: [String: Int64] = [:]    // Optional
        var openGroupLastDeletionServerId: [String: Int64] = [:]   // Optional
        
        var interactions: [String: [TSInteraction]] = [:]
        var attachments: [String: TSAttachment] = [:]
        var readReceipts: [String: [Double]] = [:]
        
        Storage.read { transaction in
            // Process the Contacts
            transaction.enumerateRows(inCollection: Legacy.contactCollection) { _, object, _, _ in
                guard let contact = object as? Legacy.Contact else { return }
                contacts.insert(contact)
            }
        
            print("RAWR [\(Date().timeIntervalSince1970)] - Process threads - Start")
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
                
                // Process the interactions
                
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
                        let publicKey: String = groupId.split(separator: "!").last.map({ String($0) })
                    else {
                        SNLog("[Migration Error] Unable to decode Closed Group")
                        shouldFailMigration = true
                        return
                    }
                    guard userClosedGroupPublicKeys.contains(publicKey) else {
                        SNLog("[Migration Error] Found unexpected invalid closed group public key")
                        shouldFailMigration = true
                        return
                    }
                    
                    let keyCollection: String = "\(Legacy.closedGroupKeyPairPrefix)\(publicKey)"
                    
                    closedGroupName[threadId] = groupThread.name(with: transaction)
                    closedGroupModel[threadId] = groupThread.groupModel
                    closedGroupFormation[threadId] = ((transaction.object(forKey: publicKey, inCollection: Legacy.closedGroupFormationTimestampCollection) as? UInt64) ?? 0)
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
                    guard let openGroup: OpenGroupV2 = transaction.object(forKey: threadId, inCollection: Legacy.openGroupCollection) as? OpenGroupV2 else {
                        SNLog("[Migration Error] Unable to find open group info")
                        shouldFailMigration = true
                        return
                    }
                    
                    openGroupInfo[threadId] = openGroup
                    openGroupUserCount[threadId] = ((transaction.object(forKey: openGroup.id, inCollection: Legacy.openGroupUserCountCollection) as? Int) ?? 0)
                    openGroupImage[threadId] = transaction.object(forKey: openGroup.id, inCollection: Legacy.openGroupImageCollection) as? Data
                    openGroupLastMessageServerId[threadId] = transaction.object(forKey: openGroup.id, inCollection: Legacy.openGroupLastMessageServerIDCollection) as? Int64
                    openGroupLastDeletionServerId[threadId] = transaction.object(forKey: openGroup.id, inCollection: Legacy.openGroupLastDeletionServerIDCollection) as? Int64
                }
            }
            print("RAWR [\(Date().timeIntervalSince1970)] - Process threads - End")
            
            // Process interactions
            print("RAWR [\(Date().timeIntervalSince1970)] - Process interactions - Start")
            transaction.enumerateKeysAndObjects(inCollection: Legacy.interactionCollection) { _, object, _ in
                guard let interaction: TSInteraction = object as? TSInteraction else {
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
            transaction.enumerateKeysAndObjects(inCollection: Legacy.attachmentsCollection) { key, object, _ in
                guard let attachment: TSAttachment = object as? TSAttachment else {
                    SNLog("[Migration Error] Unable to process attachment")
                    shouldFailMigration = true
                    return
                }
                
                attachments[key] = attachment
            }
            print("RAWR [\(Date().timeIntervalSince1970)] - Process attachments - End")
            
            }
        }
        
        // We can't properly throw within the 'enumerateKeysAndObjects' block so have to throw here
        guard !shouldFailMigration else { throw GRDBStorageError.migrationFailed }
        
        // Insert the data into GRDB
        
        // MARK: - Insert Contacts
        
        try autoreleasepool {
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
        }
        
        // MARK: - Insert Threads
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process thread inserts - Start")
        
        try threads.forEach { thread in
            guard let legacyThreadId: String = thread.uniqueId else { return }
            
            let id: String
            let variant: SessionThread.Variant
            let notificationMode: SessionThread.NotificationMode
            
            switch thread {
                case let groupThread as TSGroupThread:
                    if groupThread.isOpenGroup {
                        guard let openGroup: OpenGroupV2 = openGroupInfo[legacyThreadId] else {
                            SNLog("[Migration Error] Open group missing required data")
                            throw GRDBStorageError.migrationFailed
                        }
                        
                        id = openGroup.id
                        variant = .openGroup
                    }
                    else {
                        guard let publicKey: Data = closedGroupKeys[legacyThreadId]?.keys.publicKey else {
                            SNLog("[Migration Error] Closed group missing public key")
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
            
            try autoreleasepool {
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
                        threadId: id,
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
                    else {
                        SNLog("[Migration Error] Closed group missing required data")
                        throw GRDBStorageError.migrationFailed
                    }
                    
                    try ClosedGroup(
                        threadId: id,
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
                
                // Open Groups
                if (thread as? TSGroupThread)?.isOpenGroup == true {
                    guard let openGroup: OpenGroupV2 = openGroupInfo[legacyThreadId] else {
                        SNLog("[Migration Error] Open group missing required data")
                        throw GRDBStorageError.migrationFailed
                    }
                    
                    try OpenGroup(
                        server: openGroup.server,
                        room: openGroup.room,
                        publicKey: openGroup.publicKey,
                        name: openGroup.name,
                        groupDescription: nil,  // TODO: Add with SOGS V4
                        imageId: nil,  // TODO: Add with SOGS V4
                        imageData: openGroupImage[legacyThreadId],
                        userCount: (openGroupUserCount[legacyThreadId] ?? 0),  // Will be updated next poll
                        infoUpdates: 0  // TODO: Add with SOGS V4
                    ).insert(db)
                }
            }
            
            try autoreleasepool {
                let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
                
                try interactions[legacyThreadId]?
                    .sorted(by: { lhs, rhs in lhs.sortId < rhs.sortId }) // Maintain sort order
                    .forEach { legacyInteraction in
                        let serverHash: String?
                        let variant: Interaction.Variant
                        let authorId: String
                        let body: String?
                        let expiresInSeconds: UInt32?
                        let expiresStartedAtMs: UInt64?
                        let openGroupServerMessageId: UInt64?
                        let recipientStateMap: [String: TSOutgoingMessageRecipientState]?
                        let quotedMessage: TSQuotedMessage?
                        let linkPreview: OWSLinkPreview?
                        let linkPreviewVariant: LinkPreview.Variant
                        var attachmentIds: [String]
                        
                        // Handle the common 'TSMessage' values first
                        if let legacyMessage: TSMessage = legacyInteraction as? TSMessage {
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
                                linkPreview = OWSLinkPreview(
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
                                try legacyMessage.attachmentIds.map { legacyId in
                                    guard let attachmentId: String = legacyId as? String else {
                                        SNLog("[Migration Error] Unable to process attachment id")
                                        throw GRDBStorageError.migrationFailed
                                    }
                                    
                                    return attachmentId
                                }
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
                            case let incomingMessage as TSIncomingMessage:
                                // Note: We want to distinguish deleted messages from normal ones
                                variant = (incomingMessage.isDeleted ?
                                    .standardIncomingDeleted :
                                    .standardIncoming
                                )
                                authorId = incomingMessage.authorId
                                body = incomingMessage.body
                                expiresInSeconds = incomingMessage.expiresInSeconds
                                expiresStartedAtMs = incomingMessage.expireStartedAt
                                recipientStateMap = [:]
                                
                                
                            case let outgoingMessage as TSOutgoingMessage:
                                variant = .standardOutgoing
                                authorId = currentUserPublicKey
                                body = outgoingMessage.body
                                expiresInSeconds = outgoingMessage.expiresInSeconds
                                expiresStartedAtMs = outgoingMessage.expireStartedAt
                                recipientStateMap = outgoingMessage.recipientStateMap
                                
                            case let infoMessage as TSInfoMessage:
                                authorId = currentUserPublicKey
                                body = ((infoMessage.body ?? "").isEmpty ?
                                    infoMessage.customMessage :
                                    infoMessage.body
                                )
                                expiresInSeconds = nil    // Info messages don't expire
                                expiresStartedAtMs = nil  // Info messages don't expire
                                recipientStateMap = [:]
                                
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
                                SNLog("[Migration Error] Unsupported interaction type")
                                throw GRDBStorageError.migrationFailed
                        }
                        
                        // Insert the data
                        let interaction = try Interaction(
                            serverHash: serverHash,
                            threadId: id,
                            authorId: authorId,
                            variant: variant,
                            body: body,
                            timestampMs: Double(legacyInteraction.timestamp),
                            receivedAtTimestampMs: Double(legacyInteraction.receivedAtTimestamp),
                            expiresInSeconds: expiresInSeconds.map { TimeInterval($0) },
                            expiresStartedAtMs: expiresStartedAtMs.map { Double($0) },
                            linkPreviewUrl: linkPreview?.urlString, // Only a soft link so save to set
                            openGroupServerMessageId: openGroupServerMessageId.map { Int64($0) },
                            openGroupWhisperMods: false, // TODO: This
                            openGroupWhisperTo: nil // TODO: This
                        ).inserted(db)
                        
                        guard let interactionId: Int64 = interaction.id else {
                            SNLog("[Migration Error] Failed to insert interaction")
                            throw GRDBStorageError.migrationFailed
                        }
                        
                        // Handle the recipient states
                        
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
                                        @unknown default: throw GRDBStorageError.migrationFailed
                                    }
                                }(),
                                readTimestampMs: legacyState.readTimestamp?.doubleValue
                            ).insert(db)
                        }
                        
                        // Handle any quote
                        
                        if let quotedMessage: TSQuotedMessage = quotedMessage {
                            try Quote(
                                interactionId: interactionId,
                                authorId: quotedMessage.authorId,
                                timestampMs: Double(quotedMessage.timestamp),
                                body: quotedMessage.body
                            ).insert(db)
                            
                            // Ensure the quote thumbnail works properly
                            
                            
                            // Note: Quote attachments are now attached directly to the interaction
                            attachmentIds = attachmentIds.appending(
                                contentsOf: quotedMessage.quotedAttachments.compactMap { attachmentInfo in
                                    if let attachmentId: String = attachmentInfo.attachmentId {
                                        return attachmentId
                                    }
                                    else if let attachmentId: String = attachmentInfo.thumbnailAttachmentPointerId {
                                        return attachmentId
                                    }
                                    // TODO: Looks like some of these might be busted???
                                    return attachmentInfo.thumbnailAttachmentStreamId
                                }
                            )
                        }
                        
                        // Handle any LinkPreview
                        
                        if let linkPreview: OWSLinkPreview = linkPreview, let urlString: String = linkPreview.urlString {
                            // Note: The `legacyInteraction.timestamp` value is in milliseconds
                            let timestamp: TimeInterval = LinkPreview.timestampFor(sentTimestampMs: Double(legacyInteraction.timestamp))
                            
                            // Note: It's possible for there to be duplicate values here so we use 'save'
                            // instead of insert (ie. upsert)
                            try LinkPreview(
                                url: urlString,
                                timestamp: timestamp,
                                variant: linkPreviewVariant,
                                title: linkPreview.title
                            ).save(db)
                            
                            // Note: LinkPreview attachments are now attached directly to the interaction
                            attachmentIds = attachmentIds.appending(linkPreview.imageAttachmentId)
                        }
                        
                        // Handle any attachments
                        try attachmentIds.forEach { attachmentId in
                            guard let attachment: TSAttachment = attachments[attachmentId] else {
                                SNLog("[Migration Error] Unsupported interaction type")
                                throw GRDBStorageError.migrationFailed
                            }
                            
                            let size: CGSize = {
                                switch attachment {
                                    case let stream as TSAttachmentStream: return stream.calculateImageSize()
                                    case let pointer as TSAttachmentPointer: return pointer.mediaSize
                                    default: return CGSize.zero
                                }
                            }()
                            try Attachment(
                                interactionId: interactionId,
                                serverId: "\(attachment.serverId)",
                                variant: (attachment.isVoiceMessage ? .voiceMessage : .standard),
                                state: .pending, // TODO: This
                                contentType: attachment.contentType,
                                byteCount: UInt(attachment.byteCount),
                                creationTimestamp: (attachment as? TSAttachmentStream)?.creationTimestamp.timeIntervalSince1970,
                                sourceFilename: attachment.sourceFilename,
                                downloadUrl: attachment.downloadURL,
                                width: (size == .zero ? nil : UInt(size.width)),
                                height: (size == .zero ? nil : UInt(size.height)),
                                encryptionKey: attachment.encryptionKey,
                                digest: (attachment as? TSAttachmentStream)?.digest,
                                caption: attachment.caption
                            ).insert(db)
                        }
                }
            }
        }
        
        print("RAWR [\(Date().timeIntervalSince1970)] - Process thread inserts - End")
        
        print("RAWR Done!!!")
    }
}
