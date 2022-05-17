// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public struct QuotedReplyModel {
    public let threadId: String
    public let authorId: String
    public let timestampMs: Int64
    public let body: String?
    public let attachment: Attachment?
    public let contentType: String?
    public let sourceFileName: String?
    public let thumbnailDownloadFailed: Bool
    
    // MARK: - Initialization
    
    init(
        threadId: String,
        authorId: String,
        timestampMs: Int64,
        body: String?,
        attachment: Attachment?,
        contentType: String?,
        sourceFileName: String?,
        thumbnailDownloadFailed: Bool
    ) {
        self.attachment = attachment
        self.threadId = threadId
        self.authorId = authorId
        self.timestampMs = timestampMs
        self.body = body
        self.contentType = contentType
        self.sourceFileName = sourceFileName
        self.thumbnailDownloadFailed = thumbnailDownloadFailed
    }
    
    public static func quotedReplyForSending(
        threadId: String,
        authorId: String,
        variant: Interaction.Variant,
        body: String?,
        timestampMs: Int64,
        attachments: [Attachment]?,
        linkPreview: LinkPreview?
    ) -> QuotedReplyModel? {
        guard variant == .standardOutgoing || variant == .standardIncoming else { return nil }
        guard (body != nil && body?.isEmpty == false) || attachments?.isEmpty == false else { return nil }
        
        return QuotedReplyModel(
            threadId: threadId,
            authorId: authorId,
            timestampMs: timestampMs,
            body: body,
            attachment: attachments?.first,
            contentType: attachments?.first?.contentType,
            sourceFileName: attachments?.first?.sourceFilename,
            thumbnailDownloadFailed: false
        )
    }
}

// MARK: - Convenience

public extension QuotedReplyModel {
    func generateAttachmentThumbnailIfNeeded(_ db: Database) throws -> String? {
        guard let sourceAttachment: Attachment = self.attachment else { return nil }
        
        return try sourceAttachment
            .cloneAsThumbnail()?
            .inserted(db)
            .id
    }
}
