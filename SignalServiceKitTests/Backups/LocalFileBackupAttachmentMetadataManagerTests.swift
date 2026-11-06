//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import Testing
@testable import SignalServiceKit

struct LocalFileBackupAttachmentMetadataManagerTests {
    private let db = InMemoryDB()
    private let metadataManager: LocalFileBackupAttachmentMetadataManager

    init() {
        self.metadataManager = LocalFileBackupAttachmentMetadataManager(
            attachmentStore: AttachmentStore(),
            db: db,
            metadataStore: LocalFileBackupAttachmentMetadataStore(),
        )
    }

    @Test
    func testEnsureMetadataExists() async throws {
        let mockAttachment = AttachmentStream.mock(
            streamInfo: .mock(
                encryptedByteCount: 20,
                unencryptedByteCount: 32,
            ),
        ).attachment

        let id = db.write { tx in
            LocalFileBackupTestSupport.insertMockAttachment(mockAttachment, tx: tx)
        }

        try await metadataManager.ensureAttachmentMetadataExists(progressSink: nil)

        let metadata = try db.read { tx in
            try BackupLocalFileAttachmentMetadataRecord
                .filter(
                    Column(BackupLocalFileAttachmentMetadataRecord.CodingKeys.attachmentRowId) == id,
                )
                .fetchOne(tx.database)
        }

        #expect(metadata != nil)
    }
}
