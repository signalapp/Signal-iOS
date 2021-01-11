import SessionUtilitiesKit

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
            linkPreview: OWSLinkPreview.from(visibleMessage.linkPreview)
        )
    }
}

@objc public extension VisibleMessage {
    
    @objc(from:)
    static func from(_ tsMessage: TSOutgoingMessage) -> VisibleMessage {
        let result = VisibleMessage()
        result.threadID = tsMessage.uniqueThreadId
        result.sentTimestamp = tsMessage.timestamp
        result.recipient = tsMessage.recipientIds().first
        if let thread = tsMessage.thread as? TSGroupThread, thread.isClosedGroup {
            let groupID = thread.groupModel.groupId
            result.groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
        }
        result.text = tsMessage.body
        result.attachmentIDs = tsMessage.attachmentIds.compactMap { $0 as? String }
        result.quote = VisibleMessage.Quote.from(tsMessage.quotedMessage)
        result.linkPreview = VisibleMessage.LinkPreview.from(tsMessage.linkPreview)
        return result
    }
}
