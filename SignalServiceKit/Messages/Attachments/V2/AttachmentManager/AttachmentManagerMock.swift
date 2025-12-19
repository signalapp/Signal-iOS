//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentManagerMock: AttachmentManager {

    open func createAttachmentPointers(
        from protos: [OwnedAttachmentPointerProto],
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func createAttachmentPointers(
        from backupProtos: [OwnedAttachmentBackupPointerProto],
        uploadEra: String,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBWriteTransaction
    ) -> [OwnedAttachmentBackupPointerProto.CreationError] {
        // Do nothing
        return []
    }

    open func createAttachmentStreams(
        from dataSources: [OwnedAttachmentDataSource],
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func updateAttachmentWithOversizeTextFromBackup(
        attachmentId: Attachment.IDType,
        pendingAttachment: PendingAttachment,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func createQuotedReplyMessageThumbnailBuilder(
        from dataSource: QuotedReplyAttachmentDataSource,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<OWSAttachmentInfo> {
        return .withoutFinalizer(OWSAttachmentInfo(
            originalAttachmentMimeType: dataSource.originalAttachmentMimeType,
            originalAttachmentSourceFilename: dataSource.originalAttachmentSourceFilename
        ))
    }

    open func removeAttachment(
        reference: AttachmentReference,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func removeAllAttachments(
        from owners: [AttachmentReference.OwnerId],
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }
}

#endif
