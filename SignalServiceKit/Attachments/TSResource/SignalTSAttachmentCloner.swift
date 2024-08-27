//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SignalTSAttachmentCloner {

    public class func cloneAsSignalAttachment(
        attachment: TSAttachmentStream
    ) throws -> SignalAttachment {
        guard let sourceUrl = attachment.originalMediaURL else {
            throw OWSAssertionError("Missing originalMediaURL.")
        }
        guard let dataUTI = MimeTypeUtil.utiTypeForMimeType(attachment.contentType) else {
            throw OWSAssertionError("Missing dataUTI.")
        }

        let newUrl = OWSFileSystem.temporaryFileUrl(fileExtension: sourceUrl.pathExtension)
        try FileManager.default.copyItem(at: sourceUrl, to: newUrl)

        let clonedDataSource = try DataSourcePath(
            fileUrl: newUrl,
            shouldDeleteOnDeallocation: true
        )
        clonedDataSource.sourceFilename = attachment.sourceFilename

        var signalAttachment: SignalAttachment
        if attachment.attachmentType == .voiceMessage {
            signalAttachment = SignalAttachment.voiceMessageAttachment(dataSource: clonedDataSource, dataUTI: dataUTI)
        } else {
            signalAttachment = SignalAttachment.attachment(dataSource: clonedDataSource, dataUTI: dataUTI)
        }
        signalAttachment.captionText = attachment.caption
        signalAttachment.isBorderless = attachment.attachmentType == .borderless
        signalAttachment.isLoopingVideo = attachment.isLoopingVideo(attachment.attachmentType)
        return signalAttachment
    }
}
