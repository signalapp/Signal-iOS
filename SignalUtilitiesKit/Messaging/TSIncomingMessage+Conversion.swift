
public extension TSIncomingMessage {

    static func from(_ visibleMessage: VisibleMessage, associatedWith thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> TSIncomingMessage {
        let sender = visibleMessage.sender!
        let result = TSIncomingMessage(
            timestamp: visibleMessage.sentTimestamp!,
            in: thread,
            authorId: sender,
            sourceDeviceId: 1,
            messageBody: visibleMessage.text!,
            attachmentIds: [],
            expiresInSeconds: 0,
            quotedMessage: nil,
            linkPreview: nil,
            serverTimestamp: nil,
            wasReceivedByUD: true
        )
        result.openGroupServerMessageID = visibleMessage.openGroupServerMessageID ?? 0
        return result
    }
}
