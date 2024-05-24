//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension AttachmentReference {

    /// Collection of parameters for building AttachmentReferences.
    ///
    /// Identical to ``AttachmentReference`` except it doesn't have the attachment row id.
    ///
    /// Callers construct Attachments and their references together in one shot, so at the time they do so
    /// they don't yet have an inserted Attachment with an assigned sqlite row id, and can't construct
    /// an AttachmentReference as a result.
    /// Instead they provide one of these, from which we can create an AttachmentReference record for insertion,
    /// and afterwards get back the fully fledged AttachmentReference with id included.
    public struct ConstructionParams {
        public let owner: Owner
        public let sourceFilename: String?
        public let sourceUnencryptedByteCount: UInt32?
        public let sourceMediaSizePixels: CGSize?

        public init(
            owner: Owner,
            sourceFilename: String?,
            sourceUnencryptedByteCount: UInt32?,
            sourceMediaSizePixels: CGSize?
        ) {
            self.owner = owner
            self.sourceFilename = sourceFilename
            self.sourceUnencryptedByteCount = sourceUnencryptedByteCount
            self.sourceMediaSizePixels = sourceMediaSizePixels
        }

        internal func buildRecord(attachmentRowId: Attachment.IDType) throws -> any PersistableRecord {
            switch owner {
            case .message(let messageSource):
                return MessageAttachmentReferenceRecord(
                    attachmentRowId: attachmentRowId,
                    sourceFilename: sourceFilename,
                    sourceUnencryptedByteCount: sourceUnencryptedByteCount,
                    sourceMediaSizePixels: sourceMediaSizePixels,
                    messageSource: messageSource
                )
            case .storyMessage(let storyMessageSource):
                return try StoryMessageAttachmentReferenceRecord(
                    attachmentRowId: attachmentRowId,
                    sourceFilename: sourceFilename,
                    sourceUnencryptedByteCount: sourceUnencryptedByteCount,
                    sourceMediaSizePixels: sourceMediaSizePixels,
                    storyMessageSource: storyMessageSource
                )
            case .thread(let threadSource):
                return ThreadAttachmentReferenceRecord(
                    attachmentRowId: attachmentRowId,
                    threadSource: threadSource
                )
            }
        }
    }
}
