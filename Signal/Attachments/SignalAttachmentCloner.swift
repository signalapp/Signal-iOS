//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum SignalAttachmentCloner {
    static func cloneAsSignalAttachment(attachment: ReferencedAttachmentStream) throws -> PreviewableAttachment {
        guard let dataUTI = MimeTypeUtil.utiTypeForMimeType(attachment.attachmentStream.mimeType) else {
            throw OWSAssertionError("Missing dataUTI.")
        }

        // Just use a random file name on the decrypted copy; its internal use only.
        let decryptedCopyUrl = try attachment.attachmentStream.makeDecryptedCopy(
            filename: attachment.reference.sourceFilename
        )

        let decryptedDataSource = DataSourcePath(fileUrl: decryptedCopyUrl, ownership: .owned)
        decryptedDataSource.sourceFilename = attachment.reference.sourceFilename

        let signalAttachment: SignalAttachment
        switch attachment.reference.renderingFlag {
        case .default:
            signalAttachment = try SignalAttachment.attachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
        case .voiceMessage:
            signalAttachment = try SignalAttachment.voiceMessageAttachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
        case .borderless:
            signalAttachment = try SignalAttachment.imageAttachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
            signalAttachment.isBorderless = true
        case .shouldLoop:
            signalAttachment = try SignalAttachment.attachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
            signalAttachment.isLoopingVideo = true
        }
        return PreviewableAttachment(rawValue: signalAttachment)
    }
}
