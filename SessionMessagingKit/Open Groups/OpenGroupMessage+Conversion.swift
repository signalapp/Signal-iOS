
internal extension OpenGroupMessage {

    static func from(_ message: VisibleMessage, for server: String) -> OpenGroupMessage? {
        guard message.isValid else { preconditionFailure() } // Should be valid at this point
        let storage = Configuration.shared.storage
        let displayName = storage.getUserDisplayName() ?? "Anonymous"
        guard let userPublicKey = storage.getUserPublicKey() else { return nil }
        let quote: OpenGroupMessage.Quote? = {
            if let quote = message.quote {
                guard quote.isValid else { return nil }
                return OpenGroupMessage.Quote(quotedMessageTimestamp: quote.timestamp!, quoteePublicKey: quote.publicKey!, quotedMessageBody: quote.text!, quotedMessageServerID: nil) // TODO: Server ID
            } else {
                return nil
            }
        }()
        let body = message.text!
        let result = OpenGroupMessage(serverID: nil, senderPublicKey: userPublicKey, displayName: displayName, profilePicture: nil, body: body,
            type: OpenGroupAPI.openGroupMessageType, timestamp: message.sentTimestamp!, quote: quote, attachments: [], signature: nil, serverTimestamp: 0)
        if let linkPreview: OpenGroupMessage.Attachment = {
            if let linkPreview = message.linkPreview {
                guard linkPreview.isValid else { return nil }
                // TODO: Implement
                return OpenGroupMessage.Attachment(kind: .linkPreview, server: server, serverID: 0, contentType: "", size: 0, fileName: "",
                    flags: 0, width: 0, height: 0, caption: "", url: "", linkPreviewURL: "", linkPreviewTitle: "")
            } else {
                return nil
            }
        }() {
            result.attachments.append(linkPreview)
        }
        // TODO: Attachments
        return result
    }
}
