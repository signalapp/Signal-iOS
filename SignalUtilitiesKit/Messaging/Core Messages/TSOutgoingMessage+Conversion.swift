
@objc public extension TSOutgoingMessage {
    
    @objc(from:associatedWith:)
    static func from(_ visibleMessage: VisibleMessage, associatedWith thread: TSThread) -> TSOutgoingMessage {
        var expiration: UInt32 = 0
        if let disappearingMessagesConfiguration = OWSDisappearingMessagesConfiguration.fetch(uniqueId: thread.uniqueId!) {
            expiration = disappearingMessagesConfiguration.isEnabled ? disappearingMessagesConfiguration.durationSeconds : 0
        }
        return TSOutgoingMessage(
            outgoingMessageWithTimestamp: visibleMessage.sentTimestamp!,
            in: thread,
            messageBody: visibleMessage.text,
            attachmentIds: NSMutableArray(),
            expiresInSeconds: expiration,
            expireStartedAt: 0,
            isVoiceMessage: false,
            groupMetaMessage: .unspecified,
            quotedMessage: TSQuotedMessage.from(visibleMessage.quote),
            linkPreview: nil
        )
    }
}
