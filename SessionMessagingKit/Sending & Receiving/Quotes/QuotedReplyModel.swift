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
        guard variant == .standardOutgoing || variant == .standardIncoming else {
            return nil
        }
        
        var quotedText: String? = body
        var quotedAttachment: Attachment? = attachments?.first
        
        // If the attachment is "oversize text", try the quote as a reply to text, not as
        // a reply to an attachment
        if
            quotedText?.isEmpty == true,
            let attachment: Attachment = quotedAttachment,
            attachment.contentType == OWSMimeTypeOversizeTextMessage,
            (
                (variant == .standardIncoming && attachment.state == .downloaded) ||
                attachment.state != .failed
            ),
            let originalFilePath: String = attachment.originalFilePath
        {
            quotedText = ""
            
            if
                let textData: Data = try? Data(contentsOf: URL(fileURLWithPath: originalFilePath)),
                let oversizeText: String = String(data: textData, encoding: .utf8)
            {
                // The attachment is going to be sent as text instead
                quotedAttachment = nil
                
                // We don't need to include the entire text body of the message, just
                // enough to render a snippet.  kOversizeTextMessageSizeThreshold is our
                // limit on how long text should be in protos since they'll be stored in
                // the database. We apply this constant here for the same reasons.
                //
                // First, truncate to the rough max characters
                var truncatedText: String = oversizeText.substring(to: Int(Interaction.oversizeTextMessageSizeThreshold - 1))
                
                // But kOversizeTextMessageSizeThreshold is in _bytes_, not characters,
                // so we need to continue to trim the string until it fits.
                while truncatedText.lengthOfBytes(using: .utf8) >= Interaction.oversizeTextMessageSizeThreshold {
                    // A very coarse binary search by halving is acceptable, since
                    // kOversizeTextMessageSizeThreshold is much longer than our target
                    // length of "three short lines of text on any device we might
                    // display this on.
                    //
                    // The search will always converge since in the worst case (namely
                    // a single character which in utf-8 is >= 1024 bytes) the loop will
                    // exit when the string is empty.
                    truncatedText = truncatedText.substring(to: truncatedText.count / 2)
                }
                
                if truncatedText.lengthOfBytes(using: .utf8) < Interaction.oversizeTextMessageSizeThreshold {
                    quotedText = truncatedText
                }
            }
        }
        
        return QuotedReplyModel(
            threadId: threadId,
            authorId: authorId,
            timestampMs: timestampMs,
            body: (quotedText == nil && quotedAttachment == nil ? "" : quotedText),
            attachment: quotedAttachment,
            contentType: quotedAttachment?.contentType,
            sourceFileName: quotedAttachment?.sourceFilename,
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
