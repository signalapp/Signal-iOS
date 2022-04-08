// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Quote: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "quote" }
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    internal static let originalInteractionForeignKey = ForeignKey(
        [Columns.timestampMs, Columns.authorId],
        to: [Interaction.Columns.timestampMs, Interaction.Columns.authorId]
    )
    internal static let profileForeignKey = ForeignKey([Columns.authorId], to: [Profile.Columns.id])
    private static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    private static let attachment = hasOne(Attachment.self, using: Attachment.quoteForeignKey)
    private static let quotedInteraction = hasOne(Interaction.self, using: originalInteractionForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case interactionId
        case authorId
        case timestampMs
        case body
    }
    
    /// The id for the interaction this Quote belongs to
    public let interactionId: Int64
    
    /// The id for the author this Quote belongs to
    public let authorId: String
    
    /// The timestamp in milliseconds since epoch when the quoted interaction was sent
    public let timestampMs: Double
    
    /// The body of the quoted message if the user is quoting a text message or an attachment with a caption
    public let body: String?
    
    // MARK: - Relationships
    
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: Quote.interaction)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: Quote.profile)
    }
    
    public var attachment: QueryInterfaceRequest<Attachment> {
        request(for: Quote.attachment)
    }
    
    public var originalInteraction: QueryInterfaceRequest<Interaction> {
        request(for: Quote.quotedInteraction)
    }
}
