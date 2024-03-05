//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceManagerImpl: TSResourceManager {

    private let tsAttachmentManager: TSAttachmentManager

    public init() {
        self.tsAttachmentManager = TSAttachmentManager()
    }

    // MARK: - Message attachment writes

    public func createBodyAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        message: TSMessage,
        tx: DBWriteTransaction
    ) {
        if FeatureFlags.newAttachmentsUseV2 {
            fatalError("Not ready to create v2 attachments!")
        } else {
            tsAttachmentManager.createBodyAttachmentPointers(
                from: protos,
                message: message,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }

    public func createAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        message: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) throws {
        if FeatureFlags.newAttachmentsUseV2 {
            fatalError("Not ready to create v2 attachments!")
        } else {
            try tsAttachmentManager.createAttachmentStreams(
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
        }
    }
}
