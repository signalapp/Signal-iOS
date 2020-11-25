
public extension TSIncomingMessage {

    static func from(_ visibleMessage: VisibleMessage, associatedWith thread: TSThread) -> TSIncomingMessage {
        let sender = visibleMessage.sender!
        let result = TSIncomingMessage(
            timestamp: visibleMessage.sentTimestamp!,
            in: thread,
            authorId: sender,
            sourceDeviceId: 1,
            messageBody: visibleMessage.text!,
            attachmentIds: [],
            expiresInSeconds: 0,
            quotedMessage: TSQuotedMessage.from(visibleMessage.quote),
            linkPreview: nil,
            serverTimestamp: nil,
            wasReceivedByUD: true
        )
        result.openGroupServerMessageID = visibleMessage.openGroupServerMessageID ?? 0
        result.isOpenGroupMessage = result.openGroupServerMessageID != 0
        return result
    }
}
