//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceManagerImpl: TSResourceManager {

    private let attachmentManager: AttachmentManagerImpl
    private let tsAttachmentManager: TSAttachmentManager

    public init(attachmentManager: AttachmentManagerImpl) {
        self.attachmentManager = attachmentManager
        self.tsAttachmentManager = TSAttachmentManager()
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
            // TODO: move this into this class
            let thumbnailAttachmentId = message.quotedMessage?.fetchThumbnailAttachmentId(
                forParentMessage: message,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        {
            Logger.verbose("Removing quoted reply attachment.")
            tsAttachmentManager.removeAttachment(attachmentId: thumbnailAttachmentId, tx: SDSDB.shimOnlyBridge(tx))
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
}
