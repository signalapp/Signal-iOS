// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Quote: Codable, Equatable, Hashable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "quote" }
    public static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    internal static let originalInteractionForeignKey = ForeignKey(
        [Columns.timestampMs, Columns.authorId],
        to: [Interaction.Columns.timestampMs, Interaction.Columns.authorId]
    )
    internal static let profileForeignKey = ForeignKey([Columns.authorId], to: [Profile.Columns.id])
    internal static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    private static let quotedInteraction = hasOne(Interaction.self, using: originalInteractionForeignKey)
    public static let attachment = hasOne(Attachment.self, using: Attachment.quoteForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case interactionId
        case authorId
        case timestampMs
        case body
        case attachmentId
    }
    
    /// The id for the interaction this Quote belongs to
    public let interactionId: Int64
    
    /// The id for the author this Quote belongs to
    public let authorId: String
    
    /// The timestamp in milliseconds since epoch when the quoted interaction was sent
    public let timestampMs: Int64
    
    /// The body of the quoted message if the user is quoting a text message or an attachment with a caption
    public let body: String?
    
    /// The id for the attachment this Quote is associated with
    public let attachmentId: String?
    
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
    
    // MARK: - Interaction
    
    public init(
        interactionId: Int64,
        authorId: String,
        timestampMs: Int64,
        body: String?,
        attachmentId: String?
    ) {
        self.interactionId = interactionId
        self.authorId = authorId
        self.timestampMs = timestampMs
        self.body = body
        self.attachmentId = attachmentId
    }
}

// MARK: - Protobuf

public extension Quote {
    init?(_ db: Database, proto: SNProtoDataMessage, interactionId: Int64, thread: SessionThread) throws {
        guard
            let quoteProto = proto.quote,
            quoteProto.id != 0,
            !quoteProto.author.isEmpty
        else { return nil }
        
        self.interactionId = interactionId
        self.timestampMs = Int64(quoteProto.id)
        self.authorId = quoteProto.author

        // Prefer to generate the text snippet locally if available.
        let quotedInteraction: Interaction? = try? thread
            .interactions
            .filter(Interaction.Columns.authorId == quoteProto.author)
            .filter(Interaction.Columns.timestampMs == Double(quoteProto.id))
            .fetchOne(db)
        
        if let quotedInteraction: Interaction = quotedInteraction, quotedInteraction.body?.isEmpty == false {
            self.body = quotedInteraction.body
        }
        else if let body: String = quoteProto.text, !body.isEmpty {
            self.body = body
        }
        else {
            self.body = nil
        }
        
        // We only use the first attachment
        if let attachment = quoteProto.attachments.first(where: { $0.thumbnail != nil })?.thumbnail {
            self.attachmentId = try quotedInteraction
                .map { quotedInteraction -> Attachment? in
                    // If the quotedInteraction has an attachment then try clone it
                    if let attachment: Attachment = try? quotedInteraction.attachments.fetchOne(db) {
                        return attachment.cloneAsThumbnail()
                    }
                    
                    // Otherwise if the quotedInteraction has a link preview, try clone that
                    return try? quotedInteraction.linkPreview
                        .fetchOne(db)?
                        .attachment
                        .fetchOne(db)?
                        .cloneAsThumbnail()
                }
                .defaulting(to: Attachment(proto: attachment))
                .inserted(db)
                .id
        }
        else {
            self.attachmentId = nil
        }
        
        // Make sure the quote is valid before completing
        if self.body == nil && self.attachmentId == nil {
            return nil
        }
    }
}
