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

    public var asReferencedBackupPointer: ReferencedAttachmentBackupPointer? {
        guard let attachmentPointer = AttachmentBackupPointer(attachment: attachment) else {
            return nil
        }
        return .init(reference: reference, attachmentPointer: attachmentPointer)
    }

    public var asReferencedAnyPointer: ReferencedAttachmentPointer? {
        guard let attachmentPointer = AttachmentPointer(attachment: attachment) else {
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

public class ReferencedAttachmentBackupPointer: ReferencedAttachment {
    public let attachmentPointer: AttachmentBackupPointer

    public init(reference: AttachmentReference, attachmentPointer: AttachmentBackupPointer) {
        self.attachmentPointer = attachmentPointer
        super.init(reference: reference, attachment: attachmentPointer.attachment)
    }
}

public class ReferencedAttachmentPointer: ReferencedAttachment {
    public let attachmentPointer: AttachmentPointer

    public init(reference: AttachmentReference, attachmentPointer: AttachmentPointer) {
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

// MARK: -

extension ReferencedAttachment {

    public func previewText(
        includeFileName: Bool = false,
        includeEmoji: Bool = true,
    ) -> String {
        let mimeType = attachment.mimeType

        let attachmentString: String
        if MimeTypeUtil.isSupportedMaybeAnimatedMimeType(mimeType) || reference.renderingFlag == .shouldLoop {
            let isGIF = mimeType.caseInsensitiveCompare(MimeType.imageGif.rawValue) == .orderedSame
            let isLoopingVideo = reference.renderingFlag == .shouldLoop
                && MimeTypeUtil.isSupportedVideoMimeType(mimeType)

            if isGIF || isLoopingVideo {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_GIF",
                    comment: "Short text label for a gif attachment, used for thread preview and on the lock screen",
                )
            } else {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_PHOTO",
                    comment: "Short text label for a photo attachment, used for thread preview and on the lock screen",
                )
            }
        } else if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            attachmentString = OWSLocalizedString(
                "ATTACHMENT_TYPE_PHOTO",
                comment: "Short text label for a photo attachment, used for thread preview and on the lock screen",
            )
        } else if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            attachmentString = OWSLocalizedString(
                "ATTACHMENT_TYPE_VIDEO",
                comment: "Short text label for a video attachment, used for thread preview and on the lock screen",
            )
        } else if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            if reference.renderingFlag == .voiceMessage {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_VOICE_MESSAGE",
                    comment: "Short text label for a voice message attachment, used for thread preview and on the lock screen",
                )
            } else {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_AUDIO",
                    comment: "Short text label for a audio attachment, used for thread preview and on the lock screen",
                )
            }
        } else {
            if includeFileName, let filename = reference.sourceFilename {
                attachmentString = filename.ows_stripped()
            } else {
                attachmentString = OWSLocalizedString(
                    "ATTACHMENT_TYPE_FILE",
                    comment: "Short text label for a file attachment, used for thread preview and on the lock screen",
                )
            }
        }

        if includeEmoji {
            let emoji = self.previewEmoji()
            return emoji + " " + attachmentString
        }
        return attachmentString
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

    // MARK: -

    /// Builds a `SSKProtoAttachmentPointer` representing this reference to an
    /// attachment, suitable for sending with a message.
    func asProtoForSending() -> SSKProtoAttachmentPointer? {
        guard let pointer = AttachmentTransitPointer(attachment: attachment) else {
            return nil
        }

        let digestSHA256Ciphertext: Data
        switch pointer.info.integrityCheck {
        case .digestSHA256Ciphertext(let data):
            digestSHA256Ciphertext = data
        case .sha256ContentHash:
            return nil
        }

        let builder = SSKProtoAttachmentPointer.builder()
        builder.setCdnNumber(pointer.cdnNumber)
        builder.setCdnKey(pointer.cdnKey)
        builder.setContentType(pointer.attachment.mimeType)

        reference.sourceFilename.map(builder.setFileName(_:))

        var flags: SSKProtoAttachmentPointerFlags?
        switch reference.owner {
        case .message(.bodyAttachment(let metadata)):
            if let caption = metadata.caption {
                builder.setCaption(caption)
            }
            if let idInOwner = metadata.idInOwner {
                builder.setClientUuid(idInOwner.data)
            }
            flags = metadata.renderingFlag.toProto()
        case .message(.quotedReply(let metadata)):
            flags = metadata.renderingFlag.toProto()
        case .storyMessage(.media(let metadata)):
            (metadata.caption?.text).map(builder.setCaption(_:))
            flags = metadata.shouldLoop ? .gif : nil
        default:
            break
        }

        if let flags {
            builder.setFlags(UInt32(flags.rawValue))
        } else {
            builder.setFlags(0)
        }

        func setMediaSizePixels(_ pixelSize: CGSize) {
            builder.setWidth(UInt32(pixelSize.width.rounded()))
            builder.setHeight(UInt32(pixelSize.height.rounded()))
        }

        if let stream = pointer.attachment.asStream() {
            // If we have it downloaded and have the validated values, use them.
            builder.setSize(stream.unencryptedByteCount)

            switch stream.contentType {
            case .file, .invalid, .audio:
                break
            case .image(let pixelSize), .animatedImage(let pixelSize), .video(_, let pixelSize, _):
                setMediaSizePixels(_: pixelSize)
            }
        } else {
            // Otherwise fall back to values from the sender.
            reference.sourceUnencryptedByteCount.map(builder.setSize(_:))
            reference.sourceMediaSizePixels.map(setMediaSizePixels(_:))
        }
        builder.setKey(pointer.info.encryptionKey)
        builder.setDigest(digestSHA256Ciphertext)
        builder.setUploadTimestamp(pointer.uploadTimestamp)

        pointer.attachment.blurHash.map(builder.setBlurHash(_:))

        return builder.buildInfallibly()
    }
}
