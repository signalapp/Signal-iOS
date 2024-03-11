//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentManager {

    /// Builds a ``SSKProtoAttachmentPointer`` for sending with a message,
    /// given both the pointer (an already-uploaded attachment) and the reference to
    /// that pointer from the parent message we want to send.
    public func buildProtoForSending(
        from reference: AttachmentReference,
        pointer: AttachmentTransitPointer
    ) -> SSKProtoAttachmentPointer {
        let builder = SSKProtoAttachmentPointer.builder()

        builder.setCdnNumber(pointer.cdnNumber)
        builder.setCdnKey(pointer.cdnKey)

        builder.setContentType(pointer.attachment.mimeType)

        reference.sourceFilename.map(builder.setFileName(_:))

        var flags: TSAttachmentType?
        switch reference.owner {
        case .message(.bodyAttachment(let metadata)):
            (metadata.caption?.text).map(builder.setCaption(_:))
            flags = metadata.flags
        case .message(.quotedReply(let metadata)):
            flags = metadata.flags
        case .storyMessage(.media(let metadata)):
            (metadata.caption?.text).map(builder.setCaption(_:))
            flags = metadata.isLoopingVideo ? .GIF : nil
        default:
            break
        }

        switch flags {
        case .voiceMessage:
            builder.setFlags(UInt32(SSKProtoAttachmentPointerFlags.voiceMessage.rawValue))
        case .borderless:
            builder.setFlags(UInt32(SSKProtoAttachmentPointerFlags.borderless.rawValue))
        case .GIF:
            builder.setFlags(UInt32(SSKProtoAttachmentPointerFlags.gif.rawValue))

        case .default, nil:
            fallthrough
        @unknown default:
            builder.setFlags(0)
        }

        func setMediaSizePixels(_ pixelSize: CGSize) {
            builder.setWidth(UInt32(pixelSize.width.rounded()))
            builder.setHeight(UInt32(pixelSize.width.rounded()))
        }

        if let stream = pointer.attachment.asStream() {
            // If we have it downloaded and have the validated values, use them.
            builder.setSize(stream.unenecryptedByteCount)

            switch stream.contentType {
            case .file, .audio:
                break
            case .image(let pixelSize), .animatedImage(let pixelSize), .video(_, let pixelSize):
                setMediaSizePixels(_: pixelSize)
            }
        } else {
            // Otherwise fall back to values from the sender.
            reference.sourceUnencryptedByteCount.map(builder.setSize(_:))
            reference.sourceMediaSizePixels.map(setMediaSizePixels(_:))
        }
        builder.setKey(pointer.attachment.encryptionKey)
        pointer.attachment.encryptedFileSha256Digest.map(builder.setDigest(_:))

        pointer.attachment.blurHash.map(builder.setBlurHash(_:))

        return builder.buildInfallibly()
    }
}
