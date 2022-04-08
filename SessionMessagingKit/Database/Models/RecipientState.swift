// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct RecipientState: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "recipientState" }
    internal static let profileForeignKey = ForeignKey([Columns.recipientId], to: [Profile.Columns.id])
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    private static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case interactionId
        case recipientId
        case state
        case readTimestampMs
    }
    
    public enum State: Int, Codable, DatabaseValueConvertible {
        case failed
        case sending
        case skipped
        case sent
    }
    
    /// The id for the interaction this state belongs to
    public let interactionId: Int64
    
    /// The id for the recipient this state belongs to
    public let recipientId: String
    
    /// The current state for the recipient
    public let state: State
    
    /// When the interaction was read in milliseconds since epoch
    ///
    /// This value will be null for outgoing messages
    ///
    /// **Note:** This currently will be set when opening the thread for the first time after receiving this interaction
    /// rather than when the interaction actually appears on the screen
    public fileprivate(set) var readTimestampMs: Double? = nil  // TODO: Add setter
    
    // MARK: - Relationships
         
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: RecipientState.interaction)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: RecipientState.profile)
    }
}
