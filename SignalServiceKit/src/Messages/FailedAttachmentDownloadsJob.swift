//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public class FailedAttachmentDownloadsJob {
    public init() {}

    public func runSync(databaseStorage: SDSDatabaseStorage) {
        databaseStorage.write { tx in
            let attachmentIds = AttachmentFinder.attachmentPointerIdsToMarkAsFailed(tx: tx)
            attachmentIds.forEach { attachmentId in
                // Since we can't directly mutate the enumerated attachments, we store only
                // their ids in hopes of saving a little memory and then enumerate the
                // (larger) TSAttachment objects one at a time.
                autoreleasepool {
                    updateAttachmentPointerIfNecessary(attachmentId, tx: tx)
                }
            }
            Logger.info("Finished job. Marked \(attachmentIds.count) in-progress attachments as failed.")
        }
    }

    private func updateAttachmentPointerIfNecessary(_ uniqueId: String, tx: SDSAnyWriteTransaction) {
        // Preconditions: Must be a valid attachment pointer that hasn't failed
        guard let attachment = TSAttachmentPointer.anyFetchAttachmentPointer(uniqueId: uniqueId, transaction: tx) else {
            owsFailDebug("Missing attachment with id: \(uniqueId)")
            return
        }

        // The query we perform should *exactly* match the cases handled in the
        // first branch. If you add a new `TSAttachmentPointerState` that needs to
        // be marked as failed, make sure you also update
        // `attachmentPointerIdsToMarkAsFailed`.
        switch attachment.state {
        case .enqueued, .downloading:
            attachment.updateAttachmentPointerState(.failed, transaction: tx)
            return

        case .pendingMessageRequest:
            // Do nothing. We don't want to mark this attachment as failed.
            // It will be updated when the message request is resolved.
            break
        case .pendingManualDownload:
            // Do nothing. We don't want to mark this attachment as failed.
            break
        case .failed:
            break
        }
        // If we reach this point, the query returned something unexpected.
        owsFailDebug("Attachment has unexpected state \(attachment.uniqueId).")
    }
}
