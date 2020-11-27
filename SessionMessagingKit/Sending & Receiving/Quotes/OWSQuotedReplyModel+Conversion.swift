
extension VisibleMessage.Quote {
    
    @objc(from:)
    public static func from(_ quote: OWSQuotedReplyModel?) -> VisibleMessage.Quote? {
        guard let quote = quote else { return nil }
        let result = VisibleMessage.Quote()
        result.timestamp = quote.timestamp
        result.publicKey = quote.authorId
        result.text = quote.body
        result.attachmentID = quote.attachmentStream?.uniqueId
        return result
    }
}
