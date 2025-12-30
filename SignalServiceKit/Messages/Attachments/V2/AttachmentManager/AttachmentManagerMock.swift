//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentManagerMock: AttachmentManager {

    open func createAttachmentPointer(
        from ownedProto: OwnedAttachmentPointerProto,
        tx: DBWriteTransaction,
    ) throws {
        // Do nothing
    }

    open func createAttachmentPointer(
        from ownedBackupProto: OwnedAttachmentBackupPointerProto,
        uploadEra: String,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBWriteTransaction,
    ) -> OwnedAttachmentBackupPointerProto.CreationError? {
        // Do nothing
        return nil
    }

    open func createAttachmentStream(
        from ownedDataSource: OwnedAttachmentDataSource,
        tx: DBWriteTransaction,
    ) throws {
        // Do nothing
    }

    open func updateAttachmentWithOversizeTextFromBackup(
        attachmentId: Attachment.IDType,
        pendingAttachment: PendingAttachment,
        tx: DBWriteTransaction,
    ) throws {
        // Do nothing
    }

    open func createQuotedReplyMessageThumbnail(
        from quotedReplyAttachmentDataSource: QuotedReplyAttachmentDataSource,
        owningMessageAttachmentBuilder: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder,
        tx: DBWriteTransaction,
    ) throws {
        // Do nothing
    }

    open func removeAttachment(
        reference: AttachmentReference,
        tx: DBWriteTransaction,
    ) throws {
        // Do nothing
    }

    open func removeAllAttachments(
        from owners: [AttachmentReference.OwnerId],
        tx: DBWriteTransaction,
    ) throws {
        // Do nothing
    }
}

#endif
