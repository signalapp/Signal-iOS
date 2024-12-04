//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Just a simple structure holding an attachment and a reference to it,
/// since that's something we need to do very often.
public class ReferencedAttachment {
    public let reference: AttachmentReference
    public let attachment: Attachment

    public init(reference: AttachmentReference, attachment: Attachment) {
        self.reference = reference
        self.attachment = attachment
    }

    public var asReferencedStream: ReferencedAttachmentStream? {
        guard let attachmentStream = attachment.asStream() else {
            return nil
        }
        return .init(reference: reference, attachmentStream: attachmentStream)
    }

    public var asReferencedTransitPointer: ReferencedAttachmentTransitPointer? {
        guard let attachmentPointer = AttachmentTransitPointer(attachment: attachment) else {
            return nil
        }
        return .init(reference: reference, attachmentPointer: attachmentPointer)
    }

    public var asReferencedBackupThumbnail: ReferencedAttachmentBackupThumbnail? {
        guard let attachmentBackupThumbnail = AttachmentBackupThumbnail(attachment: attachment) else {
            return nil
        }
        return .init(reference: reference, attachmentBackupThumbnail: attachmentBackupThumbnail)
    }
}

public class ReferencedAttachmentStream: ReferencedAttachment {
    public let attachmentStream: AttachmentStream

    public init(reference: AttachmentReference, attachmentStream: AttachmentStream) {
        self.attachmentStream = attachmentStream
        super.init(reference: reference, attachment: attachmentStream.attachment)
    }
}

public class ReferencedAttachmentTransitPointer: ReferencedAttachment {
    public let attachmentPointer: AttachmentTransitPointer

    public init(reference: AttachmentReference, attachmentPointer: AttachmentTransitPointer) {
        self.attachmentPointer = attachmentPointer
        super.init(reference: reference, attachment: attachmentPointer.attachment)
    }
}

public class ReferencedAttachmentBackupThumbnail: ReferencedAttachment {
    public let attachmentBackupThumbnail: AttachmentBackupThumbnail

    public init(reference: AttachmentReference, attachmentBackupThumbnail: AttachmentBackupThumbnail) {
        self.attachmentBackupThumbnail = attachmentBackupThumbnail
        super.init(reference: reference, attachment: attachmentBackupThumbnail.attachment)
    }
}

extension ReferencedAttachment {

    public func previewText() -> String {
        let mimeType = attachment.mimeType

        let attachmentString: String
        if MimeTypeUtil.isSupportedMaybeAnimatedMimeType(mimeType) || reference.renderingFlag == .shouldLoop {
            let isGIF = mimeType.caseInsensitiveCompare(MimeType.imageGif.rawValue) == .orderedSame
            let isLoopingVideo = reference.renderingFlag == .shouldLoop
                && MimeTypeUtil.isSupportedVideoMimeType(mimeType)

            if (isGIF || isLoopingVideo) {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_GIF",
                    comment: "Short text label for a gif attachment, used for thread preview and on the lock screen"
                )
            } else {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_PHOTO",
                    comment: "Short text label for a photo attachment, used for thread preview and on the lock screen"
                )
            }
        } else if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            attachmentString = OWSLocalizedString(
                "ATTACHMENT_TYPE_PHOTO",
                comment: "Short text label for a photo attachment, used for thread preview and on the lock screen"
            )
        } else if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            attachmentString = OWSLocalizedString(
                "ATTACHMENT_TYPE_VIDEO",
                comment: "Short text label for a video attachment, used for thread preview and on the lock screen"
            )
        } else if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            if reference.renderingFlag == .voiceMessage {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_VOICE_MESSAGE",
                    comment: "Short text label for a voice message attachment, used for thread preview and on the lock screen"
                )
            } else {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_AUDIO",
                    comment: "Short text label for a audio attachment, used for thread preview and on the lock screen"
                )
            }
        } else {
            attachmentString = OWSLocalizedString(
                "ATTACHMENT_TYPE_FILE",
                comment: "Short text label for a file attachment, used for thread preview and on the lock screen"
            )
        }

        let emoji = self.previewEmoji()
        return String(format: "%@ %@", emoji, attachmentString)
    }

    public func previewEmoji() -> String {
        let mimeType = attachment.mimeType
        if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            if reference.renderingFlag == .voiceMessage {
                return "🎤"
            }
        }

        if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) || reference.renderingFlag == .shouldLoop {
            return "🎡"
        } else if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            return "📷"
        } else if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return "🎥"
        } else if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            return "🎧"
        } else {
            return "📎"
        }
    }
}
