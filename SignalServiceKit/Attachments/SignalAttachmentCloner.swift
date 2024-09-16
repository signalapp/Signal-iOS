//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SignalAttachmentCloner {

    func cloneAsSignalAttachment(
        attachment: ReferencedAttachmentStream
    ) throws -> SignalAttachment
}

public class SignalAttachmentClonerImpl: SignalAttachmentCloner {

    public init() {}

    public func cloneAsSignalAttachment(
        attachment: ReferencedAttachmentStream
    ) throws -> SignalAttachment {
        guard let dataUTI = MimeTypeUtil.utiTypeForMimeType(attachment.attachmentStream.mimeType) else {
            throw OWSAssertionError("Missing dataUTI.")
        }

        // Just use a random file name on the decrypted copy; its internal use only.
        let decryptedCopyUrl = try attachment.attachmentStream.makeDecryptedCopy(
            filename: attachment.reference.sourceFilename
        )

        let decryptedDataSource = try DataSourcePath(
            fileUrl: decryptedCopyUrl,
            shouldDeleteOnDeallocation: true
        )
        decryptedDataSource.sourceFilename = attachment.reference.sourceFilename

        var signalAttachment: SignalAttachment
        switch attachment.reference.renderingFlag {
        case .default:
            signalAttachment = SignalAttachment.attachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
        case .voiceMessage:
            signalAttachment = SignalAttachment.voiceMessageAttachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
        case .borderless:
            signalAttachment = SignalAttachment.attachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
            signalAttachment.isBorderless = true
        case .shouldLoop:
            signalAttachment = SignalAttachment.attachment(dataSource: decryptedDataSource, dataUTI: dataUTI)
            signalAttachment.isLoopingVideo = true
        }
        signalAttachment.captionText = attachment.reference.storyMediaCaption?.text
        return signalAttachment
    }
}

#if TESTABLE_BUILD

public class SignalAttachmentClonerMock: SignalAttachmentCloner {

    public func cloneAsSignalAttachment(
        attachment: ReferencedAttachmentStream
    ) throws -> SignalAttachment {
        throw OWSAssertionError("Unimplemented!")
    }
}

#endif
