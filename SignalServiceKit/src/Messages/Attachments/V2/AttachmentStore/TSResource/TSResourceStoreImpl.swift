//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceStoreImpl: TSResourceStore {

    private let tsAttachmentStore: TSAttachmentStore

    public init() {
        self.tsAttachmentStore = TSAttachmentStore()
    }

    public func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        var legacyIds = [String]()
        ids.forEach {
            switch $0 {
            case .legacy(let uniqueId):
                legacyIds.append(uniqueId)
            }
        }
        return tsAttachmentStore.attachments(withAttachmentIds: legacyIds, tx: SDSDB.shimOnlyBridge(tx))
    }

    // MARK: - Message Attachment fetching

    public func allAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        var ids = Set<TSResourceId>()

        return (self.bodyAttachments(for: message, tx: tx) + [
            self.quotedMessageThumbnailAttachment(for: message, tx: tx),
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
        if message.attachmentIds.isEmpty {
            // TODO: fetch v2 attachments
            return []
        } else {
            return tsAttachmentStore.attachments(withAttachmentIds: message.attachmentIds, tx: SDSDB.shimOnlyBridge(tx))
                .map(TSAttachmentReference.init(_:))
        }
    }

    public func bodyMediaAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        if message.attachmentIds.isEmpty {
            // TODO: fetch v2 attachments
            return []
        } else {
            return tsAttachmentStore.attachments(
                withAttachmentIds: message.attachmentIds,
                ignoringContentType: OWSMimeTypeOversizeTextMessage,
                tx: SDSDB.shimOnlyBridge(tx)
            ).map(TSAttachmentReference.init(_:))
        }
    }

    public func oversizeTextAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        if message.attachmentIds.isEmpty {
            // TODO: fetch v2 attachments
            return nil
        } else {
            guard
                let attachment = tsAttachmentStore.attachments(
                    withAttachmentIds: message.attachmentIds,
                    matchingContentType: OWSMimeTypeOversizeTextMessage,
                    tx: SDSDB.shimOnlyBridge(tx)
                ).first
            else {
                return nil
            }
            return TSAttachmentReference(attachment)
        }
    }

    public func quotedMessageThumbnailAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        // TODO: merge this with QuotedMessageAttachmentHelper
        let id = message.quotedMessage?.fetchThumbnailAttachmentId(
            forParentMessage: message,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        return legacyReference(uniqueId: id, tx: tx)
    }

    public func contactShareAvatarAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        // TODO: bifurcate legacy and v2 here.
        return legacyReference(uniqueId: message.contactShare?.avatarAttachmentId, tx: tx)
    }

    public func linkPreviewAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        // TODO: merge this with OWSLinkPreview+Attachment
        let id = message.linkPreview?.imageAttachmentId(forParentMessage: message, tx: SDSDB.shimOnlyBridge(tx))
        return legacyReference(uniqueId: id, tx: tx)
    }

    public func stickerAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        // TODO: bifurcate legacy and v2 here.
        return legacyReference(uniqueId: message.messageSticker?.attachmentId, tx: tx)
    }

    public func indexForBodyAttachmentId(_ attachmentId: TSResourceId, on message: TSMessage, tx: DBReadTransaction) -> Int? {
        switch attachmentId {
        case .legacy(let uniqueId):
            return message.attachmentIds.firstIndex(of: uniqueId)
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
        }
    }
}

// MARK: - Helpers
extension TSResourceStoreImpl {

    private func legacyReference(uniqueId: String?, tx: DBReadTransaction) -> TSResourceReference? {
        guard
            let uniqueId,
            let attachment = tsAttachmentStore.attachments(withAttachmentIds: [uniqueId], tx: SDSDB.shimOnlyBridge(tx)).first
        else {
            return nil
        }
        return TSAttachmentReference(attachment)
    }
}
