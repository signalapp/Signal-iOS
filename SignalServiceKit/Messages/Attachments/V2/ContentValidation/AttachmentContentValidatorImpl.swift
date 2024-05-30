//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentContentValidatorImpl: AttachmentContentValidator {

    public init() {}

    public func validateContents(
        data: Data,
        mimeType: String
    ) throws -> Attachment.ContentType {
        fatalError("Unimplemented")
    }

    public func validateContents(
        fileUrl: URL,
        mimeType: String
    ) throws -> Attachment.ContentType {
        fatalError("Unimplemented")
    }
}
