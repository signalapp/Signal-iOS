//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import Testing

@testable import SignalServiceKit

@MainActor
struct AudioWaveformFileMigratorTest {

    private let db = InMemoryDB()
    private let attachmentStore = AttachmentStore()
    private let migrator: AudioWaveformFileMigrator
    private let store = AudioWaveformFileMigrator.Store()

    init() {
        migrator = AudioWaveformFileMigrator(
            dateProvider: { Date() },
            db: db,
            store: store,
        )
    }

    @Test
    func needsToRunUntilRun() async throws {
        #expect(migrator.needsToRun())

        try await migrator.run()

        #expect(!migrator.needsToRun())
    }

    /// Doesn't matter that the waveform files themselves don't exist; the
    /// migrator will skip them with a warning.
    @Test
    func migratingDrainsEveryWaveformFile() async throws {
        let waveformRelativeFilePaths = [UUID().uuidString, UUID().uuidString]
        let attachmentIds = try waveformRelativeFilePaths.map {
            try insertAudioAttachment(waveformRelativeFilePath: $0)
        }

        try await migrator.run()

        for attachmentId in attachmentIds {
            let audioDetails = try #require(fetchAudioDetails(attachmentId: attachmentId))
            #expect(audioDetails.duration == 12.5)
            #expect(audioDetails.waveform == nil)
            #expect(audioDetails.waveformRelativeFilePath == nil)
        }
        #expect(orphanedWaveformFilePaths().sorted() == waveformRelativeFilePaths.sorted())
        #expect(!migrator.needsToRun())
    }

    @Test
    func migratingSkipsAttachmentsWithoutWaveformFiles() async throws {
        let waveformRelativeFilePaths = [UUID().uuidString, UUID().uuidString]

        // Interleave attachments with and without waveform files.
        let waveformAttachmentId1 = try insertAudioAttachment(waveformRelativeFilePath: waveformRelativeFilePaths[0])
        let imageAttachmentId1 = try insertImageAttachment()
        let audioAttachmentId = try insertAudioAttachment(waveformRelativeFilePath: nil)
        let imageAttachmentId2 = try insertImageAttachment()
        let waveformAttachmentId2 = try insertAudioAttachment(waveformRelativeFilePath: waveformRelativeFilePaths[1])

        try await migrator.run()

        for attachmentId in [waveformAttachmentId1, audioAttachmentId, waveformAttachmentId2] {
            let audioDetails = try #require(fetchAudioDetails(attachmentId: attachmentId))
            #expect(audioDetails.duration == 12.5)
            #expect(audioDetails.waveformRelativeFilePath == nil)
        }
        for attachmentId in [imageAttachmentId1, imageAttachmentId2] {
            #expect(fetchAttachment(attachmentId: attachmentId) != nil)
            #expect(fetchAudioDetails(attachmentId: attachmentId) == nil)
        }
        #expect(orphanedWaveformFilePaths().sorted() == waveformRelativeFilePaths.sorted())
        #expect(lastMigratedAttachmentId() == 0)
    }

    @Test
    func migratingIsIdempotent() async throws {
        _ = try insertAudioAttachment(waveformRelativeFilePath: UUID().uuidString)

        try await migrator.run()
        try await migrator.run()

        #expect(orphanedWaveformFilePaths().count == 1)
    }

    @Test
    func migratingResumesFromLastMigratedAttachmentId() async throws {
        let waveformRelativeFilePaths = [UUID().uuidString, UUID().uuidString, UUID().uuidString]
        let attachmentIds = try waveformRelativeFilePaths.map {
            try insertAudioAttachment(waveformRelativeFilePath: $0)
        }
        setLastMigratedAttachmentId(attachmentIds[1])

        try await migrator.run()

        // Only the attachment older than the persisted row ID is migrated;
        // the newer ones were "already migrated" as far as we know.
        #expect(fetchAudioDetails(attachmentId: attachmentIds[0])?.waveformRelativeFilePath == nil)
        #expect(fetchAudioDetails(attachmentId: attachmentIds[1])?.waveformRelativeFilePath == waveformRelativeFilePaths[1])
        #expect(fetchAudioDetails(attachmentId: attachmentIds[2])?.waveformRelativeFilePath == waveformRelativeFilePaths[2])
        #expect(orphanedWaveformFilePaths() == [waveformRelativeFilePaths[0]])
        #expect(lastMigratedAttachmentId() == 0)
    }

    @Test
    func migratingShortCircuitsOnceFinished() async throws {
        _ = try insertAudioAttachment(waveformRelativeFilePath: UUID().uuidString)

        try await migrator.run()

        #expect(lastMigratedAttachmentId() == 0)
        #expect(!migrator.needsToRun())

        // Newly-inserted waveform files (which shouldn't happen) don't
        // resurrect the migration.
        let waveformRelativeFilePath = UUID().uuidString
        let attachmentId = try insertAudioAttachment(waveformRelativeFilePath: waveformRelativeFilePath)

        #expect(!migrator.needsToRun())

        try await migrator.run()

        #expect(fetchAudioDetails(attachmentId: attachmentId)?.waveformRelativeFilePath == waveformRelativeFilePath)
        #expect(orphanedWaveformFilePaths().count == 1)
    }

    @Test
    func migratingLeavesOtherAttachmentsAlone() async throws {
        let attachmentId = try insertAudioAttachment(waveformRelativeFilePath: nil)

        try await migrator.run()

        let audioDetails = try #require(fetchAudioDetails(attachmentId: attachmentId))
        #expect(audioDetails.duration == 12.5)
        #expect(orphanedWaveformFilePaths().isEmpty)
    }

    // MARK: -

    private func insertAudioAttachment(
        waveformRelativeFilePath: String?,
    ) throws -> Attachment.IDType {
        return try insertAttachment(Attachment.Record.mockStream(
            mimeType: "audio/mp4",
            audioDetails: Attachment.AudioDetails(
                duration: 12.5,
                waveform: nil,
                waveformRelativeFilePath: waveformRelativeFilePath,
            ),
        ))
    }

    private func insertImageAttachment() throws -> Attachment.IDType {
        return try insertAttachment(Attachment.Record.mockStream(
            mimeType: MimeType.imageJpeg.rawValue,
            audioDetails: nil,
        ))
    }

    private func insertAttachment(
        _ attachmentParams: Attachment.Record,
    ) throws -> Attachment.IDType {
        let (threadRowId, messageRowId) = insertThreadAndInteraction()

        var attachmentParams = attachmentParams
        let referenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
            attachmentRecord: attachmentParams,
            messageRowId: messageRowId,
            threadRowId: threadRowId,
        )

        return try db.write { tx in
            try attachmentStore.insert(
                &attachmentParams,
                reference: referenceParams,
                tx: tx,
            ).id
        }
    }

    private func insertThreadAndInteraction() -> (threadRowId: Int64, interactionRowId: Int64) {
        return db.write { tx in
            let thread = TSThread(uniqueId: UUID().uuidString)
            try! thread.insert(tx.database)

            let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
            try! interaction.asRecord().insert(tx.database)

            return (thread.sqliteRowId!, interaction.sqliteRowId!)
        }
    }

    private func fetchAttachment(attachmentId: Attachment.IDType) -> Attachment? {
        return db.read { tx in
            attachmentStore.fetch(ids: [attachmentId], tx: tx).first
        }
    }

    private func fetchAudioDetails(attachmentId: Attachment.IDType) -> Attachment.AudioDetails? {
        return fetchAttachment(attachmentId: attachmentId)?.audioDetails
    }

    private func lastMigratedAttachmentId() -> Attachment.IDType {
        return db.read { tx in
            store.lastMigratedAttachmentId(tx: tx)
        }
    }

    private func setLastMigratedAttachmentId(_ attachmentId: Attachment.IDType) {
        db.write { tx in
            store.setLastMigratedAttachmentId(attachmentId, tx: tx)
        }
    }

    private func orphanedWaveformFilePaths() -> [String] {
        return db.read { tx in
            return try! String.fetchAll(
                tx.database,
                sql: """
                    SELECT \(OrphanedAttachmentRecord.CodingKeys.localRelativeFilePathAudioWaveform.rawValue)
                    FROM \(OrphanedAttachmentRecord.databaseTableName)
                    WHERE \(OrphanedAttachmentRecord.CodingKeys.localRelativeFilePathAudioWaveform.rawValue) IS NOT NULL
                """,
            )
        }
    }
}
