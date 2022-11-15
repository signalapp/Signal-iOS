// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// We can rely on the unique constraints within the `Interaction` table to prevent duplicate `VisibleMessage`
/// values from being processed, but some control messages don’t have an associated interaction - this table provides
/// a de-duping mechanism for those messages
///
/// **Note:** It’s entirely possible for there to be a false-positive with this record where multiple users sent the same
/// type of control message at the same time - this is very unlikely to occur though since unique to the millisecond level
public struct ControlMessageProcessRecord: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "controlMessageProcessRecord" }
    
    /// For notifications and migrated timestamps default to '15' days (which is the timeout for messages on the
    /// server at the time of writing)
    public static let defaultExpirationSeconds: TimeInterval = (15 * 24 * 60 * 60)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case threadId
        case timestampMs
        case variant
        case serverExpirationTimestamp
    }
    
    public enum Variant: Int, Codable, CaseIterable, DatabaseValueConvertible {
        /// **Note:** This value should only be used for entries created from the initial migration, when inserting
        /// new records it will check if there is an existing legacy record and if so it will attempt to create a "legacy"
        /// version of the new record to try and trip the unique constraint
        case legacyEntry = 0
        
        case readReceipt = 1
        case typingIndicator = 2
        case closedGroupControlMessage = 3
        case dataExtractionNotification = 4
        case expirationTimerUpdate = 5
        case configurationMessage = 6
        case unsendRequest = 7
        case messageRequestResponse = 8
        case call = 9
    }
    
    /// The id for the thread the control message is associated to
    ///
    /// **Note:** For user-specific control message (eg. `ConfigurationMessage`) this value will be the
    /// users public key
    public let threadId: String
    
    /// The type of control message
    ///
    /// **Note:** It would be nice to include this in the unique constraint to reduce the likelihood of false positives
    /// but this can result in control messages getting re-handled because the variant is unknown in the migration
    public let variant: Variant
    
    /// The timestamp of the control message
    public let timestampMs: Int64
    
    /// The timestamp for when this message will expire on the server (will be used for garbage collection)
    public let serverExpirationTimestamp: TimeInterval?
    
    // MARK: - Initialization
    
    public init?(
        threadId: String,
        message: Message,
        serverExpirationTimestamp: TimeInterval?
    ) {
        // All `VisibleMessage` values will have an associated `Interaction` so just let
        // the unique constraints on that table prevent duplicate messages
        if message is VisibleMessage { return nil }
        
        // Allow duplicates for UnsendRequest messages, if a user received an UnsendRequest
        // as a push notification the it wouldn't include a serverHash and, as a result,
        // wouldn't get deleted from the server - since the logic only runs if we find a
        // matching message the safest option is to allow duplicate handling to avoid an
        // edge-case where a message doesn't get deleted
        if message is UnsendRequest { return nil }
        
        // Allow duplicates for all call messages, the double checking will be done on
        // message handling to make sure the messages are for the same ongoing call
        if message is CallMessage { return nil }
        
        // Allow '.new' and 'encryptionKeyPair' closed group control message duplicates to avoid
        // the following situation:
        // • The app performed a background poll or received a push notification
        // • This method was invoked and the received message timestamps table was updated
        // • Processing wasn't finished
        // • The user doesn't see the new closed group
        if case .new = (message as? ClosedGroupControlMessage)?.kind { return nil }
        if case .encryptionKeyPair = (message as? ClosedGroupControlMessage)?.kind { return nil }
        
        // For all other cases we want to prevent duplicate handling of the message (this
        // can happen in a number of situations, primarily with sync messages though hence
        // why we don't include the 'serverHash' as part of this record
        self.threadId = threadId
        self.variant = {
            switch message {
                case is ReadReceipt: return .readReceipt
                case is TypingIndicator: return .typingIndicator
                case is ClosedGroupControlMessage: return .closedGroupControlMessage
                case is DataExtractionNotification: return .dataExtractionNotification
                case is ExpirationTimerUpdate: return .expirationTimerUpdate
                case is ConfigurationMessage: return .configurationMessage
                case is UnsendRequest: return .unsendRequest
                case is MessageRequestResponse: return .messageRequestResponse
                case is CallMessage: return .call
                default: preconditionFailure("[ControlMessageProcessRecord] Unsupported message type")
            }
        }()
        self.timestampMs = Int64(message.sentTimestamp ?? 0)   // Default to `0` if not set
        self.serverExpirationTimestamp = serverExpirationTimestamp
    }
    
    // MARK: - Custom Database Interaction
    
    public func willInsert(_ db: Database) throws {
        // If this isn't a legacy entry then check if there is a single entry and, if so,
        // try to create a "legacy entry" version of this record to see if a unique constraint
        // conflict occurs
        if !threadId.isEmpty && variant != .legacyEntry {
            let legacyEntry: ControlMessageProcessRecord? = try? ControlMessageProcessRecord
                .filter(Columns.threadId == "")
                .filter(Columns.variant == Variant.legacyEntry)
                .fetchOne(db)
            
            if legacyEntry != nil {
                try ControlMessageProcessRecord(
                    threadId: "",
                    variant: .legacyEntry,
                    timestampMs: timestampMs,
                    serverExpirationTimestamp: (legacyEntry?.serverExpirationTimestamp ?? 0)
                ).insert(db)
            }
        }
    }
}

// MARK: - Migration Extensions

internal extension ControlMessageProcessRecord {
    init?(
        threadId: String,
        variant: Interaction.Variant,
        timestampMs: Int64
    ) {
        switch variant {
            case .standardOutgoing, .standardIncoming, .standardIncomingDeleted,
                .infoClosedGroupCreated:
                return nil
                
            case .infoClosedGroupUpdated, .infoClosedGroupCurrentUserLeft:
                self.variant = .closedGroupControlMessage
            
            case .infoDisappearingMessagesUpdate:
                self.variant = .expirationTimerUpdate
            
            case .infoScreenshotNotification, .infoMediaSavedNotification:
                self.variant = .dataExtractionNotification
        
            case .infoMessageRequestAccepted:
                self.variant = .messageRequestResponse
                
            case .infoCall:
                self.variant = .call
        }
        
        self.threadId = threadId
        self.timestampMs = timestampMs
        self.serverExpirationTimestamp = (Date().timeIntervalSince1970 + ControlMessageProcessRecord.defaultExpirationSeconds)
    }
    
    /// This method should only be used for records created during migration from the legacy
    /// `receivedMessageTimestamps` collection which doesn't include thread or variant info
    ///
    /// In order to get around this but maintain the unique constraints on everything we create entries for each timestamp
    /// for every thread and every timestamp (while this is wildly inefficient there is a garbage collection process which will
    /// clean out these excessive entries after `defaultExpirationSeconds`)
    static func generateLegacyProcessRecords(_ db: Database, receivedMessageTimestamps: [Int64]) throws {
        let defaultExpirationTimestamp: TimeInterval = (
            Date().timeIntervalSince1970 + ControlMessageProcessRecord.defaultExpirationSeconds
        )
        
        try receivedMessageTimestamps.forEach { timestampMs in
            try ControlMessageProcessRecord(
                threadId: "",
                variant: .legacyEntry,
                timestampMs: timestampMs,
                serverExpirationTimestamp: defaultExpirationTimestamp
            ).insert(db)
        }
    }
    
    /// This method should only be called from either the `generateLegacyProcessRecords` method above or
    /// within the 'insert' method to maintain the unique constraint
    fileprivate init(
        threadId: String,
        variant: Variant,
        timestampMs: Int64,
        serverExpirationTimestamp: TimeInterval
    ) {
        self.threadId = threadId
        self.variant = variant
        self.timestampMs = timestampMs
        self.serverExpirationTimestamp = serverExpirationTimestamp
    }
}
