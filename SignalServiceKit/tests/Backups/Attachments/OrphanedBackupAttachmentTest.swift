//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct OrphanedBackupAttachmentTest {
    @Test
    func testTriggers() throws {
        let db = InMemoryDB()

        let encryptionKey = AttachmentKey.generate()
        let plaintextHash = Randomness.generateRandomBytes(32)
        var record = Attachment.Record.forInsertingFromBackup(
            blurHash: nil,
            mimeType: "image/png",
            contentType: .image,
            encryptionKey: encryptionKey.combinedKey,
            latestTransitTierInfo: nil,
            plaintextHash: plaintextHash,
            mediaTierInfo: Attachment.MediaTierInfo(
                cdnNumber: 2,
                unencryptedByteCount: 123,
                plaintextHash: plaintextHash,
                incrementalMacInfo: nil,
                uploadEra: "initialUploadEra",
            ),
            thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo(
                cdnNumber: 5,
                uploadEra: "initialUploadEra",
            ),
        )

        try db.write { tx in
            try record.insert(tx.database)
            try record.delete(tx.database)
        }

        let orphanedAttachments = try db.read { tx in
            return try OrphanedBackupAttachment.fetchAll(tx.database)
        }

        struct OrphanedBackupAttachment2: Hashable {
            var mediaName: String?
            var cdnNumber: UInt32
            var type: Int?
        }

        let actualValues = orphanedAttachments.map {
            return OrphanedBackupAttachment2(mediaName: $0.mediaName, cdnNumber: $0.cdnNumber, type: $0.type?.rawValue)
        }
        let mediaName = (plaintextHash + encryptionKey.combinedKey).hexadecimalString
        let expectedValues = [
            OrphanedBackupAttachment2(mediaName: mediaName, cdnNumber: 2, type: OrphanedBackupAttachment.SizeType.fullsize.rawValue),
            OrphanedBackupAttachment2(mediaName: mediaName, cdnNumber: 5, type: OrphanedBackupAttachment.SizeType.thumbnail.rawValue),
        ]
        #expect(Set(actualValues) == Set(expectedValues))
    }
}
