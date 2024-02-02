//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentStore {

    func anyInsert(
        _ attachment: TSAttachment,
        tx: DBWriteTransaction
    )

    func fetchAttachmentStream(
        uniqueId: String,
        tx: DBReadTransaction
    ) -> TSAttachmentStream?

    func updateAsUploaded(
        attachmentStream: TSAttachmentStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    )
}

public class AttachmentStoreImpl: AttachmentStore {

    public init() {}

    public func anyInsert(_ attachment: TSAttachment, tx: DBWriteTransaction) {
        attachment.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchAttachmentStream(
        uniqueId: String,
        tx: DBReadTransaction
    ) -> TSAttachmentStream? {
        TSAttachmentStream.anyFetchAttachmentStream(
            uniqueId: uniqueId,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func updateAsUploaded(
        attachmentStream: TSAttachmentStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        attachmentStream.updateAsUploaded(
            withEncryptionKey: encryptionKey,
            digest: digest,
            serverId: 0, // Only used in cdn0 uploads, which aren't supported here.
            cdnKey: cdnKey,
            cdnNumber: cdnNumber,
            uploadTimestamp: uploadTimestamp,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

#if TESTABLE_BUILD

open class AttachmentStoreMock: AttachmentStore {
    public init() {}

    public var attachments = [TSAttachment]()

    public func anyInsert(_ attachment: TSAttachment, tx: DBWriteTransaction) {
        self.attachments.append(attachment)
    }

    public func fetchAttachmentStream(uniqueId: String, tx: DBReadTransaction) -> TSAttachmentStream? {
        return nil
    }

    public func updateAsUploaded(
        attachmentStream: TSAttachmentStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) { }
}

#endif
