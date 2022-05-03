// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit
import SessionUtilitiesKit

public struct RecipientState: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "recipientState" }
    internal static let profileForeignKey = ForeignKey([Columns.recipientId], to: [Profile.Columns.id])
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    internal static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case interactionId
        case recipientId
        case state
        case readTimestampMs
        case mostRecentFailureText
    }
    
    public enum State: Int, Codable, DatabaseValueConvertible {
        case failed
        case sending
        case skipped
        case sent
        
        func message(hasAttachments: Bool, hasAtLeastOneReadReceipt: Bool) -> String {
            switch self {
                case .failed: return "MESSAGE_STATUS_FAILED".localized()
                case .sending:
                    guard hasAttachments else {
                        return "MESSAGE_STATUS_SENDING".localized()
                    }
                    
                    return "MESSAGE_STATUS_UPLOADING".localized()
                    
                case .sent:
                    guard hasAtLeastOneReadReceipt else {
                        return "MESSAGE_STATUS_SENT".localized()
                    }
                    
                    return "MESSAGE_STATUS_READ".localized()
                    
                default:
                    owsFailDebug("Message has unexpected status: \(self).")
                    return "MESSAGE_STATUS_SENT".localized()
            }
        }
    }
    
    /// The id for the interaction this state belongs to
    public let interactionId: Int64
    
    /// The id for the recipient that has this state
    ///
    /// **Note:** For contact and closedGroup threads this can be used as a lookup for a contact/profile but in an
    /// openGroup thread this will be the threadId so won’t resolve to a contact/profile
    public let recipientId: String
    
    /// The current state for the recipient
    public let state: State
    
    /// When the interaction was read in milliseconds since epoch
    ///
    /// This value will be null for outgoing messages
    ///
    /// **Note:** This currently will be set when opening the thread for the first time after receiving this interaction
    /// rather than when the interaction actually appears on the screen
    public let readTimestampMs: Int64?
    
    public let mostRecentFailureText: String?
    
    // MARK: - Relationships
         
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: RecipientState.interaction)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: RecipientState.profile)
    }
    
    // MARK: - Initialization
    
    public init(
        interactionId: Int64,
        recipientId: String,
        state: State,
        readTimestampMs: Int64? = nil,
        mostRecentFailureText: String? = nil
    ) {
        self.interactionId = interactionId
        self.recipientId = recipientId
        self.state = state
        self.readTimestampMs = readTimestampMs
        self.mostRecentFailureText = mostRecentFailureText
    }
}

// MARK: - Mutation

public extension RecipientState {
    func with(
        state: State? = nil,
        readTimestampMs: Int64? = nil,
        mostRecentFailureText: String? = nil
    ) -> RecipientState {
        return RecipientState(
            interactionId: interactionId,
            recipientId: recipientId,
            state: (state ?? self.state),
            readTimestampMs: (readTimestampMs ?? self.readTimestampMs),
            mostRecentFailureText: (mostRecentFailureText ?? self.mostRecentFailureText)
        )
    }
}
