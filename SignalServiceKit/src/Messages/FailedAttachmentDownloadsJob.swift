//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class FailedAttachmentDownloadsJob {
    /// Used for logging the total number of attachments modified
    private var count: UInt = 0
    public init() {}

    public func runSync(databaseStorage: SDSDatabaseStorage) {
        databaseStorage.write { writeTx in
            AttachmentFinder.unfailedAttachmentPointerIds(transaction: writeTx).forEach { attachmentId in
                // Since we can't directly mutate the enumerated attachments, we store only their ids in hopes
                // of saving a little memory and then enumerate the (larger) TSAttachment objects one at a time.
                autoreleasepool {
                    updateAttachmentPointerIfNecessary(attachmentId, transaction: writeTx)
                }
            }
        }
        Logger.info("Finished job. Marked \(count) in-progress attachments as failed")
    }

    private func updateAttachmentPointerIfNecessary(
        _ uniqueId: String,
        transaction writeTx: SDSAnyWriteTransaction
    ) {
        // Preconditions: Must be a valid attachment pointer that hasn't failed
        guard let attachment = TSAttachmentPointer.anyFetchAttachmentPointer(
            uniqueId: uniqueId,
            transaction: writeTx
        ) else {
            owsFailDebug("Missing attachment with id: \(uniqueId)")
            return
        }

        switch attachment.state {
        case .enqueued, .downloading:
            attachment.updateAttachmentPointerState(.failed, transaction: writeTx)
            count += 1

            switch count {
            case ...3:
                Logger.info("marked attachment pointer as failed: \(attachment.uniqueId)")
            case 4:
                Logger.info("eliding logs for further attachment pointers. final count will be reported once complete.")
            default:
                break
            }
        case .pendingMessageRequest:
            // Do nothing. We don't want to mark this attachment as failed.
            // It will be updated when the message request is resolved.
            break
        case .pendingManualDownload:
            // Do nothing. We don't want to mark this attachment as failed.
            break
        case .failed:
            // This should not have been returned from `unfailedAttachmentPointerIds`
            owsFailDebug("Attachment has unexpected state \(attachment.uniqueId).")
        }
    }
}
