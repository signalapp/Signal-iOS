
extension TSQuotedMessage {

    @objc(from:)
    public static func from(_ quote: VisibleMessage.Quote?) -> TSQuotedMessage? {
        guard let quote = quote else { return nil }
        return TSQuotedMessage(
            timestamp: quote.timestamp!,
            authorId: quote.publicKey!,
            body: quote.text, bodySource: .local,
            receivedQuotedAttachmentInfos: []
        )
    }
}
