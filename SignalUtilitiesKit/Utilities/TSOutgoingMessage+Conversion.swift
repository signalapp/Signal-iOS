
@objc public extension TSOutgoingMessage {
    
    @objc(from:associatedWith:)
    static func from(_ visibleMessage: VisibleMessage, associatedWith thread: TSThread) -> TSOutgoingMessage {
        var expiration: UInt32 = 0
        if let disappearingMessagesConfiguration = OWSDisappearingMessagesConfiguration.fetch(uniqueId: thread.uniqueId!) {
            expiration = disappearingMessagesConfiguration.isEnabled ? disappearingMessagesConfiguration.durationSeconds : 0
        }
        return TSOutgoingMessage(
            in: thread,
            messageBody: visibleMessage.text,
            attachmentId: nil,
            expiresInSeconds: expiration,
            quotedMessage: nil,
            linkPreview: nil
        )
    }
}
