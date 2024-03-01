//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceStoreImpl: TSResourceStore {

    private let tsAttachmentStore: TSAttachmentStore

    public init(tsAttachmentStore: TSAttachmentStore) {
        self.tsAttachmentStore = tsAttachmentStore
    }

    public func fetch(_ id: TSResourceId, tx: DBReadTransaction) -> TSResource? {
        switch id {
        case .legacy(let uniqueId):
            return tsAttachmentStore.attachments(withAttachmentIds: [uniqueId], tx: tx).first
        }
    }

    public func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        var legacyIds = [String]()
        ids.forEach {
            switch $0 {
            case .legacy(let uniqueId):
                legacyIds.append(uniqueId)
            }
        }
        return tsAttachmentStore.attachments(withAttachmentIds: legacyIds, tx: tx)
    }

    // MARK: - Message Attachment fetching

    public func allAttachments(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReferences {
        var ids = Set<TSResourceId>()

        self.bodyAttachments(for: message, tx: tx).references.forEach { ids.insert($0.id) }
        [
            self.quotedMessageThumbnailAttachment(for: message, tx: tx),
            self.contactShareAvatarAttachment(for: message, tx: tx),
            self.linkPreviewAttachment(for: message, tx: tx),
            self.stickerAttachment(for: message, tx: tx)
        ].forEach {
            guard let id = $0?.id else { return }
            ids.insert(id)
        }

        return references(ids: Array(ids), tx: tx)
    }

    public func bodyAttachments(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReferences {
        if message.attachmentIds.isEmpty {
            // TODO: fetch v2 attachments
            return .empty
        } else {
            return legacyReferences(uniqueIds: message.attachmentIds, tx: tx)
        }
    }

    public func bodyMediaAttachments(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReferences {
        if message.attachmentIds.isEmpty {
            // TODO: fetch v2 attachments
            return .empty
        } else {
            let attachments = tsAttachmentStore.attachments(
                withAttachmentIds: message.attachmentIds,
                ignoringContentType: OWSMimeTypeOversizeTextMessage,
                tx: tx
            )
            return references(resources: attachments)
        }
    }

    public func oversizeTextAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        if message.attachmentIds.isEmpty {
            // TODO: fetch v2 attachments
            return nil
        } else {
            let attachment = tsAttachmentStore.attachments(
                withAttachmentIds: message.attachmentIds,
                matchingContentType: OWSMimeTypeOversizeTextMessage,
                tx: tx
            ).first
            return reference(resource: attachment)
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

    // MARK: - Message attachment writes

    public func addBodyAttachments(
        _ attachments: [TSResource],
        to message: TSMessage,
        tx: DBWriteTransaction
    ) {
        var legacyAttachments = [TSAttachment]()
        attachments.forEach {
            switch $0.concreteType {
            case let .legacy(attachment):
                legacyAttachments.append(attachment)
            }
        }
        tsAttachmentStore.addBodyAttachments(legacyAttachments, to: message, tx: tx)
    }

    public func removeBodyAttachment(
        _ attachment: TSResource,
        from message: TSMessage,
        tx: DBWriteTransaction
    ) {
        switch attachment.concreteType {
        case .legacy(let legacyAttachment):
            tsAttachmentStore.removeBodyAttachment(legacyAttachment, from: message, tx: tx)
        }
    }

    // MARK: - Helpers

    private func legacyReference(uniqueId: String?, tx: DBReadTransaction) -> TSResourceReference? {
        guard
            let uniqueId,
            let attachment = tsAttachmentStore.attachments(withAttachmentIds: [uniqueId], tx: tx).first
        else {
            return nil
        }
        return TSResourceReference(
            id: .legacy(uniqueId: uniqueId),
            sourceFilename: attachment.sourceFilename,
            fetcher: { innerTx in
                // Re-fetch the attachment.
                return self.fetch(.legacy(uniqueId: uniqueId), tx: innerTx)
            }
        )
    }

    private func reference(resource: TSResource?) -> TSResourceReference? {
        guard let resourceId = resource?.resourceId else {
            return nil
        }
        switch resource?.concreteType {
        case nil:
            return nil
        case .legacy(let attachment):
            return TSResourceReference(
                id: resourceId,
                sourceFilename: attachment.sourceFilename,
                fetcher: { innerTx in
                    // Re-fetch the attachment.
                    return self.fetch(resourceId, tx: innerTx)
                }
            )
        }
    }

    private func legacyReferences(uniqueIds: [String], tx: DBReadTransaction) -> TSResourceReferences {
        let ids = uniqueIds.map { TSResourceId.legacy(uniqueId: $0) }
        let attachments = tsAttachmentStore.attachments(withAttachmentIds: uniqueIds, tx: tx)
        return TSResourceReferences(
            references: attachments.map {
                let id = TSResourceId.legacy(uniqueId: $0.uniqueId)
                return .init(
                    id: id,
                    sourceFilename: $0.sourceFilename,
                    fetcher: { innerTx in
                        // Re-fetch the attachment.
                        return self.fetch(id, tx: innerTx)
                    })
            },
            fetcher: { innerTx in
                return self.fetch(ids, tx: innerTx)
            }
        )
    }

    private func references(resources: [TSResource]) -> TSResourceReferences {
        let ids = resources.map(\.resourceId)
        return TSResourceReferences(
            references: resources.compactMap { self.reference(resource: $0) },
            fetcher: { innerTx in
                // Re-fetch the attachments
                return self.fetch(ids, tx: innerTx)
            }
        )
    }

    private func references(ids: [TSResourceId], tx: DBReadTransaction) -> TSResourceReferences {
        var legacyIds = [String]()
        ids.forEach {
            switch $0 {
            case .legacy(let uniqueId):
                legacyIds.append(uniqueId)
            }
        }
        let legacyAttachments = tsAttachmentStore.attachments(withAttachmentIds: legacyIds, tx: tx)
        return TSResourceReferences(
            references: legacyAttachments.map {
                let id = TSResourceId.legacy(uniqueId: $0.uniqueId)
                return .init(
                    id: id,
                    sourceFilename: $0.sourceFilename,
                    fetcher: { innerTx in
                        // Re-fetch the attachment.
                        return self.fetch(id, tx: innerTx)
                    })
            },
            fetcher: { innerTx in
                return self.fetch(ids, tx: innerTx)
            }
        )
    }
}
