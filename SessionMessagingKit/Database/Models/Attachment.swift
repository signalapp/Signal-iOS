// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Attachment: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "attachment" }
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    internal static let quoteForeignKey = ForeignKey([Columns.quoteId], to: [Quote.Columns.interactionId])
    internal static let linkPreviewForeignKey = ForeignKey(
        [Columns.linkPreviewUrl],
        to: [LinkPreview.Columns.url]
    )
    private static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    private static let quote = belongsTo(Quote.self, using: quoteForeignKey)
    private static let linkPreview = belongsTo(LinkPreview.self, using: linkPreviewForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case interactionId
        case serverId
        case variant
        case state
        case contentType
        case byteCount
        case creationTimestamp
        case sourceFilename
        case downloadUrl
        case width
        case height
        case encryptionKey
        case digest
        case caption
        case quoteId
        case linkPreviewUrl
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        case standard
        case voiceMessage
    }
    
    public enum State: Int, Codable, DatabaseValueConvertible {
        case pending
        case downloading
        case downloaded
        case uploading
        case uploaded
        case failed
    }
    
    /// The id for the interaction this attachment belongs to
    public let interactionId: Int64
    
    /// The id for the attachment returned by the server
    ///
    /// This will be null for attachments which haven’t completed uploading
    ///
    /// **Note:** This value is not unique as multiple SOGS could end up having the same file id
    public let serverId: String?
    
    /// The type of this attachment, used to distinguish logic handling
    public let variant: Variant
    
    /// The current state of the attachment
    public let state: State
    
    /// The MIMEType for the attachment
    public let contentType: String
    
    /// The size of the attachment in bytes
    ///
    /// **Note:** This may be `0` for some legacy attachments
    public let byteCount: UInt
    
    /// Timestamp in seconds since epoch for when this attachment was created
    ///
    /// **Uploaded:** This will be the timestamp the file finished uploading
    /// **Downloaded:** This will be the timestamp the file finished downloading
    public let creationTimestamp: TimeInterval?
    
    /// Represents the "source" filename sent or received in the protos, not the filename on disk
    public let sourceFilename: String?
    
    /// The url the attachment can be downloaded from, this will be `null` for attachments which haven’t yet been uploaded
    ///
    /// **Note:** The url is a fully constructed url but the clients just extract the id from the end of the url to perform the actual download
    public let downloadUrl: String?
    
    /// The width of the attachment, this will be `null` for non-visual attachment types
    public let width: UInt?
    
    /// The height of the attachment, this will be `null` for non-visual attachment types
    public let height: UInt?
    
    /// The key used to decrypt the attachment
    public let encryptionKey: Data?
    
    /// The computed digest for the attachment (generated from `iv || encrypted data || hmac`)
    public let digest: Data?
    
    /// Caption for the attachment
    public let caption: String?
    
    /// The id for the QuotedMessage if this attachment belongs to one
    ///
    /// **Note:** If this value is present then this attachment shouldn't be returned as a
    /// standard attachment for the interaction
    public let quoteId: String?
    
    /// The id for the LinkPreview if this attachment belongs to one
    ///
    /// **Note:** If this value is present then this attachment shouldn't be returned as a
    /// standard attachment for the interaction
    public let linkPreviewUrl: String?
    
    // MARK: - Relationships
    
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: Attachment.interaction)
    }
    
    public var quote: QueryInterfaceRequest<Quote> {
        request(for: Attachment.quote)
    }
    
    public var linkPreview: QueryInterfaceRequest<LinkPreview> {
        request(for: Attachment.linkPreview)
    }
}
