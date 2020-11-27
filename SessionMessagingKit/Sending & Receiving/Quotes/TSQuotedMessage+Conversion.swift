
extension TSQuotedMessage {

    @objc(from:)
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
