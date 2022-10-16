// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import SignalCoreKit
import SessionUtilitiesKit

public enum MessageReceiver {
    private static var lastEncryptionKeyPairRequest: [String: Date] = [:]
    
    public static func parse(
        _ db: Database,
        envelope: SNProtoEnvelope,
        serverExpirationTimestamp: TimeInterval?,
        openGroupId: String?,
        openGroupMessageServerId: Int64?,
        openGroupServerPublicKey: String?,
        isOutgoing: Bool? = nil,
        otherBlindedPublicKey: String? = nil,
        dependencies: SMKDependencies = SMKDependencies()
    ) throws -> (Message, SNProtoContent, String) {
        let userPublicKey: String = getUserHexEncodedPublicKey(db, dependencies: dependencies)
        let isOpenGroupMessage: Bool = (openGroupId != nil)
        
        // Decrypt the contents
        guard let ciphertext = envelope.content else { throw MessageReceiverError.noData }
        
        var plaintext: Data
        var sender: String
        var groupPublicKey: String? = nil
        
        if isOpenGroupMessage {
            (plaintext, sender) = (envelope.content!, envelope.source!)
        }
        else {
            switch envelope.type {
                case .sessionMessage:
                    // Default to 'standard' as the old code didn't seem to require an `envelope.source`
                    switch (SessionId.Prefix(from: envelope.source) ?? .standard) {
                        case .standard, .unblinded:
                            guard let userX25519KeyPair: Box.KeyPair = Identity.fetchUserKeyPair(db) else {
                                throw MessageReceiverError.noUserX25519KeyPair
                            }
                            
                            (plaintext, sender) = try decryptWithSessionProtocol(ciphertext: ciphertext, using: userX25519KeyPair)
                            
                        case .blinded:
                            guard let otherBlindedPublicKey: String = otherBlindedPublicKey else {
                                throw MessageReceiverError.noData
                            }
                            guard let openGroupServerPublicKey: String = openGroupServerPublicKey else {
                                throw MessageReceiverError.invalidGroupPublicKey
                            }
                            guard let userEd25519KeyPair: Box.KeyPair = Identity.fetchUserEd25519KeyPair(db) else {
                                throw MessageReceiverError.noUserED25519KeyPair
                            }
                            
                            (plaintext, sender) = try decryptWithSessionBlindingProtocol(
                                data: ciphertext,
                                isOutgoing: (isOutgoing == true),
                                otherBlindedPublicKey: otherBlindedPublicKey,
                                with: openGroupServerPublicKey,
                                userEd25519KeyPair: userEd25519KeyPair,
                                using: dependencies
                            )
                    }
                    
                case .closedGroupMessage:
                    guard
                        let hexEncodedGroupPublicKey = envelope.source,
                        let closedGroup: ClosedGroup = try? ClosedGroup.fetchOne(db, id: hexEncodedGroupPublicKey)
                    else {
                        throw MessageReceiverError.invalidGroupPublicKey
                    }
                    guard
                        let encryptionKeyPairs: [ClosedGroupKeyPair] = try? closedGroup.keyPairs.order(ClosedGroupKeyPair.Columns.receivedTimestamp.desc).fetchAll(db),
                        !encryptionKeyPairs.isEmpty
                    else {
                        throw MessageReceiverError.noGroupKeyPair
                    }
                    
                    // Loop through all known group key pairs in reverse order (i.e. try the latest key
                    // pair first (which'll more than likely be the one we want) but try older ones in
                    // case that didn't work)
                    func decrypt(keyPairs: [ClosedGroupKeyPair], lastError: Error? = nil) throws -> (Data, String) {
                        guard let keyPair: ClosedGroupKeyPair = keyPairs.first else {
                            throw (lastError ?? MessageReceiverError.decryptionFailed)
                        }
                        
                        do {
                            return try decryptWithSessionProtocol(
                                ciphertext: ciphertext,
                                using: Box.KeyPair(
                                    publicKey: keyPair.publicKey.bytes,
                                    secretKey: keyPair.secretKey.bytes
                                )
                            )
                        }
                        catch {
                            return try decrypt(keyPairs: Array(keyPairs.suffix(from: 1)), lastError: error)
                        }
                    }
                    
                    groupPublicKey = hexEncodedGroupPublicKey
                    (plaintext, sender) = try decrypt(keyPairs: encryptionKeyPairs)
                
                default: throw MessageReceiverError.unknownEnvelopeType
            }
        }
        
        // Don't process the envelope any further if the sender is blocked
        guard (try? Contact.fetchOne(db, id: sender))?.isBlocked != true else {
            throw MessageReceiverError.senderBlocked
        }
        
        // Parse the proto
        let proto: SNProtoContent
        
        do {
            proto = try SNProtoContent.parseData(plaintext.removePadding())
        }
        catch {
            SNLog("Couldn't parse proto due to error: \(error).")
            throw error
        }
        
        // Parse the message
        guard let message: Message = Message.createMessageFrom(proto, sender: sender) else {
            throw MessageReceiverError.unknownMessage
        }
        
        // Ignore self sends if needed
        guard message.isSelfSendValid || sender != userPublicKey else {
            throw MessageReceiverError.selfSend
        }
        
        // Guard against control messages in open groups
        guard !isOpenGroupMessage || message is VisibleMessage else {
            throw MessageReceiverError.invalidMessage
        }
        
        // Finish parsing
        message.sender = sender
        message.recipient = userPublicKey
        message.sentTimestamp = envelope.timestamp
        message.receivedTimestamp = UInt64((Date().timeIntervalSince1970) * 1000)
        message.groupPublicKey = groupPublicKey
        message.openGroupServerMessageId = openGroupMessageServerId.map { UInt64($0) }
        
        // Validate
        var isValid: Bool = message.isValid
        if message is VisibleMessage && !isValid && proto.dataMessage?.attachments.isEmpty == false {
            isValid = true
        }
        
        guard isValid else {
            throw MessageReceiverError.invalidMessage
        }
        
        // Extract the proper threadId for the message
        let threadId: String = {
            if let groupPublicKey: String = groupPublicKey { return groupPublicKey }
            if let openGroupId: String = openGroupId { return openGroupId }
            
            switch message {
                case let message as VisibleMessage: return (message.syncTarget ?? sender)
                case let message as ExpirationTimerUpdate: return (message.syncTarget ?? sender)
                default: return sender
            }
        }()
        
        return (message, proto, threadId)
    }
    
    // MARK: - Handling
    
    public static func handle(
        _ db: Database,
        message: Message,
        associatedWithProto proto: SNProtoContent,
        openGroupId: String?,
        dependencies: SMKDependencies = SMKDependencies()
    ) throws {
        switch message {
            case let message as ReadReceipt:
                try MessageReceiver.handleReadReceipt(db, message: message)
                
            case let message as TypingIndicator:
                try MessageReceiver.handleTypingIndicator(db, message: message)
                
            case let message as ClosedGroupControlMessage:
                try MessageReceiver.handleClosedGroupControlMessage(db, message)
                
            case let message as DataExtractionNotification:
                try MessageReceiver.handleDataExtractionNotification(db, message: message)
                
            case let message as ExpirationTimerUpdate:
                try MessageReceiver.handleExpirationTimerUpdate(db, message: message)
                
            case let message as ConfigurationMessage:
                try MessageReceiver.handleConfigurationMessage(db, message: message)
                
            case let message as UnsendRequest:
                try MessageReceiver.handleUnsendRequest(db, message: message)
                
            case let message as CallMessage:
                try MessageReceiver.handleCallMessage(db, message: message)
                
            case let message as MessageRequestResponse:
                try MessageReceiver.handleMessageRequestResponse(db, message: message, dependencies: dependencies)
                
            case let message as VisibleMessage:
                try MessageReceiver.handleVisibleMessage(
                    db,
                    message: message,
                    associatedWithProto: proto,
                    openGroupId: openGroupId
                )
                
            default: fatalError()
        }
        
        // Perform any required post-handling logic
        try MessageReceiver.postHandleMessage(db, message: message, openGroupId: openGroupId)
    }
    
    public static func postHandleMessage(
        _ db: Database,
        message: Message,
        openGroupId: String?
    ) throws {
        // When handling any non-typing indicator message we want to make sure the thread becomes
        // visible (the only other spot this flag gets set is when sending messages)
        switch message {
            case is TypingIndicator: break
                
            default:
                guard let threadInfo: (id: String, variant: SessionThread.Variant) = threadInfo(db, message: message, openGroupId: openGroupId) else {
                    return
                }
                
                _ = try SessionThread
                    .fetchOrCreate(db, id: threadInfo.id, variant: threadInfo.variant)
                    .with(shouldBeVisible: true)
                    .saved(db)
        }
    }
    
    public static func handleOpenGroupReactions(
        _ db: Database,
        threadId: String,
        openGroupMessageServerId: Int64,
        openGroupReactions: [Reaction]
    ) throws {
        guard let interactionId: Int64 = try? Interaction
            .select(.id)
            .filter(Interaction.Columns.threadId == threadId)
            .filter(Interaction.Columns.openGroupServerMessageId == openGroupMessageServerId)
            .asRequest(of: Int64.self)
            .fetchOne(db)
        else {
            throw MessageReceiverError.invalidMessage
        }
        
        _ = try Reaction
            .filter(Reaction.Columns.interactionId == interactionId)
            .deleteAll(db)
        
        for reaction in openGroupReactions {
            try reaction.with(interactionId: interactionId).insert(db)
        }
    }
    
    // MARK: - Convenience
    
    internal static func threadInfo(_ db: Database, message: Message, openGroupId: String?) -> (id: String, variant: SessionThread.Variant)? {
        if let openGroupId: String = openGroupId {
            // Note: We don't want to create a thread for an open group if it doesn't exist
            if (try? SessionThread.exists(db, id: openGroupId)) != true { return nil }
            
            return (openGroupId, .openGroup)
        }
        
        if let groupPublicKey: String = message.groupPublicKey {
            // Note: We don't want to create a thread for a closed group if it doesn't exist
            if (try? SessionThread.exists(db, id: groupPublicKey)) != true { return nil }
            
            return (groupPublicKey, .closedGroup)
        }
        
        // Extract the 'syncTarget' value if there is one
        let maybeSyncTarget: String?
        
        switch message {
            case let message as VisibleMessage: maybeSyncTarget = message.syncTarget
            case let message as ExpirationTimerUpdate: maybeSyncTarget = message.syncTarget
            default: maybeSyncTarget = nil
        }
        
        // Note: We don't want to create a thread for a closed group if it doesn't exist
        guard let contactId: String = (maybeSyncTarget ?? message.sender) else { return nil }
        
        return (contactId, .contact)
    }
    
    internal static func updateProfileIfNeeded(
        _ db: Database,
        publicKey: String,
        name: String?,
        profilePictureUrl: String?,
        profileKey: OWSAES256Key?,
        sentTimestamp: TimeInterval,
        dependencies: Dependencies = Dependencies()
    ) throws {
        let isCurrentUser = (publicKey == getUserHexEncodedPublicKey(db, dependencies: dependencies))
        let profile: Profile = Profile.fetchOrCreate(id: publicKey)
        var updatedProfile: Profile = profile
        
        // Name
        if let name = name, name != profile.name {
            let shouldUpdate: Bool
            if isCurrentUser {
                shouldUpdate = given(UserDefaults.standard[.lastDisplayNameUpdate]) {
                    sentTimestamp > $0.timeIntervalSince1970
                }
                .defaulting(to: true)
            }
            else {
                shouldUpdate = true
            }
            
            if shouldUpdate {
                if isCurrentUser {
                    UserDefaults.standard[.lastDisplayNameUpdate] = Date(timeIntervalSince1970: sentTimestamp)
                }
                
                updatedProfile = updatedProfile.with(name: name)
            }
        }
        
        // Profile picture & profile key
        if
            let profileKey: OWSAES256Key = profileKey,
            let profilePictureUrl: String = profilePictureUrl,
            profileKey.keyData.count == kAES256_KeyByteLength,
            profileKey != profile.profileEncryptionKey
        {
            let shouldUpdate: Bool
            if isCurrentUser {
                shouldUpdate = given(UserDefaults.standard[.lastProfilePictureUpdate]) {
                    sentTimestamp > $0.timeIntervalSince1970
                }
                .defaulting(to: true)
            }
            else {
                shouldUpdate = true
            }
            
            if shouldUpdate {
                if isCurrentUser {
                    UserDefaults.standard[.lastProfilePictureUpdate] = Date(timeIntervalSince1970: sentTimestamp)
                }
                
                updatedProfile = updatedProfile.with(
                    profilePictureUrl: .update(profilePictureUrl),
                    profileEncryptionKey: .update(profileKey)
                )
            }
        }
        
        // Persist any changes
        if updatedProfile != profile {
            try updatedProfile.save(db)
        }
        
        // Download the profile picture if needed
        if updatedProfile.profilePictureUrl != profile.profilePictureUrl || updatedProfile.profileEncryptionKey != profile.profileEncryptionKey {
            db.afterNextTransactionCommit { _ in
                ProfileManager.downloadAvatar(for: updatedProfile)
            }
        }
    }
}
