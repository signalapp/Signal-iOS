
extension TSQuotedMessage {

    /// To be used for outgoing messages only.
    public static func from(_ quote: VisibleMessage.Quote?) -> TSQuotedMessage? {
        guard let quote = quote else { return nil }
        var attachments: [TSAttachment] = []
        if let attachmentID = quote.attachmentID, let attachment = TSAttachment.fetch(uniqueId: attachmentID) {
            attachments.append(attachment)
        }
        return TSQuotedMessage(
            timestamp: quote.timestamp!,
            authorId: quote.publicKey!,
            body: quote.text,
            quotedAttachmentsForSending: attachments
        )
    }
}

extension VisibleMessage.Quote {
    
    public static func from(_ quote: TSQuotedMessage?) -> VisibleMessage.Quote? {
        guard let quote = quote else { return nil }
        
        return VisibleMessage.Quote(
            timestamp: quote.timestamp,
            publicKey: quote.authorId,
            text: quote.body,
            attachmentId: quote.quotedAttachments.first?.attachmentId
        )
    }
}
