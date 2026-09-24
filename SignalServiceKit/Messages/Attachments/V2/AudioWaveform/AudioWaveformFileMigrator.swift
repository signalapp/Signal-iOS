//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Migrates audio waveforms that live in their own encrypted file into the
/// `Attachment` row that owns them, as serialized samples.
///
/// Iterates through every Attachment row, and for those with a non-nil
/// `audioWaveformRelativeFilePath` migrates the file's contents to
/// `audioWaveformSamples` and orphans the file so it gets cleaned up.
///
/// Iteration runs from the newest Attachment to the oldest, durably tracking
/// the last-migrated row ID so an interrupted run resumes where it left off.
public struct AudioWaveformFileMigrator {
    private typealias Columns = Attachment.Record.CodingKeys

    private let dateProvider: DateProvider
    private let db: DB
    private let logger = PrefixedLogger(prefix: "AudioWaveformFileMigrator")
    private let store: Store

    public init(
        dateProvider: @escaping DateProvider,
        db: DB,
    ) {
        self.init(dateProvider: dateProvider, db: db, store: Store())
    }

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        store: Store,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.store = store
    }

    public func needsToRun() -> Bool {
        return db.read { tx in
            // Row IDs start at 1, so 0 means we've visited every row.
            return store.lastMigratedAttachmentId(tx: tx) > 0
        }
    }

    public func run() async throws(CancellationError) {
        logger.info("Starting...")

        struct TxContext {
            var attachmentRowCursor: FailIfThrowsRecordCursor<AttachmentRow>
            var lastMigratedAttachmentId: Attachment.IDType
        }

        try await TimeGatedBatch.processAll(
            db: db,
            buildTxContext: { tx -> TxContext in
                let lastMigratedAttachmentId = store.lastMigratedAttachmentId(tx: tx)

                return TxContext(
                    attachmentRowCursor: fetchAttachmentRowCursor(
                        before: lastMigratedAttachmentId,
                        tx: tx,
                    ),
                    lastMigratedAttachmentId: lastMigratedAttachmentId,
                )
            },
            processBatch: { tx, txContext throws(CancellationError) in
                guard !Task.isCancelled else {
                    throw CancellationError()
                }

                guard
                    let attachmentRow = txContext.attachmentRowCursor.next()
                else {
                    // SQLite won't use 0 for a row ID, so we'll use 0 as a
                    // sentinel value to let future runs short-circuit.
                    txContext.lastMigratedAttachmentId = 0
                    return .done(())
                }

                if let waveformRelativeFilePath = attachmentRow.waveformRelativeFilePath {
                    migrate(
                        attachmentRow,
                        waveformRelativeFilePath: waveformRelativeFilePath,
                        tx: tx,
                    )
                }
                txContext.lastMigratedAttachmentId = attachmentRow.attachmentId
                return .more
            },
            concludeTx: { tx, txContext in
                store.setLastMigratedAttachmentId(
                    txContext.lastMigratedAttachmentId,
                    tx: tx,
                )
            },
        )

        logger.info("Done!")
    }

    // MARK: -

    struct Store {
        private enum Keys {
            static let lastMigratedAttachmentId = "lastMigratedAttachmentId"
        }

        private let kvStore = NewKeyValueStore(collection: "AudioWaveformFileMigrator")

        /// The exclusive upper bound on the Attachment row IDs left to
        /// migrate: `Attachment.IDType.max` if we haven't migrated anything
        /// yet, and `0` once we've migrated everything.
        func lastMigratedAttachmentId(tx: DBReadTransaction) -> Attachment.IDType {
            return kvStore.fetchValue(
                Attachment.IDType.self,
                forKey: Keys.lastMigratedAttachmentId,
                tx: tx,
            ) ?? .max
        }

        func setLastMigratedAttachmentId(
            _ attachmentId: Attachment.IDType,
            tx: DBWriteTransaction,
        ) {
            kvStore.writeValue(
                attachmentId,
                forKey: Keys.lastMigratedAttachmentId,
                tx: tx,
            )
        }
    }

    // MARK: -

    private struct AttachmentRow: Decodable, FetchableRecord {
        let attachmentId: Attachment.IDType
        let encryptionKey: Data
        let waveformRelativeFilePath: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Attachment.Record.CodingKeys.self)

            self.attachmentId = try container.decode(Attachment.IDType.self, forKey: .sqliteId)
            self.encryptionKey = try container.decode(Data.self, forKey: .encryptionKey)
            self.waveformRelativeFilePath = try container.decodeIfPresent(String.self, forKey: .audioWaveformRelativeFilePath)
        }
    }

    private func fetchAttachmentRowCursor(
        before lastMigratedAttachmentId: Attachment.IDType,
        tx: DBReadTransaction,
    ) -> FailIfThrowsRecordCursor<AttachmentRow> {
        let query = """
        SELECT
            \(Columns.sqliteId.rawValue),
            \(Columns.encryptionKey.rawValue),
            \(Columns.audioWaveformRelativeFilePath.rawValue)
        FROM \(Attachment.Record.databaseTableName)
        WHERE \(Columns.sqliteId.rawValue) < ?
        ORDER BY \(Columns.sqliteId.rawValue) DESC
        """

        return FailIfThrowsRecordCursor {
            return try AttachmentRow.fetchCursor(
                tx.database,
                sql: query,
                arguments: [lastMigratedAttachmentId],
            )
        }
    }

    private func migrate(
        _ attachmentRow: AttachmentRow,
        waveformRelativeFilePath: String,
        tx: DBWriteTransaction,
    ) {
        let waveformSamples = readWaveformSamples(
            encryptionKey: attachmentRow.encryptionKey,
            waveformRelativeFilePath: waveformRelativeFilePath,
        )

        failIfThrows {
            try tx.database.execute(
                sql: """
                    UPDATE \(Attachment.Record.databaseTableName)
                    SET
                        \(Columns.audioWaveformSamples.rawValue) = ?,
                        \(Columns.audioWaveformRelativeFilePath.rawValue) = NULL
                    WHERE \(Columns.sqliteId.rawValue) = ?
                """,
                arguments: [waveformSamples, attachmentRow.attachmentId],
            )
        }

        // The trigger that orphans an attachment's files only fires when the
        // attachment row is deleted, so orphan the waveform file ourselves.
        _ = OrphanedAttachmentRecord.insertRecord(
            OrphanedAttachmentRecord.InsertableRecord(
                isPendingAttachment: false,
                localRelativeFilePath: nil,
                localRelativeFilePathThumbnail: nil,
                localRelativeFilePathAudioWaveform: waveformRelativeFilePath,
                localRelativeFilePathVideoStillFrame: nil,
                timestamp: dateProvider().ows_millisecondsSince1970,
            ),
            tx: tx,
        )
    }

    private func readWaveformSamples(
        encryptionKey: Data,
        waveformRelativeFilePath: String,
    ) -> Data? {
        do {
            let attachmentKey = try AttachmentKey(combinedKey: encryptionKey)

            // The waveform was validated when it was written; no need to
            // revalidate it now.
            let archivedData = try Cryptography.decryptFileWithoutValidating(
                at: AttachmentStream.absoluteAttachmentFileURL(
                    relativeFilePath: waveformRelativeFilePath,
                ),
                metadata: DecryptionMetadata(key: attachmentKey),
            )
            return try AudioWaveform(archivedData: archivedData).waveformData
        } catch {
            logger.warn("Failed to read waveform file: \(error)")
            return nil
        }
    }
}
