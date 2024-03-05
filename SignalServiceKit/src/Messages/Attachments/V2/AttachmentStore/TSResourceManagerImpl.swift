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
                tx: tx
            )
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
        tsAttachmentManager.addBodyAttachments(legacyAttachments, to: message, tx: tx)
    }

    public func removeBodyAttachment(
        _ attachment: TSResource,
        from message: TSMessage,
        tx: DBWriteTransaction
    ) {
        switch attachment.concreteType {
        case .legacy(let legacyAttachment):
            tsAttachmentManager.removeBodyAttachment(legacyAttachment, from: message, tx: tx)
        }
    }
}
