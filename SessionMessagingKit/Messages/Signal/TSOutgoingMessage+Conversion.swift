import SessionUtilitiesKit

@objc public extension TSOutgoingMessage {
    
    @objc(from:associatedWith:)
    static func from(_ visibleMessage: VisibleMessage, associatedWith thread: TSThread) -> TSOutgoingMessage {
        return from(visibleMessage, associatedWith: thread, using: nil)
    }
    
    static func from(_ visibleMessage: VisibleMessage, associatedWith thread: TSThread, using transaction: YapDatabaseReadWriteTransaction? = nil) -> TSOutgoingMessage {
        var expiration: UInt32 = 0
        let disappearingMessagesConfigurationOrNil: OWSDisappearingMessagesConfiguration?
        if let transaction = transaction {
            disappearingMessagesConfigurationOrNil = OWSDisappearingMessagesConfiguration.fetch(uniqueId: thread.uniqueId!, transaction: transaction)
        } else {
            disappearingMessagesConfigurationOrNil = OWSDisappearingMessagesConfiguration.fetch(uniqueId: thread.uniqueId!)
        }
        if let disappearingMessagesConfiguration = disappearingMessagesConfigurationOrNil {
            expiration = disappearingMessagesConfiguration.isEnabled ? disappearingMessagesConfiguration.durationSeconds : 0
        }
        return TSOutgoingMessage(
            outgoingMessageWithTimestamp: visibleMessage.sentTimestamp!,
            in: thread,
            messageBody: visibleMessage.text,
            attachmentIds: NSMutableArray(array: visibleMessage.attachmentIDs),
            expiresInSeconds: expiration,
            expireStartedAt: 0,
            isVoiceMessage: false,
            groupMetaMessage: .unspecified,
            quotedMessage: TSQuotedMessage.from(visibleMessage.quote),
            linkPreview: OWSLinkPreview.from(visibleMessage.linkPreview),
            openGroupInvitationName: visibleMessage.openGroupInvitation?.name,
            openGroupInvitationURL: visibleMessage.openGroupInvitation?.url,
            serverHash: visibleMessage.serverHash
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
