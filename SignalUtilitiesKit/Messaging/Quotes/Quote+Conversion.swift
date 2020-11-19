
extension VisibleMessage.Quote {
    
    @objc(from:)
    public static func from(_ quote: OWSQuotedReplyModel?) -> VisibleMessage.Quote? {
        guard let quote = quote else { return nil }
        let result = VisibleMessage.Quote()
        result.timestamp = quote.timestamp
        result.publicKey = quote.authorId
        result.text = quote.body
        return result
    }
}

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
