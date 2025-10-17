//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BackupArchiveAttachmentByteCounter {
    private var bytesCounter: UInt64 = 0
    private var includedAttachmentsInByteCount: Set<Attachment.IDType> = Set()

    func addToByteCount(attachmentID: Attachment.IDType, byteCount: UInt64) {
        if includedAttachmentsInByteCount.insert(attachmentID).inserted {
            bytesCounter += byteCount
        }
    }

    func attachmentByteSize() -> UInt64 {
        bytesCounter
    }
}
