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

    // MARK: - Message attachment writes

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
}
