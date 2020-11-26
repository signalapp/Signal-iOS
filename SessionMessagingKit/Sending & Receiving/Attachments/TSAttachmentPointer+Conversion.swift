
extension TSAttachmentPointer {

    public static func from(_ attachment: VisibleMessage.Attachment) -> TSAttachmentPointer {
        let kind: TSAttachmentType
        switch attachment.kind! {
        case .generic: kind = .default
        case .voiceMessage: kind = .voiceMessage
        }
        let result = TSAttachmentPointer(
            serverId: 0,
            key: attachment.key,
            digest: attachment.digest,
            byteCount: UInt32(attachment.sizeInBytes!),
            contentType: attachment.contentType!,
            sourceFilename: attachment.fileName,
            caption: attachment.caption,
            albumMessageId: nil,
            attachmentType: kind,
            mediaSize: attachment.size!)
        result.downloadURL = attachment.url!
        return result
    }
}
