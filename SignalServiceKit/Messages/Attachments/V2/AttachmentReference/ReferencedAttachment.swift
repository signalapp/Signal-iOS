//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Just a simple structure holding an attachment and a reference to it,
/// since that's something we need to do very often.
public class ReferencedAttachment {
    public let reference: AttachmentReference
    public let attachment: Attachment

    public init(reference: AttachmentReference, attachment: Attachment) {
        self.reference = reference
        self.attachment = attachment
    }

    public var asReferencedStream: ReferencedAttachmentStream? {
        guard let attachmentStream = attachment.asStream() else {
            return nil
        }
        return .init(reference: reference, attachmentStream: attachmentStream)
    }
}

public class ReferencedAttachmentStream: ReferencedAttachment {
    public let attachmentStream: AttachmentStream

    public init(reference: AttachmentReference, attachmentStream: AttachmentStream) {
        self.attachmentStream = attachmentStream
        super.init(reference: reference, attachment: attachmentStream.attachment)
    }
}
