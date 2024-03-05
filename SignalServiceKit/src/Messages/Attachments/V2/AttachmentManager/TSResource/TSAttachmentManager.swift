//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSAttachmentManager {

    public init() {}

    public func createBodyAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        message: TSMessage,
        tx: DBWriteTransaction
    ) {
        let attachmentPointers = TSAttachmentPointer.attachmentPointers(
            fromProtos: protos,
            albumMessage: message
        )
        for pointer in attachmentPointers {
            pointer.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
        }
        self.addBodyAttachments(attachmentPointers, to: message, tx: tx)
    }

    // MARK: - TSMessage Writes

    public func addBodyAttachments(
        _ attachments: [TSAttachment],
        to message: TSMessage,
        tx: DBWriteTransaction
    ) {
        message.anyUpdateMessage(transaction: SDSDB.shimOnlyBridge(tx)) { message in
            var attachmentIds = message.attachmentIds
            var attachmentIdSet = Set(attachmentIds)
            for attachment in attachments {
                if attachmentIdSet.contains(attachment.uniqueId) {
                    continue
                }
                attachmentIds.append(attachment.uniqueId)
                attachmentIdSet.insert(attachment.uniqueId)
            }
            message.setLegacyBodyAttachmentIds(attachmentIds)
        }
    }

    public func removeBodyAttachment(
        _ attachment: TSAttachment,
        from message: TSMessage,
        tx: DBWriteTransaction
    ) {
        owsAssertDebug(message.attachmentIds.contains(attachment.uniqueId))
        attachment.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))

        message.anyUpdateMessage(transaction: SDSDB.shimOnlyBridge(tx)) { message in
            var attachmentIds = message.attachmentIds
            attachmentIds.removeAll(where: { $0 == attachment.uniqueId })
            message.setLegacyBodyAttachmentIds(attachmentIds)
        }
    }
}
