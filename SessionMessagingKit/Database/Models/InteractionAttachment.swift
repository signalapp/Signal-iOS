// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct InteractionAttachment: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "interactionAttachment" }
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    private static let attachmentForeignKey = ForeignKey([Columns.attachmentId], to: [Attachment.Columns.id])
    internal static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    internal static let attachment = belongsTo(Attachment.self, using: attachmentForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case interactionId
        case attachmentId
    }
    
    public let interactionId: Int64
    public let attachmentId: String
    
    // MARK: - Relationships
         
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: InteractionAttachment.interaction)
    }
    
    public var attachment: QueryInterfaceRequest<Attachment> {
        request(for: InteractionAttachment.attachment)
    }
    
    // MARK: - Custom Database Interaction
    
    public func delete(_ db: Database) throws -> Bool {
        // If we have an Attachment then check if this is the only type that is referencing it
        // and delete the Attachment if so
        let quoteUses: Int? = try? Quote
            .select(Quote.Columns.attachmentId)
            .filter(Quote.Columns.attachmentId == attachmentId)
            .fetchCount(db)
        let linkPreviewUses: Int? = try? LinkPreview
            .select(LinkPreview.Columns.attachmentId)
            .filter(LinkPreview.Columns.attachmentId == attachmentId)
            .fetchCount(db)
        
        if (quoteUses ?? 0) == 0 && (linkPreviewUses ?? 0) == 0 {
            try attachment.deleteAll(db)
        }
        
        return try performDelete(db)
    }
}
