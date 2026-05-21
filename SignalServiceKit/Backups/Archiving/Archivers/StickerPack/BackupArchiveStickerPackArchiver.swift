//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public extension BackupArchive {
    /// An identifier for a ``BackupProto_StickerPack`` backup frame.
    struct StickerPackId {
        let value: Data

        init(_ value: Data) {
            self.value = value
        }
    }
}

// MARK: -

public class BackupArchiveStickerPackArchiver: BackupArchiveProtoStreamWriter {
    typealias StickerPackId = BackupArchive.StickerPackId
    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult
    typealias ArchiveFrameError = BackupArchive.ArchiveFrameError
    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult

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

        // Iterate over installed sticker packs...
        try context.bencher.wrapEnumeration(
            tx: context.tx,
            enumerationBlock: { tx, block throws(CancellationError) in
                var cursor = FailIfThrowsRecordCursor {
                    try StickerPackRecord
                        .filter(Column(StickerPackRecord.CodingKeys.isInstalled) == true)
                        .fetchCursor(tx.database)
                }

                while let stickerPack = cursor.next(), try block(stickerPack) {}
            },
            perEnumerantBlock: { installedStickerPack, frameBencher -> Bool in
                if handledPacks.contains(installedStickerPack.packId) {
                    return true
                }

                let maybeError: ArchiveFrameError? = Self.writeFrameToStream(
                    stream,
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

                return true
            },
        )

        // Iterate over any restored sticker packs that have yet to be downloaded via StickerManager.
        try context.bencher.wrapEnumeration(
            tx: context.tx,
            enumerationBlock: { tx, block throws(CancellationError) in
                try backupStickerPackDownloadStore.iterateAllEnqueued(tx: tx, block: block)
            },
            perEnumerantBlock: { record, frameBencher -> Bool in
                if handledPacks.contains(record.packId) {
                    return true
                }

                let maybeError: ArchiveFrameError? = Self.writeFrameToStream(
                    stream,
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

                return true
            },
        )

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
        backupStickerPackDownloadStore.enqueue(
            packId: stickerPack.packID,
            packKey: stickerPack.packKey,
            tx: context.tx,
        )
        return .success
    }
}
