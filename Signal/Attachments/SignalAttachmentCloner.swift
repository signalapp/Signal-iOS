//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

enum SignalAttachmentCloner {
    static func cloneAsSignalAttachment(attachment: ReferencedAttachmentStream) throws -> PreviewableAttachment {
        guard let dataUTI = MimeTypeUtil.utiTypeForMimeType(attachment.attachmentStream.mimeType) else {
            throw OWSAssertionError("Missing dataUTI.")
        }

        // Just use a random file name on the decrypted copy; its internal use only.
        let decryptedCopyUrl = try attachment.attachmentStream.makeDecryptedCopy(
            filename: attachment.reference.sourceFilename,
        )

        let decryptedDataSource = DataSourcePath(fileUrl: decryptedCopyUrl, ownership: .owned)
        decryptedDataSource.sourceFilename = attachment.reference.sourceFilename

        let result: PreviewableAttachment
        switch attachment.reference.renderingFlag {
        case .default:
            result = try PreviewableAttachment.buildAttachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
        case .voiceMessage:
            result = try PreviewableAttachment.voiceMessageAttachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
        case .borderless:
            result = try PreviewableAttachment.imageAttachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
            result.rawValue.isBorderless = true
        case .shouldLoop:
            result = try PreviewableAttachment.buildAttachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
            result.rawValue.isLoopingVideo = true
        }
        return result
    }
}
