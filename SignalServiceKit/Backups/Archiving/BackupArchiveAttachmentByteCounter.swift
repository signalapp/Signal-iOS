//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BackupArchiveAttachmentByteCounter {
    private struct BytesCounter {
        var bytes: UInt64 = 0
        var includedAttachments: Set<Attachment.IDType> = Set()
    }

    private var localBytesCounter = BytesCounter()
    private var remoteBytesCounter = BytesCounter()

    func addToRemoteByteCount(attachmentID: Attachment.IDType, byteCount: UInt64) {
        if remoteBytesCounter.includedAttachments.insert(attachmentID).inserted {
            remoteBytesCounter.bytes += byteCount
        }
    }

    func addToLocalByteCount(attachmentID: Attachment.IDType, byteCount: UInt64) {
        if localBytesCounter.includedAttachments.insert(attachmentID).inserted {
            localBytesCounter.bytes += byteCount
        }
    }

    func remoteAttachmentByteSize() -> UInt64 {
        remoteBytesCounter.bytes
    }

    func localAttachmentByteSize() -> UInt64 {
        localBytesCounter.bytes
    }
}
