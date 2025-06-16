//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentContentValidatorMock: AttachmentContentValidator {

    init() {}

    open func validateContents(
        dataSource: DataSource,
        shouldConsume: Bool,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        throw OWSAssertionError("Unimplemented")
    }

    open func validateContents(
        data: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        throw OWSAssertionError("Unimplemented")
    }

    open func validateDownloadedContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32?,
        integrityCheck: AttachmentIntegrityCheck,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        throw OWSAssertionError("Unimplemented")
    }

    open func reValidateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) throws -> RevalidatedAttachment {
        throw OWSAssertionError("Unimplemented")
    }

    open func validateContents(
        ofBackupMediaFileAt fileUrl: URL,
        outerDecryptionData: DecryptionMetadata,
        innerDecryptionData: DecryptionMetadata,
        finalEncryptionKey: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> any PendingAttachment {
        throw OWSAssertionError("Unimplemented")
    }

    open func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedMessageBody? {
        return .inline(messageBody)
    }

    open func prepareQuotedReplyThumbnail(
        fromOriginalAttachment: AttachmentStream,
        originalReference: AttachmentReference
    ) throws -> QuotedReplyAttachmentDataSource {
        throw OWSAssertionError("Unimplemented")
    }

    open func prepareQuotedReplyThumbnail(
        fromOriginalAttachmentStream: AttachmentStream
    ) throws -> PendingAttachment {
        throw OWSAssertionError("Unimplemented")
    }
}

#endif
