
public extension TSIncomingMessage {

    static func from(_ visibleMessage: VisibleMessage, using transaction: YapDatabaseReadWriteTransaction) -> TSIncomingMessage {
        let sender = visibleMessage.sender!
        let thread = TSContactThread.getOrCreateThread(withContactId: sender, transaction: transaction)
        return TSIncomingMessage(
            timestamp: visibleMessage.receivedTimestamp!,
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
    }
}
