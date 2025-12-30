//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public extension BackupArchive {
    /// An identifier for a ``BackupProto_StickerPack`` backup frame.
    struct StickerPackId: BackupArchive.LoggableId {
        let value: Data

        init(_ value: Data) {
            self.value = value
        }

        // MARK: BackupArchive.LoggableId

        public var typeLogString: String { "BackupProto_StickPack" }
        public var idLogString: String {
            /// Since sticker pack IDs are a cross-client identifier, we don't
            /// want to log them directly.
            return "\(value.hashValue)"
        }
    }
}

// MARK: -

public class BackupArchiveStickerPackArchiver: BackupArchiveProtoStreamWriter {
    typealias StickerPackId = BackupArchive.StickerPackId
    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult<StickerPackId>
    typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<StickerPackId>
    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult<StickerPackId>

    private let backupStickerPackDownloadStore: BackupStickerPackDownloadStore

    init(
        backupStickerPackDownloadStore: BackupStickerPackDownloadStore,
    ) {
        self.backupStickerPackDownloadStore = backupStickerPackDownloadStore
    }

    // MARK: -

    /// Archive all ``StickerPack``s (they map to ``BackupProto_StickerPack``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveStickerPacks(
        stream: BackupArchiveProtoOutputStream,
        context: BackupArchive.ArchivingContext,
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        var handledPacks = Set<Data>()

        func archiveInstalledStickerPack(
            _ installedStickerPack: StickerPack,
            _ frameBencher: BackupArchive.Bencher.FrameBencher,
        ) {
            autoreleasepool {
                guard !handledPacks.contains(installedStickerPack.packId) else { return }
                let maybeError: ArchiveFrameError? = Self.writeFrameToStream(
                    stream,
                    objectId: StickerPackId(installedStickerPack.packId),
                    frameBencher: frameBencher,
                ) {
                    var stickerPack = BackupProto_StickerPack()
                    stickerPack.packID = installedStickerPack.packId
                    stickerPack.packKey = installedStickerPack.packKey

                    var frame = BackupProto_Frame()
                    frame.item = .stickerPack(stickerPack)

                    return frame
                }

                if let maybeError {
                    errors.append(maybeError)
                } else {
                    handledPacks.insert(installedStickerPack.packId)
                }
            }
        }

        func enumerateStickerPackRecord(tx: DBReadTransaction, block: (StickerPack) throws -> Void) throws {
            let cursor = try StickerPackRecord
                .filter(Column(StickerPackRecord.CodingKeys.isInstalled) == true)
                .fetchCursor(tx.database)
            while let next = try cursor.next() {
                let stickerPack = try StickerPack.fromRecord(next)
                try block(stickerPack)
            }
        }

        // Iterate over the installed sticker packs
        do {
            try context.bencher.wrapEnumeration(
                enumerateStickerPackRecord(tx:block:),
                tx: context.tx,
            ) { stickerPack, frameBencher in
                try Task.checkCancellation()
                archiveInstalledStickerPack(stickerPack, frameBencher)
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            return .completeFailure(.fatalArchiveError(.stickerPackIteratorError(error)))
        }

        // Iterate over any restored sticker packs that have yet to be downloaded via StickerManager.
        do {
            try context.bencher.wrapEnumeration(
                backupStickerPackDownloadStore.iterateAllEnqueued(tx:block:),
                tx: context.tx,
            ) { record, frameBencher in
                try Task.checkCancellation()
                autoreleasepool {
                    guard !handledPacks.contains(record.packId) else { return }
                    let maybeError: ArchiveFrameError? = Self.writeFrameToStream(
                        stream,
                        objectId: StickerPackId(record.packId),
                        frameBencher: frameBencher,
                    ) {
                        var stickerPack = BackupProto_StickerPack()
                        stickerPack.packID = record.packId
                        stickerPack.packKey = record.packKey

                        var frame = BackupProto_Frame()
                        frame.item = .stickerPack(stickerPack)

                        return frame
                    }
                    if let maybeError {
                        errors.append(maybeError)
                    } else {
                        handledPacks.insert(record.packId)
                    }
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            return .completeFailure(.fatalArchiveError(.stickerPackIteratorError(error)))
        }

        if errors.count > 0 {
            return .partialSuccess(errors)
        } else {
            return .success
        }
    }

    // MARK: -

    /// Restore a single ``BackupProto_StickerPack`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if the frame was restored without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ stickerPack: BackupProto_StickerPack,
        context: BackupArchive.RestoringContext,
    ) -> RestoreFrameResult {
        do {
            try backupStickerPackDownloadStore.enqueue(
                packId: stickerPack.packID,
                packKey: stickerPack.packKey,
                tx: context.tx,
            )
        } catch {
            return .failure([.restoreFrameError(.databaseInsertionFailed(error), StickerPackId(stickerPack.packID))])
        }
        return .success
    }
}
