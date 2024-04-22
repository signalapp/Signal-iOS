//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SignalTSAttachmentCloner {

    class func cloneAsSignalAttachmentRequest(
        attachment: TSAttachmentStream,
        sourceMessage: TSMessage,
        transaction: SDSAnyReadTransaction
    ) throws -> CloneAsSignalAttachmentRequest {
        // TODO: these should be done in one lookup.
        let attachmentType = attachment.attachmentType(forContainingMessage: sourceMessage, transaction: transaction)
        let caption = attachment.caption(forContainingMessage: sourceMessage, transaction: transaction)
        return try cloneAsSignalAttachmentRequest(
            attachment: attachment,
            isVoiceMessage: attachmentType == .voiceMessage,
            isBorderless: attachmentType == .borderless,
            isLoopingVideo: attachment.isLoopingVideo(attachmentType),
            caption: caption
        )
    }

    class func cloneAsSignalAttachmentRequest(
        attachment: TSAttachmentStream,
        sourceStoryMessage: StoryMessage,
        transaction: SDSAnyReadTransaction
    ) throws -> CloneAsSignalAttachmentRequest {
        // TODO: these should be done in one lookup.
        let isLoopingVideo = attachment.isLoopingVideo(inContainingStoryMessage: sourceStoryMessage, transaction: transaction)
        let caption = attachment.caption(forContainingStoryMessage: sourceStoryMessage, transaction: transaction)
        return try cloneAsSignalAttachmentRequest(
            attachment: attachment,
            isVoiceMessage: false,
            isBorderless: false,
            isLoopingVideo: isLoopingVideo,
            caption: caption
        )
    }

    private class func cloneAsSignalAttachmentRequest(
        attachment: TSAttachmentStream,
        isVoiceMessage: Bool,
        isBorderless: Bool,
        isLoopingVideo: Bool,
        caption: String?
    ) throws -> CloneAsSignalAttachmentRequest {
        guard let sourceUrl = attachment.originalMediaURL else {
            throw OWSAssertionError("Missing originalMediaURL.")
        }
        guard let dataUTI = MimeTypeUtil.utiTypeForMimeType(attachment.contentType) else {
            throw OWSAssertionError("Missing dataUTI.")
        }
        return CloneAsSignalAttachmentRequest(
            uniqueId: attachment.uniqueId,
            sourceUrl: sourceUrl,
            dataUTI: dataUTI,
            sourceFilename: attachment.sourceFilename,
            isVoiceMessage: isVoiceMessage,
            caption: caption,
            isBorderless: isBorderless,
            isLoopingVideo: isLoopingVideo
        )
    }
}
