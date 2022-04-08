// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct LinkPreview: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "linkPreview" }
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    private static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    private static let attachment = hasOne(Attachment.self, using: Attachment.linkPreviewForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case url
        case interactionId
        case title
    }
    
    /// The url for the link preview
    public let url: String
    
    /// The id for the interaction this LinkPreview belongs to
    public let interactionId: Int64
    
    /// The title for the link
    public let title: String?
    
    // MARK: - Relationships
    
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: LinkPreview.interaction)
    }
    
    public var attachment: QueryInterfaceRequest<Attachment> {
        request(for: LinkPreview.attachment)
    }
}
