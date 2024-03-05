//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSAttachmentManager {

    public init() {}

    // MARK: - TSMessage Writes

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

    public func createAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        message: TSOutgoingMessage,
        tx: SDSAnyWriteTransaction
    ) throws {
        let isVoiceMessage = message.isVoiceMessage
        let attachmentStreams = try unsavedAttachmentInfos.map {
            try $0.asStreamConsumingDataSource(isVoiceMessage: isVoiceMessage)
        }

        self.addBodyAttachments(attachmentStreams, to: message, tx: tx)

        attachmentStreams.forEach { $0.anyInsert(transaction: tx) }
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

    // MARK: - Helpers

    private func addBodyAttachments(
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
}
