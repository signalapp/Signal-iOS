// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct InteractionAttachment: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "interactionAttachment" }
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    internal static let attachmentForeignKey = ForeignKey([Columns.attachmentId], to: [Attachment.Columns.id])
    public static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    internal static let attachment = belongsTo(Attachment.self, using: attachmentForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case albumIndex
        case interactionId
        case attachmentId
    }
    
    public let albumIndex: Int
    public let interactionId: Int64
    public let attachmentId: String
    
    // MARK: - Relationships
         
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: InteractionAttachment.interaction)
    }
    
    public var attachment: QueryInterfaceRequest<Attachment> {
        request(for: InteractionAttachment.attachment)
    }
    
    // MARK: - Initialization
    
    public init(
        albumIndex: Int,
        interactionId: Int64,
        attachmentId: String
    ) {
        self.albumIndex = albumIndex
        self.interactionId = interactionId
        self.attachmentId = attachmentId
    }
}
