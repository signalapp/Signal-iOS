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
        sourceFilename: String?
    ) throws -> PendingAttachment {
        throw OWSAssertionError("Unimplemented")
    }

    open func validateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        digestSHA256Ciphertext: Data,
        mimeType: String,
        sourceFilename: String?
    ) throws -> PendingAttachment {
        throw OWSAssertionError("Unimplemented")
    }

    open func prepareOversizeTextIfNeeded(
        from messageBody: MessageBody
    ) throws -> ValidatedMessageBody? {
        return .inline(messageBody)
    }
}

#endif
