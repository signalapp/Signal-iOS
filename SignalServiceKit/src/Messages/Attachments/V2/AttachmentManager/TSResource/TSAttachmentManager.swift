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

    public func createBodyAttachmentStreams(
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

    // MARK: - Remove Message Attachments

    public func removeBodyAttachments(
        from message: TSMessage,
        removeMedia: Bool,
        removeOversizeText: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        // We remove attachments before
        // anyUpdateWithTransaction, because anyUpdateWithTransaction's
        // block can be called twice, once on this instance and once
        // on the copy from the database.  We only want to remove
        // attachments once.

        var removedIds = Set<String>()
        for attachmentId in message.attachmentIds {
            self.removeAttachment(
                attachmentId: attachmentId,
                filterBlock: { attachment in
                    // We can only discriminate oversize text attachments at the
                    // last minute by consulting the attachment model.
                    if attachment.isOversizeTextMimeType {
                        if removeOversizeText {
                            Logger.verbose("Removing oversize text attachment.")
                            removedIds.insert(attachmentId)
                            return true
                        } else {
                            return false
                        }
                    } else {
                        if removeMedia {
                            Logger.verbose("Removing body attachment.")
                            removedIds.insert(attachmentId)
                            return true
                        } else {
                            return false
                        }
                    }
                },
                tx: tx
            )
        }

        message.anyUpdateMessage(transaction: tx) { message in
            message.setLegacyBodyAttachmentIds(message.attachmentIds.filter { !removedIds.contains($0) })
        }
    }

    public func removeAttachment(
        attachmentId: String,
        tx: SDSAnyWriteTransaction
    ) {
        removeAttachment(attachmentId: attachmentId, filterBlock: { _ in true }, tx: tx)
    }

    private func removeAttachment(
        attachmentId: String,
        filterBlock: (TSAttachment) -> Bool,
        tx: SDSAnyWriteTransaction
    ) {
        if attachmentId.isEmpty {
            owsFailDebug("Invalid attachmentId")
            return
        }

        // We need to fetch each attachment, since [TSAttachment removeWithTransaction:] does important work.
        let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: tx)
        guard let attachment else  {
            Logger.warn("couldn't load interaction's attachment for deletion.")
            return
        }
        if filterBlock(attachment).negated {
            return
        }
        attachment.anyRemove(transaction: tx)
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
