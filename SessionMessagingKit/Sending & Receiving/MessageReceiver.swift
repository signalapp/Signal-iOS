// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import SessionUtilitiesKit

public enum MessageReceiver {
    private static var lastEncryptionKeyPairRequest: [String: Date] = [:]
    // TODO: Remove these (bad convention)
    public static var handleNewCallOfferMessageIfNeeded: ((CallMessage, YapDatabaseReadWriteTransaction) -> Void)?
    public static var handleOfferCallMessage: ((CallMessage) -> Void)?
    public static var handleAnswerCallMessage: ((CallMessage) -> Void)?
    public static var handleEndCallMessage: ((CallMessage) -> Void)?

    public static func parse(
        _ db: Database,
        envelope: SNProtoEnvelope,
        serverExpirationTimestamp: TimeInterval?,
        openGroupId: String?,
        openGroupMessageServerId: UInt64?,
        isOutgoing: Bool? = nil,
        otherBlindedPublicKey: String? = nil,
        dependencies: Dependencies = Dependencies()
    ) throws -> (Message, SNProtoContent, String) {
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        let isOpenGroupMessage: Bool = (openGroupMessageServerId != nil)
        
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
                            guard let userX25519KeyPair = dependencies.storage.getUserKeyPair() else {
                                throw Error.noUserX25519KeyPair
                            }
                            
                            (plaintext, sender) = try decryptWithSessionProtocol(ciphertext: ciphertext, using: userX25519KeyPair)
                            
                        case .blinded:
                            guard let otherBlindedPublicKey: String = otherBlindedPublicKey else { throw Error.noData }
                            guard let openGroupServerPublicKey: String = openGroupServerPublicKey else {
                                throw Error.invalidGroupPublicKey
                            }
                            guard let userEd25519KeyPair = dependencies.storage.getUserED25519KeyPair() else {
                                throw Error.noUserED25519KeyPair
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
            proto = try SNProtoContent.parseData((plaintext as NSData).removePadding())
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
        message.openGroupServerTimestamp = (isOpenGroupMessage ? envelope.serverTimestamp : nil)
        message.openGroupServerMessageId = openGroupMessageServerId
        
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
}
