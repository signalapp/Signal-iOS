
public extension TSIncomingMessage {

    static func from(_ visibleMessage: VisibleMessage, associatedWith thread: TSThread) -> TSIncomingMessage {
        let sender = visibleMessage.sender!
        var expiration: UInt32 = 0
        Storage.read { transaction in
            expiration = thread.disappearingMessagesDuration(with: transaction)
        }
        let result = TSIncomingMessage(
            timestamp: visibleMessage.sentTimestamp!,
            in: thread,
            authorId: sender,
            sourceDeviceId: 1,
            messageBody: visibleMessage.text,
            attachmentIds: visibleMessage.attachmentIDs,
            expiresInSeconds: expiration,
            quotedMessage: TSQuotedMessage.from(visibleMessage.quote),
            linkPreview: OWSLinkPreview.from(visibleMessage.linkPreview),
            serverTimestamp: nil,
            wasReceivedByUD: true
        )
        result.openGroupServerMessageID = visibleMessage.openGroupServerMessageID ?? 0
        result.isOpenGroupMessage = result.openGroupServerMessageID != 0
        return result
    }
}
