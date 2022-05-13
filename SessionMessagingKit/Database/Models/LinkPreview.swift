// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct LinkPreview: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "linkPreview" }
    internal static let interactionForeignKey = ForeignKey(
        [Columns.url],
        to: [Interaction.Columns.linkPreviewUrl]
    )
    internal static let interactions = hasMany(Interaction.self, using: Interaction.linkPreviewForeignKey)
    public static let attachment = hasOne(Attachment.self, using: Attachment.linkPreviewForeignKey)
    
    /// We want to cache url previews to the nearest 100,000 seconds (~28 hours - simpler than 86,400) to ensure the user isn't shown a preview that is too stale
    internal static let timstampResolution: Double = 100000
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case url
        case timestamp
        case variant
        case title
        case attachmentId
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        case standard
        case openGroupInvitation
    }
    
    /// The url for the link preview
    public let url: String
    
    /// The number of seconds since epoch rounded down to the nearest 100,000 seconds (~day) - This
    /// allows us to optimise against duplicate urls without having “stale” data last too long
    public let timestamp: TimeInterval
    
    /// The type of link preview
    public let variant: Variant
    
    /// The title for the link
    public let title: String?
    
    /// The id for the attachment for the link preview image
    public let attachmentId: String?
    
    // MARK: - Relationships
    
    public var attachment: QueryInterfaceRequest<Attachment> {
        request(for: LinkPreview.attachment)
    }
    
    // MARK: - Initialization
    
    public init(
        url: String,
        timestamp: TimeInterval = LinkPreview.timestampFor(
            sentTimestampMs: (Date().timeIntervalSince1970 * 1000)  // Default to now
        ),
        variant: Variant = .standard,
        title: String?,
        attachmentId: String? = nil
    ) {
        self.url = url
        self.timestamp = timestamp
        self.variant = variant
        self.title = title
        self.attachmentId = attachmentId
    }
    
    // MARK: - Custom Database Interaction
    
    public func delete(_ db: Database) throws -> Bool {
        // If we have an Attachment then check if this is the only type that is referencing it
        // and delete the Attachment if so
        if let attachmentId: String = attachmentId {
            let interactionUses: Int? = try? InteractionAttachment
                .filter(InteractionAttachment.Columns.attachmentId == attachmentId)
                .fetchCount(db)
            let quoteUses: Int? = try? Quote
                .filter(Quote.Columns.attachmentId == attachmentId)
                .fetchCount(db)
            
            if (interactionUses ?? 0) == 0 && (quoteUses ?? 0) == 0 {
                try attachment.deleteAll(db)
            }
        }
        
        return try performDelete(db)
    }
}

// MARK: - Protobuf

public extension LinkPreview {
    init?(_ db: Database, proto: SNProtoDataMessage, body: String?, sentTimestampMs: TimeInterval) throws {
        guard OWSLinkPreview.featureEnabled else { throw LinkPreviewError.noPreview }
        guard let previewProto = proto.preview.first else { throw LinkPreviewError.noPreview }
        guard proto.attachments.count < 1 else { throw LinkPreviewError.invalidInput }
        guard URL(string: previewProto.url) != nil else { throw LinkPreviewError.invalidInput }
        guard LinkPreview.isValidLinkUrl(previewProto.url) else { throw LinkPreviewError.invalidInput }
        guard let body: String = body else { throw LinkPreviewError.invalidInput }
        guard LinkPreview.allPreviewUrls(forMessageBodyText: body).contains(previewProto.url) else {
            throw LinkPreviewError.invalidInput
        }
        
        // Try to get an existing link preview first
        let timestamp: TimeInterval = LinkPreview.timestampFor(sentTimestampMs: sentTimestampMs)
        let maybeLinkPreview: LinkPreview? = try? LinkPreview
            .filter(LinkPreview.Columns.url == previewProto.url)
            .filter(LinkPreview.Columns.timestamp == LinkPreview.timestampFor(
                sentTimestampMs: Double(proto.timestamp)
            ))
            .fetchOne(db)
        
        if let linkPreview: LinkPreview = maybeLinkPreview {
            self = linkPreview
            return
        }
        
        self.url = previewProto.url
        self.timestamp = timestamp
        self.variant = .standard
        self.title = LinkPreview.normalizeTitle(title: previewProto.title)
        
        if let imageProto = previewProto.image {
            let attachment: Attachment = Attachment(proto: imageProto)
            try attachment.insert(db)
            
            self.attachmentId = attachment.id
        }
        else {
            self.attachmentId = nil
        }
        
        // Make sure the quote is valid before completing
        guard self.title != nil || self.attachmentId != nil else { throw LinkPreviewError.invalidInput }
    }
}

// MARK: - Convenience

public extension LinkPreview {
    struct URLMatchResult {
        let urlString: String
        let matchRange: NSRange
    }
    
    static func timestampFor(sentTimestampMs: Double) -> TimeInterval {
        // We want to round the timestamp down to the nearest 100,000 seconds (~28 hours - simpler
        // than 86,400) to optimise LinkPreview storage without having too stale data
        return (floor(sentTimestampMs / 1000 / LinkPreview.timstampResolution) * LinkPreview.timstampResolution)
    }
    
    static func saveAttachmentIfPossible(_ db: Database, imageData: Data?, mimeType: String) throws -> String? {
        guard let imageData: Data = imageData, !imageData.isEmpty else { return nil }
        guard let fileExtension: String = MIMETypeUtil.fileExtension(forMIMEType: mimeType) else { return nil }
        
        let filePath = OWSFileSystem.temporaryFilePath(withFileExtension: fileExtension)
        try imageData.write(to: NSURL.fileURL(withPath: filePath), options: .atomicWrite)
                
        guard let dataSource = DataSourcePath.dataSource(withFilePath: filePath, shouldDeleteOnDeallocation: true) else {
            return nil
        }
        
        return try Attachment(contentType: mimeType, dataSource: dataSource)?
            .inserted(db)
            .id
    }
    
    static func isValidLinkUrl(_ urlString: String) -> Bool {
        return URL(string: urlString) != nil
    }
    
    static func allPreviewUrls(forMessageBodyText body: String) -> [String] {
        return allPreviewUrlMatches(forMessageBodyText: body).map { $0.urlString }
    }
    
    // MARK: - Private Methods
    
    private static func allPreviewUrlMatches(forMessageBodyText body: String) -> [URLMatchResult] {
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        }
        catch {
            return []
        }

        var urlMatches: [URLMatchResult] = []
        let matches = detector.matches(in: body, options: [], range: NSRange(location: 0, length: body.count))
        for match in matches {
            guard let matchURL = match.url else { continue }
            
            // If the URL entered didn't have a scheme it will default to 'http', we want to catch this and
            // set the scheme to 'https' instead as we don't load previews for 'http' so this will result
            // in more previews actually getting loaded without forcing the user to enter 'https://' before
            // every URL they enter
            let urlString: String = (matchURL.absoluteString == "http://\(body)" ?
                "https://\(body)" :
                matchURL.absoluteString
            )
            
            if isValidLinkUrl(urlString) {
                let matchResult = URLMatchResult(urlString: urlString, matchRange: match.range)
                urlMatches.append(matchResult)
            }
        }
        
        return urlMatches
    }
    
    fileprivate static func normalizeTitle(title: String?) -> String? {
        guard var result: String = title, !result.isEmpty else { return nil }
        
        // Truncate title after 2 lines of text.
        let maxLineCount = 2
        var components = result.components(separatedBy: .newlines)
        
        if components.count > maxLineCount {
            components = Array(components[0..<maxLineCount])
            result =  components.joined(separator: "\n")
        }
        
        let maxCharacterCount = 2048
        if result.count > maxCharacterCount {
            let endIndex = result.index(result.startIndex, offsetBy: maxCharacterCount)
            result = String(result[..<endIndex])
        }
        
        return result.filterStringForDisplay()
    }
}
