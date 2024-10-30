//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Runs backfills to re-validate existing attachments that were validated _before_
/// some update was applied to our validation logic.
///
/// Typically the sequence of events would be something like this:
/// 1. We discover a bug in our validator (or we want to support a new file type, etc)
/// 2. We apply a fix, updating the validator's logic to handle the mishandled file type
/// 3. We add a new ``ValidationBackfill`` case which filters to the appropriate content/mime/file type
///
/// This class ensures that after step (3) we will run the backfill to re-validate all existing attachments
/// that match the filters, so that they are run through the updated validator with the fix from step (2).
///
/// Notably, we _can_ ship (3) in a release after shipping (2), but if we do it could mean we re-validate
/// attachments that were already validated with the latest validator. This is a waste of resources but
/// doesn't break anything. Typically we want to ship (2) and (3) in the same release.
public protocol AttachmentValidationBackfillMigrator {

    /// Runs another batch, returns true if all batches completed.
    /// If returns false, another batch may be needed and should be run.
    func runNextBatch() async throws -> Bool
}

internal enum ValidationBackfill: Int, CaseIterable {

    case recomputeAudioDurations = 1

    // MARK: - Migration insertion point
    // Insert new backfills here, incrementing the last raw value by 1.

    // MARK: - Properties

    /// Which content type + mime type to re-validate.
    enum ContentTypeFilter: Hashable {
        /// No content type filter; re-validate _everything_. This is very expensive
        /// and should be incredibly rare. You probably don't want this.
        case none

        /// Filter to just a content type; don't sub-filter by mime type. Other filters can be applied
        /// but typically this will take advantage of the contentType,mimeType index.
        case contentType(Attachment.ContentTypeRaw)

        /// Filter to both a content and mime type. You cannot filter to just a mime type (that doesn't
        /// really make sense, anyway, all mime types are subscoped to a content type). Takes
        /// advantage of the contentType,mimeType index.
        case mimeTypes(Attachment.ContentTypeRaw, mimeTypes: [String])
    }

    /// Filters _which_ existing attachments should be re-validated by content and optionally mime type.
    ///
    /// ~Most~ backfills should filter by a content type, and optionally by a mimeType.
    /// These specific filters are common, use an index when filtering, and are therefore specifically defined.
    var contentTypeFilter: ContentTypeFilter {
        switch self {
        case .recomputeAudioDurations:
            return .contentType(.audio)
        }
    }

    /// Other filters (that don't use the content type or mime type); less common but still supported.
    /// Only supports single column filters.
    struct Filter {
        /// What column to filter on.
        let column: Attachment.Record.CodingKeys
        /// ==, >, <, <=, >=, etc.
        let `operator`: (_ lhs: SQLSpecificExpressible, _ rhs: SQLExpressible?) -> SQLExpression
        /// The value to compare the column to
        let value: SQLExpressible
    }

    /// Filters _which_ existing attachments should be re-validated by other columns than content and mime type.
    ///
    /// Less common than content/mime type filtering, and only supports single column filtering for now.
    /// All filters, including content/mime type, are chained with AND, not or.
    var columnFilters: [Filter] {
        switch self {
        case .recomputeAudioDurations:
            return [
                .init(
                    column: .cachedAudioDurationSeconds,
                    operator: ==,
                    value: 0
                )
            ]
        }
    }
}

public class AttachmentValidationBackfillMigratorImpl: AttachmentValidationBackfillMigrator {

    private let attachmentStore: AttachmentStore
    private let databaseStorage: SDSDatabaseStorage
    private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    private let orphanedAttachmentStore: OrphanedAttachmentStore
    private let store: AttachmentValidationBackfillStore
    private let validator: AttachmentContentValidator

    public init(
        attachmentStore: AttachmentStore,
        attachmentValidationBackfillStore: AttachmentValidationBackfillStore,
        databaseStorage: SDSDatabaseStorage,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        validator: AttachmentContentValidator
    ) {
        self.attachmentStore = attachmentStore
        self.databaseStorage = databaseStorage
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
        self.orphanedAttachmentStore = orphanedAttachmentStore
        self.store = attachmentValidationBackfillStore
        self.validator = validator
    }

    // MARK: - Public

    public func runNextBatch() async throws -> Bool {
        let didEnqueue = try await enqueueForBackfillIfNeeded()
        if didEnqueue {
            return false
         }
        return try await runNextValidationBatch()
    }

    // MARK: - Private

    /// Re-validate enqueued attachments, one batch at a time.
    /// Returns true if there is nothing left to re-validate (finished).
    private func runNextValidationBatch() async throws -> Bool {
        // Pop attachments off the queue, newest first.
        let attachments: [Attachment.IDType: Attachment.Record?] = try databaseStorage.read { tx in
            let attachmentIds = try store.getNextAttachmentIdBatch(tx: tx)

            let attachments = try Attachment.Record.fetchAll(
                tx.unwrapGrdbRead.database,
                keys: attachmentIds
            )
            return attachmentIds.dictionaryMappingToValues { id in
                return attachments.first(where: { $0.sqliteId == id })
            }
        }
        if attachments.keys.isEmpty {
            return true
        }

        let startTimeMs = Date.ows_millisecondTimestamp()
        var revalidatedAttachmentIds = [(Attachment.IDType, RevalidatedAttachment)]()
        var skippedAttachmentIds = [Attachment.IDType]()
        for (attachmentId, attachment) in attachments {
            guard
                let attachment,
                let localRelativeFilePath = attachment.localRelativeFilePath,
                let plaintextLength = attachment.unencryptedByteCount
            else {
                skippedAttachmentIds.append(attachmentId)
                continue
            }
            let fileUrl = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: localRelativeFilePath)
            do {
                let revalidationResult = try await self.reValidateContents(
                    ofEncryptedFileAt: fileUrl,
                    encryptionKey: attachment.encryptionKey,
                    plaintextLength: plaintextLength,
                    mimeType: attachment.mimeType
                )
                revalidatedAttachmentIds.append((attachmentId, revalidationResult))
            } catch let error {
                Logger.error("Failed to validate; skipping \(error)")
                skippedAttachmentIds.append(attachmentId)
            }

            let nowMs = Date().ows_millisecondsSince1970
            if nowMs - startTimeMs > Constants.batchDurationMs {
                // If we take a long time, stop and commit now so we persist that expensive progress.
                break
            }
        }

        // Commit the batch.
        // 1. Remove the enqueued row (including for "skipped" ids)
        // 2. Update the content type everywhere needed to the newly validated type.
        try await databaseStorage.awaitableWrite { tx in
            try skippedAttachmentIds.forEach { try self.store.dequeue(attachmentId: $0, tx: tx) }
            try revalidatedAttachmentIds.forEach { (attachmentId, revalidatedAttachment) in
                try self.store.dequeue(attachmentId: attachmentId, tx: tx)
                try self.updateRevalidatedAttachment(
                    revalidatedAttachment,
                    id: attachmentId,
                    tx: tx.asV2Write
                )
            }
        }

        return false
    }

    private func reValidateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) async throws -> RevalidatedAttachment {
        // AttachmentValidator runs synchronously _and_ opens write transactions internally.
        // We can't block on the write lock in async funcs (they use a cooperative thread pool),
        // so bridge out of structured concurrency to run the validation.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let result = try self.validator.reValidateContents(
                        ofEncryptedFileAt: fileUrl,
                        encryptionKey: encryptionKey,
                        plaintextLength: plaintextLength,
                        mimeType: mimeType
                    )
                    continuation.resume(with: .success(result))
                } catch let error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func updateRevalidatedAttachment(
        _ revalidatedAttachment: RevalidatedAttachment,
        id: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        let hasOrphanRecord = orphanedAttachmentStore.orphanAttachmentExists(
            with: revalidatedAttachment.orphanRecordId,
            tx: tx
        )
        guard hasOrphanRecord else {
            throw OWSAssertionError("Orphan record deleted before creation")
        }

        guard let attachment = attachmentStore.fetch(id: id, tx: tx) else {
            // If the attachment got deleted, that's fine. Drop the update.
            return
        }

        // "Ancillary" files (e.g. video still frame) are regenerated on revalidation.
        // Whatever old ancillary files existed before must be orphaned.
        let oldAncillaryFilesOrphanRecord: OrphanedAttachmentRecord? = {
            switch attachment.streamInfo?.contentType {
            case nil, .invalid, .file, .image, .animatedImage:
                return nil
            case .video(_, _, let stillFrameRelativeFilePath):
                return .init(
                    localRelativeFilePath: nil,
                    localRelativeFilePathThumbnail: nil,
                    localRelativeFilePathAudioWaveform: nil,
                    localRelativeFilePathVideoStillFrame: stillFrameRelativeFilePath
                )
            case .audio(_, let waveformRelativeFilePath):
                return .init(
                    localRelativeFilePath: nil,
                    localRelativeFilePathThumbnail: nil,
                    localRelativeFilePathAudioWaveform: waveformRelativeFilePath,
                    localRelativeFilePathVideoStillFrame: nil
                )
            }
        }()

        // Update the attachment
        try attachmentStore.updateAttachment(
            attachment,
            revalidatedContentType: revalidatedAttachment.validatedContentType,
            mimeType: revalidatedAttachment.mimeType,
            blurHash: revalidatedAttachment.blurHash,
            tx: tx
        )
        // Clear out the orphan record for the _new_ ancillary files.
        orphanedAttachmentCleaner.releasePendingAttachment(
            withId: revalidatedAttachment.orphanRecordId,
            tx: tx
        )
        // Insert the orphan record for the _old_ ancillary files.
        if var oldAncillaryFilesOrphanRecord {
            try orphanedAttachmentStore.insert(&oldAncillaryFilesOrphanRecord, tx: tx)
        }
    }

    /// Walk over existing attachments and enqueue them for re-validation, if needed.
    ///
    /// We do NOT need to enqueue anything if we've already walked over all attachments for the latest known backfill;
    /// we only need to enqueue once per backfill.
    ///
    /// Returns true if anything was enqueued.
    private func enqueueForBackfillIfNeeded() async throws -> Bool {
        // Check with a cheap read if we need to do any enqueuing.
        if databaseStorage.read(block: { tx in self.store.backfillsThatNeedEnqueuing(tx: tx.asV2Read) }).isEmpty {
            return false
        }

        return try await databaseStorage.awaitableWrite { tx in
            let backfillsToEnqueue = self.store.backfillsThatNeedEnqueuing(tx: tx.asV2Read)
            if backfillsToEnqueue.isEmpty {
                return false
            }
            try self.enqueueForBackfill(backfillsToEnqueue, tx: tx)
            self.store.setLastEnqueuedBackfill(
                backfillsToEnqueue.max(by: { $0.rawValue < $1.rawValue })!,
                tx: tx.asV2Write
            )
            return true
        }
    }

    /// Given a set of backfills that have yet to have the enqueue pass, enqueues all attachments that need re-validation.
    ///
    /// Filters across all the backfills and enqueues any attachment that passes the filter of _any_ of the backfills.
    private func enqueueForBackfill(_ backfills: [ValidationBackfill], tx: SDSAnyWriteTransaction) throws {
        let contentTypeColumn = Column(Attachment.Record.CodingKeys.contentType)
        let mimeTypeColumn = Column(Attachment.Record.CodingKeys.mimeType)

        // We OR these; we enqueue any attachment that matches any backfill's filters.
        var perBackfillPredicates: [SQLSpecificExpressible] = []
        for backfill in backfills {
            // We AND these; any given backfill's filters must all match.
            var backfillPredicates = [SQLSpecificExpressible]()
            switch backfill.contentTypeFilter {
            case .none:
                Logger.warn("Backfilling without any content type filter")
            case .contentType(let contentType):
                backfillPredicates.append(contentTypeColumn == contentType.rawValue)
            case .mimeTypes(let contentType, let mimeTypes):
                backfillPredicates.append(contentTypeColumn == contentType.rawValue)
                mimeTypes.forEach { mimeType in
                    backfillPredicates.append(mimeTypeColumn == mimeType)
                }
            }

            for columnFilter in backfill.columnFilters {
                backfillPredicates.append(columnFilter.operator(Column(columnFilter.column), columnFilter.value))
            }

            // AND all predicates for this backfill.
            let backfillPredicate = backfillPredicates.joined(operator: .and)
            perBackfillPredicates.append(backfillPredicate)
        }

        let query = Attachment.Record
            // OR all the predicates across backfills.
            .filter(perBackfillPredicates.joined(operator: .or))
            .select(Column(Attachment.Record.CodingKeys.sqliteId))
        let cursor = try Int64.fetchCursor(tx.unwrapGrdbWrite.database, query)

        while let nextId = try cursor.next() {
            try self.store.enqueue(attachmentId: nextId, tx: tx)
        }
    }

    // MARK: -

    private enum Constants {
        /// Despite the batch size, once we take this long to re-validate, we commit what we have. This
        /// ensures we commit progress more aggressively for expensive files.
        static let batchDurationMs = 500
    }
}
