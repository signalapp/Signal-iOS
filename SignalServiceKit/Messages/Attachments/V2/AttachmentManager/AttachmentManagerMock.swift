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
        tx: DBWriteTransaction
    ) -> [OwnedAttachmentBackupPointerProto.CreationError] {
        // Do nothing
        return []
    }

    open func createAttachmentStreams(
        consuming dataSources: [OwnedAttachmentDataSource],
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func quotedReplyAttachmentInfo(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> QuotedAttachmentInfo? {
        return nil
    }

    open func createQuotedReplyMessageThumbnailBuilder(
        from dataSource: QuotedReplyAttachmentDataSource,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo> {
        return .withoutFinalizer(.init(
            info: .stub(
                withOriginalAttachmentMimeType: dataSource.originalAttachmentMimeType,
                originalAttachmentSourceFilename: dataSource.originalAttachmentSourceFilename
            ),
            renderingFlag: dataSource.renderingFlag
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
