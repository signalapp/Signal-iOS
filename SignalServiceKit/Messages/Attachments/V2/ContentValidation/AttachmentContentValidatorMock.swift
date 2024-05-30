//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentContentValidatorMock: AttachmentContentValidator {

    init() {}

    open func validateContents(
        data: Data,
        mimeType: String
    ) throws -> Attachment.ContentType {
        return .file
    }

    open func validateContents(
        fileUrl: URL,
        mimeType: String
    ) throws -> Attachment.ContentType {
        return .file
    }

    open func validateContents(
        encryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) throws -> Attachment.ContentType {
        return .file
    }
}

#endif
