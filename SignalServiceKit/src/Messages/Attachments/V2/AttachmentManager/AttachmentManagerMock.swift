//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentManagerMock: AttachmentManager {

    open func createAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    open func createAttachment(
        from proto: SSKProtoAttachmentPointer,
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func createAttachment(
        rawFileData: Data,
        mimeType: String,
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func createAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func quotedReplyAttachmentInfo(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> OWSAttachmentInfo? {
        return nil
    }

    open func createQuotedReplyMessageThumbnail(
        originalMessage: TSMessage,
        quotedReplyMessageId: Int64,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func removeAttachment(
        _ attachment: TSResource,
        from owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    open func removeAllAttachments(
        from owners: [AttachmentReference.OwnerId],
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }
}

#endif
