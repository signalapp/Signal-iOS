
internal extension OpenGroupMessage {

    static func from(_ message: VisibleMessage, for server: String, using transaction: YapDatabaseReadWriteTransaction) -> OpenGroupMessage? {
        let storage = SNMessagingKitConfiguration.shared.storage
        guard let userPublicKey = storage.getUserPublicKey() else { return nil }
        var attachmentIDs = message.attachmentIDs
        // Validation
        guard message.isValid else { return nil } // Should be valid at this point
        // Quote
        let quote: OpenGroupMessage.Quote? = {
            if let quote = message.quote {
                guard quote.isValid else { return nil }
                let quotedMessageBody = quote.text ?? String(quote.timestamp!) // The back-end doesn't accept messages without a body so we use this as a workaround
                if let quotedAttachmentID = quote.attachmentID, let index = attachmentIDs.firstIndex(of: quotedAttachmentID) {
                    attachmentIDs.remove(at: index)
                }
                // FIXME: For some reason the server always returns a 500 if quotedMessageServerID is set...
                return OpenGroupMessage.Quote(quotedMessageTimestamp: quote.timestamp!, quoteePublicKey: quote.publicKey!, quotedMessageBody: quotedMessageBody, quotedMessageServerID: nil)
            } else {
                return nil
            }
        }()
        // Message
        let displayName = storage.getUserDisplayName() ?? "Anonymous"
        let body = message.text ?? String(message.sentTimestamp!) // The back-end doesn't accept messages without a body so we use this as a workaround
        let result = OpenGroupMessage(serverID: nil, senderPublicKey: userPublicKey, displayName: displayName, profilePicture: nil, body: body,
            type: OpenGroupAPI.openGroupMessageType, timestamp: message.sentTimestamp!, quote: quote, attachments: [], signature: nil, serverTimestamp: 0)
        // Link preview
        if let linkPreview = message.linkPreview {
            guard linkPreview.isValid, let attachmentID = linkPreview.attachmentID,
                let attachment = TSAttachmentStream.fetch(uniqueId: attachmentID, transaction: transaction) else { return nil }
            if let index = attachmentIDs.firstIndex(of: attachmentID) {
                attachmentIDs.remove(at: index)
            }
            let fileName = attachment.sourceFilename ?? UUID().uuidString
            let width = attachment.shouldHaveImageSize() ? attachment.imageSize().width : 0
            let height = attachment.shouldHaveImageSize() ? attachment.imageSize().height : 0
            let openGroupLinkPreview = OpenGroupMessage.Attachment(
                kind: .linkPreview,
                server: server,
                serverID: attachment.serverId,
                contentType: attachment.contentType,
                size: UInt(attachment.byteCount),
                fileName: fileName,
                flags: 0,
                width: UInt(width),
                height: UInt(height),
                caption: attachment.caption,
                url: attachment.downloadURL,
                linkPreviewURL: linkPreview.url,
                linkPreviewTitle: linkPreview.title
            )
            result.attachments.append(openGroupLinkPreview)
        }
        // Attachments
        let attachments: [OpenGroupMessage.Attachment] = attachmentIDs.compactMap { attachmentID in
            guard let attachment = TSAttachmentStream.fetch(uniqueId: attachmentID, transaction: transaction) else { return nil } // Should never occur
            let fileName = attachment.sourceFilename ?? UUID().uuidString
            let width = attachment.shouldHaveImageSize() ? attachment.imageSize().width : 0
            let height = attachment.shouldHaveImageSize() ? attachment.imageSize().height : 0
            return OpenGroupMessage.Attachment(
                kind: .attachment,
                server: server,
                serverID: attachment.serverId,
                contentType: attachment.contentType,
                size: UInt(attachment.byteCount),
                fileName: fileName,
                flags: 0,
                width: UInt(width),
                height: UInt(height),
                caption: attachment.caption,
                url: attachment.downloadURL,
                linkPreviewURL: nil,
                linkPreviewTitle: nil
            )
        }
        result.attachments += attachments
        // Return
        return result
    }
}
