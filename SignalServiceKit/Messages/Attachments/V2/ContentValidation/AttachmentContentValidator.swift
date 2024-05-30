//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentContentValidator {

    /// Validate a fullsize attachment's in memory contents, based on the provided mimetype.
    /// Returns the validated content type, or `file` if validation fails.
    /// Errors are thrown if data reading/parsing fails.
    func validateContents(
        data: Data,
        mimeType: String
    ) throws -> Attachment.ContentType

    /// Validate a fullsize attachment's file contents, based on the provided mimetype.
    /// Returns the validated content type, or `file` if validation fails.
    /// Errors are thrown if file I/O operations fail.
    func validateContents(
        fileUrl: URL,
        mimeType: String
    ) throws -> Attachment.ContentType
}
