//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceStoreImpl: TSResourceStore {

    private let attachmentStore: AttachmentStoreImpl
    private let tsAttachmentStore: TSAttachmentStore

    public init(attachmentStore: AttachmentStoreImpl) {
        self.attachmentStore = attachmentStore
        self.tsAttachmentStore = TSAttachmentStore()
    }

    public func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        var legacyIds = [String]()
        var v2Ids = [Attachment.IDType]()
        ids.forEach {
            switch $0 {
            case .legacy(let uniqueId):
                legacyIds.append(uniqueId)
            case .v2(let rowId):
                v2Ids.append(rowId)
            }
        }
        var resources: [TSResource] = tsAttachmentStore.attachments(
            withAttachmentIds: legacyIds,
            tx: SDSDB.shimOnlyBridge(tx)
        )
        if v2Ids.isEmpty.negated {
            resources.append(contentsOf: attachmentStore.fetch(ids: v2Ids, tx: tx))
        }
        return resources
    }

    // MARK: - Message Attachment fetching

    public func allAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        // TODO: we can make this method more efficient if its more knowledgeable
        // For v1, just grab all the fields one by one.
        // For v2, do a single fetch with all message owner types.
        var ids = Set<TSResourceId>()

        return (self.bodyAttachments(for: message, tx: tx) + [
            self.quotedThumbnailAttachment(for: message, tx: tx),
            self.contactShareAvatarAttachment(for: message, tx: tx),
            self.linkPreviewAttachment(for: message, tx: tx),
            self.stickerAttachment(for: message, tx: tx)
        ]).compactMap { reference in
            guard
                let reference,
                !ids.contains(reference.resourceId)
            else {
                return nil
            }
            ids.insert(reference.resourceId)
            return reference
        }
    }

    public func bodyAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        if FeatureFlags.newAttachmentsUseV2, message.attachmentIds.isEmpty {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return []
            }
            // For legacy reasons, an oversized text attachment is considered a "body" attachment.
            return attachmentStore.fetchReferences(
                owners: [
                    .messageBodyAttachment(messageRowId: messageRowId),
                    .messageOversizeText(messageRowId: messageRowId)
                ],
                tx: tx
            )
        } else {
            let attachments = tsAttachmentStore.attachments(withAttachmentIds: message.attachmentIds, tx: SDSDB.shimOnlyBridge(tx))
            let attachmentMap = Dictionary(uniqueKeysWithValues: attachments.map { ($0.uniqueId, $0) })
            return message.attachmentIds.map { uniqueId in
                TSAttachmentReference(uniqueId: uniqueId, attachment: attachmentMap[uniqueId])
            }
        }
    }

    public func bodyMediaAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        if FeatureFlags.newAttachmentsUseV2, message.attachmentIds.isEmpty {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return []
            }
            return attachmentStore.fetchReferences(owner: .messageBodyAttachment(messageRowId: messageRowId), tx: tx)
        } else {
            let attachments = tsAttachmentStore.attachments(
                withAttachmentIds: message.attachmentIds,
                ignoringContentType: OWSMimeTypeOversizeTextMessage,
                tx: SDSDB.shimOnlyBridge(tx)
            )
            // If we fail to fetch any attachments, we don't know if theyre media or
            // oversize text, so we can't return them even as a reference.
            return attachments.map {
                TSAttachmentReference(uniqueId: $0.uniqueId, attachment: $0)
            }
        }
    }

    public func oversizeTextAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        if FeatureFlags.newAttachmentsUseV2, message.attachmentIds.isEmpty {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return nil
            }
            return attachmentStore.fetchFirstReference(owner: .messageOversizeText(messageRowId: messageRowId), tx: tx)
        } else {
            guard
                let attachment = tsAttachmentStore.attachments(
                    withAttachmentIds: message.attachmentIds,
                    matchingContentType: OWSMimeTypeOversizeTextMessage,
                    tx: SDSDB.shimOnlyBridge(tx)
                ).first
            else {
                /// We can't tell from the unique id if its an oversized text attachment, so if the attachment
                /// lookup fails for any reason, we return nil.
                return nil
            }
            return TSAttachmentReference(uniqueId: attachment.uniqueId, attachment: attachment)
        }
    }

    public func contactShareAvatarAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        if
            FeatureFlags.readV2Attachments,
            let contactShare = message.contactShare,
            contactShare.legacyAvatarAttachmentId == nil
        {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return nil
            }
            return attachmentStore.fetchFirstReference(owner: .messageContactAvatar(messageRowId: messageRowId), tx: tx)
        }
        return legacyReference(uniqueId: message.contactShare?.legacyAvatarAttachmentId, tx: tx)
    }

    public func linkPreviewAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        guard let linkPreview = message.linkPreview else {
            return nil
        }
        if FeatureFlags.readV2Attachments, linkPreview.usesV2AttachmentReference {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return nil
            }
            return attachmentStore.fetchFirstReference(owner: .messageLinkPreview(messageRowId: messageRowId), tx: tx)
        } else {
            return legacyReference(uniqueId: linkPreview.legacyImageAttachmentId, tx: tx)
        }
    }

    public func stickerAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        if
            FeatureFlags.readV2Attachments,
            let messageSticker = message.messageSticker,
            // TODO: need to make this attachment id nullable
            messageSticker.legacyAttachmentId == nil
        {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return nil
            }
            return attachmentStore.fetchFirstReference(owner: .messageSticker(messageRowId: messageRowId), tx: tx)
        }
        return legacyReference(uniqueId: message.messageSticker?.legacyAttachmentId, tx: tx)
    }

    public func indexForBodyAttachmentId(
        _ attachmentId: TSResourceId,
        on message: TSMessage,
        tx: DBReadTransaction
    ) -> Int? {
        switch attachmentId {
        case .legacy(let uniqueId):
            return message.attachmentIds.firstIndex(of: uniqueId)
        case .v2(let rowId):
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return nil
            }
            // Do filtering in memory; there is a fixed max # of body attachments
            // per message and these are just references.
            return attachmentStore
                .fetchReferences(
                    owner: .messageBodyAttachment(messageRowId: messageRowId),
                    tx: tx
                )
                .lazy
                .filter { $0.attachmentRowId == rowId }
                .compactMap {
                    switch $0.owner {
                    case .message(.bodyAttachment(let metadata)):
                        let index: UInt32 = metadata.index
                        // Safe UInt -> Int64 cast.
                        return Int(index)
                    default:
                        return nil
                    }
                }
                .first
        }
    }

    // MARK: - Quoted Messages

    public func quotedAttachmentReference(
        from info: OWSAttachmentInfo,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> TSQuotedMessageResourceReference? {
        switch info.attachmentType {
        case .V2:
            return attachmentStore.quotedAttachmentReference(
                from: info,
                parentMessage: parentMessage,
                tx: tx
            )?.tsReference
        case .unset, .original, .originalForSend, .thumbnail, .untrustedPointer:
            fallthrough
        @unknown default:
            if let reference = self.legacyReference(uniqueId: info.attachmentId, tx: tx) {
                return .thumbnail(reference)
            } else if let stub = TSQuotedMessageResourceReference.Stub(info) {
                return .stub(stub)
            } else {
                return nil
            }
        }
    }

    public func attachmentToUseInQuote(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference? {
        if
            FeatureFlags.readV2Attachments,
            let attachment = attachmentStore.attachmentToUseInQuote(originalMessage: originalMessage, tx: tx)
        {
            return attachment
        } else {
            guard
                let attachment = tsAttachmentStore.attachmentToUseInQuote(
                    originalMessage: originalMessage,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            else {
                return nil
            }
            return TSAttachmentReference(uniqueId: attachment.uniqueId, attachment: attachment)
        }
    }

    // MARK: - Story Message Attachment Fetching

    public func linkPreviewAttachment(
        for storyMessage: StoryMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference? {
        switch storyMessage.attachment {
        case .file, .foreignReferenceAttachment:
            return nil
        case .text(let textAttachment):
            guard let linkPreview = textAttachment.preview else {
                return nil
            }
            if FeatureFlags.readV2Attachments, linkPreview.usesV2AttachmentReference {
                guard let storyMessageRowId = storyMessage.id else {
                    owsFailDebug("Fetching attachments for an un-inserted story message!")
                    return nil
                }
                return attachmentStore.fetchFirstReference(
                    owner: .storyMessageLinkPreview(storyMessageRowId: storyMessageRowId),
                    tx: tx
                )
            } else {
                return legacyReference(uniqueId: linkPreview.legacyImageAttachmentId, tx: tx)
            }
        }
    }
}

// MARK: - TSResourceUploadStore

extension TSResourceStoreImpl: TSResourceUploadStore {

    public func updateAsUploaded(
        attachmentStream: TSResourceStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        switch attachmentStream.concreteStreamType {
        case .legacy(let tSAttachment):
            tSAttachment.updateAsUploaded(
                withEncryptionKey: encryptionKey,
                digest: digest,
                serverId: 0, // Only used in cdn0 uploads, which aren't supported here.
                cdnKey: cdnKey,
                cdnNumber: cdnNumber,
                uploadTimestamp: uploadTimestamp,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        case .v2(let attachment):
            attachmentStore.markUploadedToTransitTier(
                attachmentStream: attachment,
                cdnKey: cdnKey,
                cdnNumber: cdnNumber,
                uploadTimestamp: uploadTimestamp,
                tx: tx
            )
        }
    }
}

// MARK: - Helpers
extension TSResourceStoreImpl {

    private func legacyReference(uniqueId: String?, tx: DBReadTransaction) -> TSResourceReference? {
        guard let uniqueId else {
            return nil
        }
        let attachment = tsAttachmentStore.attachments(withAttachmentIds: [uniqueId], tx: SDSDB.shimOnlyBridge(tx)).first
        return TSAttachmentReference(uniqueId: uniqueId, attachment: attachment)
    }
}
