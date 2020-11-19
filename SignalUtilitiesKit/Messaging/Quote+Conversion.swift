
extension VisibleMessage.Quote {
    
    @objc(from:)
    public static func from(_ model: OWSQuotedReplyModel?) -> VisibleMessage.Quote? {
        guard let model = model else { return nil }
        let result = VisibleMessage.Quote()
        result.timestamp = model.timestamp
        result.publicKey = model.authorId
        result.text = model.body
        return result
    }
}
