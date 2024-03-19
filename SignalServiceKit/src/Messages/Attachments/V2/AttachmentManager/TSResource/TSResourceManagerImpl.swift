//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceManagerImpl: TSResourceManager {

    private let attachmentManager: AttachmentManagerImpl
    private let attachmentStore: AttachmentStore
    private let tsAttachmentManager: TSAttachmentManager
    private let tsResourceStore: TSResourceStore

    public init(
        attachmentManager: AttachmentManagerImpl,
        attachmentStore: AttachmentStore,
        tsResourceStore: TSResourceStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.tsAttachmentManager = TSAttachmentManager()
        self.tsResourceStore = tsResourceStore
    }

    // MARK: - Protos

    public func createBodyAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        message: TSMessage,
        tx: DBWriteTransaction
    ) {
        if FeatureFlags.newAttachmentsUseV2 {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Adding attachments to an uninserted message!")
                return
            }
            attachmentManager.createAttachmentPointers(
                from: protos,
                owner: .messageBodyAttachment(messageRowId: messageRowId),
                tx: tx
            )
        } else {
            tsAttachmentManager.createBodyAttachmentPointers(
                from: protos,
                message: message,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }

    public func createBodyAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        message: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) throws {
        if FeatureFlags.newAttachmentsUseV2 {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Adding attachments to an uninserted message!")
                return
            }
            try attachmentManager.createAttachmentStreams(
                consumingDataSourcesOf: unsavedAttachmentInfos,
                owner: .messageBodyAttachment(messageRowId: messageRowId),
                tx: tx
            )
        } else {
            try tsAttachmentManager.createBodyAttachmentStreams(
                consumingDataSourcesOf: unsavedAttachmentInfos,
                message: message,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }

    public func createQuotedReplyAttachmentBuilder(
        fromUntrustedRemote proto: SSKProtoAttachmentPointer,
        tx: DBWriteTransaction
    ) -> QuotedMessageAttachmentBuilder? {
        if FeatureFlags.newAttachmentsUseV2 {
            return attachmentManager.createQuotedReplyAttachmentBuilder(
                fromUntrustedRemote: proto,
                tx: tx
            )
        } else {
            guard
                let info = tsAttachmentManager.createQuotedReplyAttachment(
                    fromUntrustedRemote: proto,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            else {
                return nil
            }
            return NoOpFinalizingAttachmentBuilder(attachmentInfo: info)
        }
    }

    public func buildProtoForSending(
        from reference: TSResourceReference,
        pointer: TSResourcePointer
    ) -> SSKProtoAttachmentPointer? {
        switch pointer.resource.concreteType {
        case .legacy(let tsAttachment):
            guard let stream = tsAttachment as? TSAttachmentStream else {
                return nil
            }
            return stream.buildProto()
        case .v2(let attachment):
            switch reference.concreteType {
            case .legacy:
                owsFailDebug("Invalid attachment type combination!")
                return nil
            case .v2(let attachmentReference):
                guard let attachmentPointer = AttachmentTransitPointer(attachment: attachment) else {
                    owsFailDebug("Invalid attachment type combination!")
                    return nil
                }
                return attachmentManager.buildProtoForSending(
                    from: attachmentReference,
                    pointer: attachmentPointer
                )
            }
        }
    }

    // MARK: - Removes and Deletes

    public func removeBodyAttachment(
        _ attachment: TSResource,
        from message: TSMessage,
        tx: DBWriteTransaction
    ) {
        switch attachment.concreteType {
        case .legacy(let legacyAttachment):
            tsAttachmentManager.removeBodyAttachment(legacyAttachment, from: message, tx: SDSDB.shimOnlyBridge(tx))
        case .v2(let attachment):
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Removing attachment from uninserted message!")
                return
            }
            attachmentManager.removeAttachment(
                attachment,
                from: .messageBodyAttachment(messageRowId: messageRowId),
                tx: tx
            )
        }
    }

    public func removeAttachments(
        from message: TSMessage,
        with types: TSMessageAttachmentReferenceType,
        tx: DBWriteTransaction
    ) {
        message.anyReload(transaction: SDSDB.shimOnlyBridge(tx), ignoreMissing: true)

        var v2Owners = [AttachmentReference.OwnerTypeRaw]()

        if types.contains(.bodyAttachment) || types.contains(.oversizeText) {
            if message.attachmentIds.count > 0 {
                tsAttachmentManager.removeBodyAttachments(
                    from: message,
                    removeMedia: types.contains(.bodyAttachment),
                    removeOversizeText: types.contains(.oversizeText),
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            } else {
                if types.contains(.bodyAttachment) {
                    v2Owners.append(.messageBodyAttachment)
                }
                if types.contains(.oversizeText) {
                    v2Owners.append(.messageOversizeText)
                }
            }
        }

        if types.contains(.linkPreview), let linkPreview = message.linkPreview {
            Logger.verbose("Removing link preview attachment.")
            // TODO: move this into this class
            linkPreview.removeAttachment(tx: SDSDB.shimOnlyBridge(tx))
        }

        if types.contains(.sticker), let messageSticker = message.messageSticker {
            Logger.verbose("Removing sticker attachment.")
            // TODO: differentiate legacy and v2
            tsAttachmentManager.removeAttachment(attachmentId: messageSticker.attachmentId, tx: SDSDB.shimOnlyBridge(tx))
        }

        if
            types.contains(.quotedReply),
            let quoteAttachmentInfo = message.quotedMessage?.attachmentInfo()
        {
            Logger.verbose("Removing quoted reply attachment.")
            if quoteAttachmentInfo.attachmentType == OWSAttachmentInfoReference.V2 {
                v2Owners.append(.quotedReplyAttachment)
            } else if let id = quoteAttachmentInfo.attachmentId {
                tsAttachmentManager.removeAttachment(attachmentId: id, tx: SDSDB.shimOnlyBridge(tx))
            }
        }

        if
            types.contains(.contactAvatar),
            let contactShare = message.contactShare,
            let contactShareAttachmentId = contactShare.avatarAttachmentId
        {
            Logger.verbose("Removing contact share attachment.")
            // TODO: differentiate legacy and v2
            tsAttachmentManager.removeAttachment(attachmentId: contactShareAttachmentId, tx: SDSDB.shimOnlyBridge(tx))
        }

        if FeatureFlags.readV2Attachments {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Removing attachments from un-inserted message.")
                return
            }
            attachmentManager.removeAllAttachments(
                from: v2Owners.map { $0.with(ownerId: messageRowId) },
                tx: tx
            )
        }
    }

    // MARK: - Quoted reply thumbnails

    public func createThumbnailAndUpdateMessageIfNecessary(
        quotedMessage: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBWriteTransaction
    ) -> TSResourceStream? {
        switch quotedMessage.attachmentInfo()?.attachmentType {
        case nil:
            return nil
        case .V2:
            guard let messageRowId = parentMessage.sqliteRowId else {
                owsFailDebug("Clonign thumbnail attachment from un-inserted message.")
                return nil
            }
            let attachment = attachmentStore.fetchFirst(owner: .quotedReplyAttachment(messageRowId: messageRowId), tx: tx)

            // If its a stream, its the thumbnail (we do cloning and resizing at download time).
            // If its not a stream, that's because its undownloaded and we should return nil.
            return attachment?.asStream()
        case
                .unset,
                .originalForSend,
                .original,
                .thumbnail,
                .untrustedPointer:
            fallthrough
        @unknown default:
            return tsAttachmentManager.createThumbnailAndUpdateMessageIfNecessary(
                parentMessage: parentMessage,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }

    public func newQuotedReplyMessageThumbnailBuilder(
        originalMessage: TSMessage,
        tx: DBWriteTransaction
    ) -> QuotedMessageAttachmentBuilder? {
        // Normally, we decide whether to create a v1 or v2 attachment based on
        // FeatureFlags.newAttachmentsUseV2. Here, though, we re-use whatever type
        // v1 or v2 that the original message was using.
        // This does mean we could end up creating v1 attachments even after starting creating
        // v2 ones, but the migration should eventually catch up.
        // Remember that both this code and any migrations use write transactions, so
        // that serves as a global lock that ensures there aren't races; new quotes create
        // new v1 attachments but not while the migration is running.
        let originalAttachmentRef = tsResourceStore.attachmentToUseInQuote(
            originalMessage: originalMessage,
            tx: tx
        )
        switch originalAttachmentRef?.concreteType {
        case nil:
            return nil
        case .legacy(let tSAttachmentReference):
            guard let attachment = tSAttachmentReference.attachment else {
                return nil
            }
            guard
                let info = tsAttachmentManager.cloneThumbnailForNewQuotedReplyMessage(
                    originalAttachment: attachment,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            else {
                return nil
            }
            return NoOpFinalizingAttachmentBuilder(attachmentInfo: info)
        case .v2(let originalReference):
            return attachmentManager.newQuotedReplyMessageThumbnailBuilder(
                originalReference: originalReference,
                tx: tx
            )
        }
    }

    public func thumbnailImage(
        thumbnail: TSQuotedMessageResourceReference.Thumbnail,
        attachment: TSResource,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> UIImage? {
        switch attachment.concreteType {
        case .v2(let attachment):
            guard let stream = attachment.asStream() else {
                return nil
            }
            // If it is an attachment stream, it should already be pointing at the resized
            // thumbnail image, no copying needed.
            return stream.thumbnailImageSync(quality: .small)
        case .legacy(let tsAttachment):
            guard let info = parentMessage.quotedMessage?.attachmentInfo() else {
                return nil
            }
            return tsAttachmentManager.thumbnailImage(
                attachment: tsAttachment,
                info: info,
                parentMessage: parentMessage,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }
}
