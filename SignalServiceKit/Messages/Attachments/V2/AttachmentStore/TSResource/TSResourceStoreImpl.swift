//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceStoreImpl: TSResourceStore {

    private let attachmentStore: AttachmentStoreImpl
    private let attachmentUploadStore: AttachmentUploadStore

    public init(
        attachmentStore: AttachmentStoreImpl,
        attachmentUploadStore: AttachmentUploadStore
    ) {
        self.attachmentStore = attachmentStore
        self.attachmentUploadStore = attachmentUploadStore
    }

    public func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        var v2Ids = [Attachment.IDType]()
        ids.forEach {
            switch $0 {
            case .v2(let rowId):
                v2Ids.append(rowId)
            }
        }
        return attachmentStore.fetch(ids: v2Ids, tx: tx)
    }

    // MARK: - Message Attachment fetching

    public func allAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        let v2References: [TSResourceReference]

        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Fetching attachments for an un-inserted message!")
            return []
        }
        v2References = attachmentStore
            .fetchReferences(
                owners: AttachmentReference.MessageOwnerTypeRaw.allCases.map {
                    $0.with(messageRowId: messageRowId)
                },
                tx: tx
            )

        return v2References
    }

    public func bodyAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        if message.attachmentIds?.isEmpty != false {
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
            return []
        }
    }

    public func bodyMediaAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        if message.attachmentIds?.isEmpty != false {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return []
            }
            return attachmentStore.fetchReferences(owner: .messageBodyAttachment(messageRowId: messageRowId), tx: tx)
        } else {
            return []
        }
    }

    public func oversizeTextAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Fetching attachments for an un-inserted message!")
            return nil
        }
        return attachmentStore.fetchFirstReference(owner: .messageOversizeText(messageRowId: messageRowId), tx: tx)
    }

    public func contactShareAvatarAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        if
            let contactShare = message.contactShare,
            contactShare.legacyAvatarAttachmentId == nil
        {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return nil
            }
            return attachmentStore.fetchFirstReference(owner: .messageContactAvatar(messageRowId: messageRowId), tx: tx)
        }
        return nil
    }

    public func linkPreviewAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        guard let linkPreview = message.linkPreview else {
            return nil
        }
        if linkPreview.usesV2AttachmentReference {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return nil
            }
            return attachmentStore.fetchFirstReference(owner: .messageLinkPreview(messageRowId: messageRowId), tx: tx)
        } else {
            return nil
        }
    }

    public func stickerAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        guard let messageSticker = message.messageSticker else {
            return nil
        }
        if let legacyAttachmentId = messageSticker.legacyAttachmentId {
            return nil
        } else {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Fetching attachments for an un-inserted message!")
                return nil
            }
            return attachmentStore.fetchFirstReference(owner: .messageSticker(messageRowId: messageRowId), tx: tx)
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
            if let stub = TSQuotedMessageResourceReference.Stub(info) {
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
            let originalMessageRowId = originalMessage.sqliteRowId,
            let attachment = attachmentStore.attachmentToUseInQuote(originalMessageRowId: originalMessageRowId, tx: tx)
        {
            return attachment
        } else {
            return nil
        }
    }

    // MARK: - Story Message Attachment Fetching

    public func mediaAttachment(
        for storyMessage: StoryMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference? {
        switch storyMessage.attachment {
        case .text:
            return nil
        case .file(let storyMessageFileAttachment):
            return nil
        case .foreignReferenceAttachment:
            guard let storyMessageRowId = storyMessage.id else {
                owsFailDebug("Fetching attachments for an un-inserted story message!")
                return nil
            }
            return attachmentStore.fetchFirstReference(
                owner: .storyMessageMedia(storyMessageRowId: storyMessageRowId),
                tx: tx
            )
        }
    }

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
            if linkPreview.usesV2AttachmentReference {
                guard let storyMessageRowId = storyMessage.id else {
                    owsFailDebug("Fetching attachments for an un-inserted story message!")
                    return nil
                }
                return attachmentStore.fetchFirstReference(
                    owner: .storyMessageLinkPreview(storyMessageRowId: storyMessageRowId),
                    tx: tx
                )
            } else {
                return nil
            }
        }
    }
}

// MARK: - TSResourceUploadStore

extension TSResourceStoreImpl: TSResourceUploadStore {

    public func updateAsUploaded(
        attachmentStream: TSResourceStream,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws {
        let attachment = attachmentStream.concreteStreamType
        try attachmentUploadStore.markUploadedToTransitTier(
            attachmentStream: attachment,
            info: info,
            tx: tx
        )
    }
}
