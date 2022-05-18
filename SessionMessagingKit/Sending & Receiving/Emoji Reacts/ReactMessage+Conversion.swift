
extension ReactMessage {

    /// To be used for outgoing messages only.
    public static func from(_ reaction: VisibleMessage.Reaction?) -> ReactMessage? {
        guard let reaction = reaction else { return nil }
        return ReactMessage(
            timestamp: reaction.timestamp!,
            authorId: reaction.publicKey!,
            emoji: reaction.emoji)
    }
}

extension VisibleMessage.Reaction {
    
    public static func from(_ reaction: ReactMessage?) -> VisibleMessage.Reaction? {
        guard let reaction = reaction else { return nil }
        let result = VisibleMessage.Reaction()
        result.timestamp = reaction.timestamp
        result.publicKey = reaction.authorId
        result.emoji = reaction.emoji
        return result
    }
}
