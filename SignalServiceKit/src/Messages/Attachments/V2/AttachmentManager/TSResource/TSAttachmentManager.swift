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
        tx: SDSAnyWriteTransaction
    ) {
        let attachmentPointers = TSAttachmentPointer.attachmentPointers(
            fromProtos: protos,
            albumMessage: message
        )
        for pointer in attachmentPointers {
            pointer.anyInsert(transaction: tx)
        }
        self.addBodyAttachments(attachmentPointers, to: message, tx: tx)
    }

    // MARK: - TSMessage Writes

    public func addBodyAttachments(
        _ attachments: [TSAttachment],
        to message: TSMessage,
        tx: SDSAnyWriteTransaction
    ) {
        message.anyUpdateMessage(transaction: tx) { message in
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
        tx: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(message.attachmentIds.contains(attachment.uniqueId))
        attachment.anyRemove(transaction: tx)

        message.anyUpdateMessage(transaction: tx) { message in
            var attachmentIds = message.attachmentIds
            attachmentIds.removeAll(where: { $0 == attachment.uniqueId })
            message.setLegacyBodyAttachmentIds(attachmentIds)
        }
    }
}
