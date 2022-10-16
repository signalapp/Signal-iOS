// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionSnodeKit
import SessionUtilitiesKit

/// Abstract base class for `VisibleMessage` and `ControlMessage`.
public class Message: Codable {
    public var id: String?
    public var threadId: String?
    public var sentTimestamp: UInt64?
    public var receivedTimestamp: UInt64?
    public var recipient: String?
    public var sender: String?
    public var groupPublicKey: String?
    public var openGroupServerMessageId: UInt64?
    public var serverHash: String?

    public var ttl: UInt64 { 14 * 24 * 60 * 60 * 1000 }
    public var isSelfSendValid: Bool { false }
    
    public var shouldBeRetryable: Bool { false }

    // MARK: - Validation
    
    public var isValid: Bool {
        if let sentTimestamp = sentTimestamp { guard sentTimestamp > 0 else { return false } }
        if let receivedTimestamp = receivedTimestamp { guard receivedTimestamp > 0 else { return false } }
        return sender != nil && recipient != nil
    }
    
    // MARK: - Initialization
    
    public init(
        id: String? = nil,
        threadId: String? = nil,
        sentTimestamp: UInt64? = nil,
        receivedTimestamp: UInt64? = nil,
        recipient: String? = nil,
        sender: String? = nil,
        groupPublicKey: String? = nil,
        openGroupServerMessageId: UInt64? = nil,
        serverHash: String? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.sentTimestamp = sentTimestamp
        self.receivedTimestamp = receivedTimestamp
        self.recipient = recipient
        self.sender = sender
        self.groupPublicKey = groupPublicKey
        self.openGroupServerMessageId = openGroupServerMessageId
        self.serverHash = serverHash
    }

    // MARK: - Proto Conversion
    
    public class func fromProto(_ proto: SNProtoContent, sender: String) -> Self? {
        preconditionFailure("fromProto(_:sender:) is abstract and must be overridden.")
    }

    public func toProto(_ db: Database) -> SNProtoContent? {
        preconditionFailure("toProto(_:) is abstract and must be overridden.")
    }

    public func setGroupContextIfNeeded(_ db: Database, on dataMessage: SNProtoDataMessage.SNProtoDataMessageBuilder) throws {
        guard
            let threadId: String = threadId,
            (try? ClosedGroup.exists(db, id: threadId)) == true,
            let legacyGroupId: Data = "\(SMKLegacy.closedGroupIdPrefix)\(threadId)".data(using: .utf8)
        else { return }
        
        // Android needs a group context or it'll interpret the message as a one-to-one message
        let groupProto = SNProtoGroupContext.builder(id: legacyGroupId, type: .deliver)
        dataMessage.setGroup(try groupProto.build())
    }
}

// MARK: - Message Parsing/Processing

public typealias ProcessedMessage = (
    threadId: String?,
    proto: SNProtoContent,
    messageInfo: MessageReceiveJob.Details.MessageInfo
)

public extension Message {
    static let nonThreadMessageId: String = "NON_THREAD_MESSAGE"
    
    enum Variant: String, Codable {
        case readReceipt
        case typingIndicator
        case closedGroupControlMessage
        case dataExtractionNotification
        case expirationTimerUpdate
        case configurationMessage
        case unsendRequest
        case messageRequestResponse
        case visibleMessage
        case callMessage
        
        init?(from type: Message) {
            switch type {
                case is ReadReceipt: self = .readReceipt
                case is TypingIndicator: self = .typingIndicator
                case is ClosedGroupControlMessage: self = .closedGroupControlMessage
                case is DataExtractionNotification: self = .dataExtractionNotification
                case is ExpirationTimerUpdate: self = .expirationTimerUpdate
                case is ConfigurationMessage: self = .configurationMessage
                case is UnsendRequest: self = .unsendRequest
                case is MessageRequestResponse: self = .messageRequestResponse
                case is VisibleMessage: self = .visibleMessage
                case is CallMessage: self = .callMessage
                default: return nil
            }
        }
        
        var messageType: Message.Type {
            switch self {
                case .readReceipt: return ReadReceipt.self
                case .typingIndicator: return TypingIndicator.self
                case .closedGroupControlMessage: return ClosedGroupControlMessage.self
                case .dataExtractionNotification: return DataExtractionNotification.self
                case .expirationTimerUpdate: return ExpirationTimerUpdate.self
                case .configurationMessage: return ConfigurationMessage.self
                case .unsendRequest: return UnsendRequest.self
                case .messageRequestResponse: return MessageRequestResponse.self
                case .visibleMessage: return VisibleMessage.self
                case .callMessage: return CallMessage.self
            }
        }

        func decode<CodingKeys: CodingKey>(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Message {
            switch self {
                case .readReceipt: return try container.decode(ReadReceipt.self, forKey: key)
                case .typingIndicator: return try container.decode(TypingIndicator.self, forKey: key)
                
                case .closedGroupControlMessage:
                    return try container.decode(ClosedGroupControlMessage.self, forKey: key)
                    
                case .dataExtractionNotification:
                    return try container.decode(DataExtractionNotification.self, forKey: key)
                    
                case .expirationTimerUpdate: return try container.decode(ExpirationTimerUpdate.self, forKey: key)
                case .configurationMessage: return try container.decode(ConfigurationMessage.self, forKey: key)
                case .unsendRequest: return try container.decode(UnsendRequest.self, forKey: key)
                case .messageRequestResponse: return try container.decode(MessageRequestResponse.self, forKey: key)
                case .visibleMessage: return try container.decode(VisibleMessage.self, forKey: key)
                case .callMessage: return try container.decode(CallMessage.self, forKey: key)
            }
        }
    }
    
    static func createMessageFrom(_ proto: SNProtoContent, sender: String) -> Message? {
        // Note: This array is ordered intentionally to ensure the correct types are processed
        // and aren't parsed as the wrong type
        let prioritisedVariants: [Variant] = [
            .readReceipt,
            .typingIndicator,
            .closedGroupControlMessage,
            .dataExtractionNotification,
            .expirationTimerUpdate,
            .configurationMessage,
            .unsendRequest,
            .messageRequestResponse,
            .visibleMessage,
            .callMessage
        ]
        
        return prioritisedVariants
            .reduce(nil) { prev, variant in
                guard prev == nil else { return prev }
                
                return variant.messageType.fromProto(proto, sender: sender)
            }
    }
    
    static func shouldSync(message: Message) -> Bool {
        switch message {
            case let controlMessage as ClosedGroupControlMessage:
                switch controlMessage.kind {
                    case .new: return true
                    default: return false
                }
                
            case let callMessage as CallMessage:
                switch callMessage.kind {
                    case .answer, .endCall: return true
                    default: return false
                }
                
            case is ConfigurationMessage: return true
            case is UnsendRequest: return true
            default: return false
        }
    }
    
    static func processRawReceivedMessage(
        _ db: Database,
        rawMessage: SnodeReceivedMessage
    ) throws -> ProcessedMessage? {
        guard let envelope = SNProtoEnvelope.from(rawMessage) else {
            throw MessageReceiverError.invalidMessage
        }
        
        do {
            let processedMessage: ProcessedMessage? = try processRawReceivedMessage(
                db,
                envelope: envelope,
                serverExpirationTimestamp: (TimeInterval(rawMessage.info.expirationDateMs) / 1000),
                serverHash: rawMessage.info.hash,
                handleClosedGroupKeyUpdateMessages: true
            )
            
            // Retrieve the number of entries we have for the hash of this message
            let numExistingHashes: Int = (try? SnodeReceivedMessageInfo
                .filter(SnodeReceivedMessageInfo.Columns.hash == rawMessage.info.hash)
                .fetchCount(db))
                .defaulting(to: 0)
            
            // Try to insert the raw message info into the database (used for both request paging and
            // de-duping purposes)
            _ = try rawMessage.info.inserted(db)
            
            // If the above insertion worked then we hadn't processed this message for this specific
            // service node, but may have done so for another node - if the hash already existed in
            // the database before we inserted it for this node then we can ignore this message as a
            // duplicate
            guard numExistingHashes == 0 else { throw MessageReceiverError.duplicateMessageNewSnode }
            
            return processedMessage
        }
        catch {
            // If we get 'selfSend' or 'duplicateControlMessage' errors then we still want to insert
            // the SnodeReceivedMessageInfo to prevent retrieving and attempting to process the same
            // message again (as well as ensure the next poll doesn't retrieve the same message)
            switch error {
                case MessageReceiverError.selfSend, MessageReceiverError.duplicateControlMessage:
                    _ = try? rawMessage.info.inserted(db)
                    break
                
                default: break
            }
            
            throw error
        }
    }
    
    static func processRawReceivedMessage(
        _ db: Database,
        serializedData: Data,
        serverHash: String?
    ) throws -> ProcessedMessage? {
        guard let envelope = try? SNProtoEnvelope.parseData(serializedData) else {
            throw MessageReceiverError.invalidMessage
        }
        
        return try processRawReceivedMessage(
            db,
            envelope: envelope,
            serverExpirationTimestamp: (Date().timeIntervalSince1970 + ControlMessageProcessRecord.defaultExpirationSeconds),
            serverHash: serverHash,
            handleClosedGroupKeyUpdateMessages: true
        )
    }
    
    /// This method behaves slightly differently from the other `processRawReceivedMessage` methods as it doesn't
    /// insert the "message info" for deduping (we want the poller to re-process the message) and also avoids handling any
    /// closed group key update messages (the `NotificationServiceExtension` does this itself)
    static func processRawReceivedMessageAsNotification(
        _ db: Database,
        envelope: SNProtoEnvelope
    ) throws -> ProcessedMessage? {
        let processedMessage: ProcessedMessage? = try processRawReceivedMessage(
            db,
            envelope: envelope,
            serverExpirationTimestamp: (Date().timeIntervalSince1970 + ControlMessageProcessRecord.defaultExpirationSeconds),
            serverHash: nil,
            handleClosedGroupKeyUpdateMessages: false
        )
        
        return processedMessage
    }
    
    static func processReceivedOpenGroupMessage(
        _ db: Database,
        openGroupId: String,
        openGroupServerPublicKey: String,
        message: OpenGroupAPI.Message,
        data: Data,
        dependencies: SMKDependencies = SMKDependencies()
    ) throws -> ProcessedMessage? {
        // Need a sender in order to process the message
        guard let sender: String = message.sender, let timestamp = message.posted else { return nil }
        
        // Note: The `posted` value is in seconds but all messages in the database use milliseconds for timestamps
        let envelopeBuilder = SNProtoEnvelope.builder(type: .sessionMessage, timestamp: UInt64(floor(timestamp * 1000)))
        envelopeBuilder.setContent(data)
        envelopeBuilder.setSource(sender)
        
        guard let envelope = try? envelopeBuilder.build() else {
            throw MessageReceiverError.invalidMessage
        }
        
        return try processRawReceivedMessage(
            db,
            envelope: envelope,
            serverExpirationTimestamp: nil,
            serverHash: nil,
            openGroupId: openGroupId,
            openGroupMessageServerId: message.id,
            openGroupServerPublicKey: openGroupServerPublicKey,
            handleClosedGroupKeyUpdateMessages: false,
            dependencies: dependencies
        )
    }
    
    static func processReceivedOpenGroupDirectMessage(
        _ db: Database,
        openGroupServerPublicKey: String,
        message: OpenGroupAPI.DirectMessage,
        data: Data,
        isOutgoing: Bool? = nil,
        otherBlindedPublicKey: String? = nil,
        dependencies: SMKDependencies = SMKDependencies()
    ) throws -> ProcessedMessage? {
        // Note: The `posted` value is in seconds but all messages in the database use milliseconds for timestamps
        let envelopeBuilder = SNProtoEnvelope.builder(type: .sessionMessage, timestamp: UInt64(floor(message.posted * 1000)))
        envelopeBuilder.setContent(data)
        envelopeBuilder.setSource(message.sender)
        
        guard let envelope = try? envelopeBuilder.build() else {
            throw MessageReceiverError.invalidMessage
        }
        
        return try processRawReceivedMessage(
            db,
            envelope: envelope,
            serverExpirationTimestamp: nil,
            serverHash: nil,
            openGroupId: nil,   // Explicitly null since it shouldn't be handled as an open group message
            openGroupMessageServerId: message.id,
            openGroupServerPublicKey: openGroupServerPublicKey,
            isOutgoing: isOutgoing,
            otherBlindedPublicKey: otherBlindedPublicKey,
            handleClosedGroupKeyUpdateMessages: false,
            dependencies: dependencies
        )
    }
    
    static func processRawReceivedReactions(
        _ db: Database,
        openGroupId: String,
        message: OpenGroupAPI.Message,
        associatedPendingChanges: [OpenGroupAPI.PendingChange],
        dependencies: SMKDependencies = SMKDependencies()
    ) -> [Reaction] {
        var results: [Reaction] = []
        guard let reactions = message.reactions else { return results }
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        let blindedUserPublicKey: String? = SessionThread
            .getUserHexEncodedBlindedKey(
                threadId: openGroupId,
                threadVariant: .openGroup
            )
        for (encodedEmoji, rawReaction) in reactions {
            if let decodedEmoji = encodedEmoji.removingPercentEncoding,
               rawReaction.count > 0,
               let reactors = rawReaction.reactors
            {
                // Decide whether we need to ignore all reactions
                let pendingChangeRemoveAllReaction: Bool = associatedPendingChanges.contains { pendingChange in
                    if case .reaction(_, let emoji, let action) = pendingChange.metadata {
                        return emoji == decodedEmoji && action == .removeAll
                    }
                    return false
                }
                
                // Decide whether we need to add an extra reaction from current user
                let pendingChangeSelfReaction: Bool? = {
                    // Find the newest 'PendingChange' entry with a matching emoji, if one exists, and
                    // set the "self reaction" value based on it's action
                    let maybePendingChange: OpenGroupAPI.PendingChange? = associatedPendingChanges
                        .sorted(by: { lhs, rhs -> Bool in (lhs.seqNo ?? Int64.max) >= (rhs.seqNo ?? Int64.max) })
                        .first { pendingChange in
                            if case .reaction(_, let emoji, _) = pendingChange.metadata {
                                return emoji == decodedEmoji
                            }
                            
                            return false
                        }
                    
                    // If there is no pending change for this reaction then return nil
                    guard
                        let pendingChange: OpenGroupAPI.PendingChange = maybePendingChange,
                        case .reaction(_, _, let action) = pendingChange.metadata
                    else { return nil }

                    // Otherwise add/remove accordingly
                    return action == .add
                }()
                let shouldAddSelfReaction: Bool = (
                    pendingChangeSelfReaction ??
                    ((rawReaction.you || reactors.contains(userPublicKey)) && !pendingChangeRemoveAllReaction)
                )
                
                let count: Int64 = rawReaction.you ? rawReaction.count - 1 : rawReaction.count
                
                let timestampMs: Int64 = Int64(floor((Date().timeIntervalSince1970 * 1000)))
                let maxLength: Int = shouldAddSelfReaction ? 4 : 5
                let desiredReactorIds: [String] = reactors
                    .filter { $0 != blindedUserPublicKey && $0 != userPublicKey } // Remove current user for now, will add back if needed
                    .prefix(maxLength)
                    .map{ $0 }

                results = results
                    .appending( // Add the first reaction (with the count)
                        pendingChangeRemoveAllReaction ?
                        nil :
                        desiredReactorIds.first
                            .map { reactor in
                                Reaction(
                                    interactionId: message.id,
                                    serverHash: nil,
                                    timestampMs: timestampMs,
                                    authorId: reactor,
                                    emoji: decodedEmoji,
                                    count: count,
                                    sortId: rawReaction.index
                                )
                            }
                    )
                    .appending( // Add all other reactions
                        contentsOf: desiredReactorIds.count <= 1 || pendingChangeRemoveAllReaction ?
                            [] :
                            desiredReactorIds
                                .suffix(from: 1)
                                .map { reactor in
                                    Reaction(
                                        interactionId: message.id,
                                        serverHash: nil,
                                        timestampMs: timestampMs,
                                        authorId: reactor,
                                        emoji: decodedEmoji,
                                        count: 0,   // Only want this on the first reaction
                                        sortId: rawReaction.index
                                    )
                                }
                    )
                    .appending( // Add the current user reaction (if applicable and not already included)
                        !shouldAddSelfReaction ?
                            nil :
                            Reaction(
                                interactionId: message.id,
                                serverHash: nil,
                                timestampMs: timestampMs,
                                authorId: userPublicKey,
                                emoji: decodedEmoji,
                                count: 1,
                                sortId: rawReaction.index
                            )
                    )
            }
        }
        return results
    }
    
    private static func processRawReceivedMessage(
        _ db: Database,
        envelope: SNProtoEnvelope,
        serverExpirationTimestamp: TimeInterval?,
        serverHash: String?,
        openGroupId: String? = nil,
        openGroupMessageServerId: Int64? = nil,
        openGroupServerPublicKey: String? = nil,
        isOutgoing: Bool? = nil,
        otherBlindedPublicKey: String? = nil,
        handleClosedGroupKeyUpdateMessages: Bool,
        dependencies: SMKDependencies = SMKDependencies()
    ) throws -> ProcessedMessage? {
        let (message, proto, threadId) = try MessageReceiver.parse(
            db,
            envelope: envelope,
            serverExpirationTimestamp: serverExpirationTimestamp,
            openGroupId: openGroupId,
            openGroupMessageServerId: openGroupMessageServerId,
            openGroupServerPublicKey: openGroupServerPublicKey,
            isOutgoing: isOutgoing,
            otherBlindedPublicKey: otherBlindedPublicKey,
            dependencies: dependencies
        )
        message.serverHash = serverHash
        
        // Ignore invalid messages and hashes for messages we have previously handled
        guard let variant: Message.Variant = Message.Variant(from: message) else {
            throw MessageReceiverError.invalidMessage
        }
        
        /// **Note:** We want to immediately handle any `ClosedGroupControlMessage` with the kind `encryptionKeyPair` as
        /// we need the keyPair in storage in order to be able to parse and messages which were signed with the new key (also no need to add
        /// these as jobs as they will be fully handled in here)
        if handleClosedGroupKeyUpdateMessages {
            switch message {
                case let closedGroupControlMessage as ClosedGroupControlMessage:
                    switch closedGroupControlMessage.kind {
                        case .encryptionKeyPair:
                            try MessageReceiver.handleClosedGroupControlMessage(db, closedGroupControlMessage)
                            return nil
                            
                        default: break
                    }
                
                default: break
            }
        }
        
        // Prevent ControlMessages from being handled multiple times if not supported
        do {
            try ControlMessageProcessRecord(
                threadId: threadId,
                message: message,
                serverExpirationTimestamp: serverExpirationTimestamp
            )?.insert(db)
        }
        catch {
            // We want to custom handle this 
            if case DatabaseError.SQLITE_CONSTRAINT_UNIQUE = error {
                throw MessageReceiverError.duplicateControlMessage
            }
            
            throw error
        }
        
        return (
            threadId,
            proto,
            try MessageReceiveJob.Details.MessageInfo(
                message: message,
                variant: variant,
                proto: proto
            )
        )
    }
}

// MARK: - Mutation

internal extension Message {
    func with(sentTimestamp: UInt64) -> Message {
        self.sentTimestamp = sentTimestamp
        return self
    }
}
