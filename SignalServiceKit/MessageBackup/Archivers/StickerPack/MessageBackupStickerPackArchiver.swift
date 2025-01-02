//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public extension MessageBackup {
    /// An identifier for a ``BackupProto_StickerPack`` backup frame.
    struct StickerPackId: MessageBackupLoggableId {
        let value: Data

        init(_ value: Data) {
            self.value = value
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto_StickPack" }
        public var idLogString: String {
            /// Since sticker pack IDs are a cross-client identifier, we don't
            /// want to log them directly.
            return "\(value.hashValue)"
        }
    }
}

public protocol MessageBackupStickerPackArchiver: MessageBackupProtoArchiver {

    typealias StickerPackId = MessageBackup.StickerPackId

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<StickerPackId>

    typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<StickerPackId>

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<StickerPackId>

    /// Archive all ``StickerPack``s (they map to ``BackupProto_StickerPack``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveStickerPacks(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ArchivingContext
    ) throws(CancellationError) -> ArchiveMultiFrameResult

    /// Restore a single ``BackupProto_StickerPack`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if the frame was restored without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ stickerPack: BackupProto_StickerPack,
        context: MessageBackup.RestoringContext
    ) -> RestoreFrameResult

}

public class MessageBackupStickerPackArchiverImpl: MessageBackupStickerPackArchiver {

    private let backupStickerPackDownloadStore: BackupStickerPackDownloadStore

    init(
        backupStickerPackDownloadStore: BackupStickerPackDownloadStore
    ) {
        self.backupStickerPackDownloadStore = backupStickerPackDownloadStore
    }

    public func archiveStickerPacks(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ArchivingContext
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        var handledPacks = Set<Data>()

        func archiveInstalledStickerPack(_ installedStickerPack: StickerPack) {
            autoreleasepool {
                guard !handledPacks.contains(installedStickerPack.packId) else { return }
                let maybeError: ArchiveFrameError? = Self.writeFrameToStream(
                    stream,
                    objectId: StickerPackId(installedStickerPack.packId)) {
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

        // Iterate over the installed sticker packs
        do {
            let cursor = try StickerPackRecord
                .filter(Column(StickerPackRecord.CodingKeys.isInstalled) == true)
                .fetchCursor(context.tx.databaseConnection)
            while let next = try cursor.next() {
                try Task.checkCancellation()
                let stickerPack = try StickerPack.fromRecord(next)
                archiveInstalledStickerPack(stickerPack)
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            return .completeFailure(.fatalArchiveError(.stickerPackIteratorError(error)))
        }

        // Iterate over any restored sticker packs that have yet to be downloaded via StickerManager.
        do {
            try backupStickerPackDownloadStore.iterateAllEnqueued(tx: context.tx) { record in
                try Task.checkCancellation()
                autoreleasepool {
                    guard !handledPacks.contains(record.packId) else { return }
                    let maybeError: ArchiveFrameError? = Self.writeFrameToStream(
                        stream,
                        objectId: StickerPackId(record.packId)) {
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

    public func restore(
        _ stickerPack: BackupProto_StickerPack,
        context: MessageBackup.RestoringContext
    ) -> RestoreFrameResult {
        do {
            try backupStickerPackDownloadStore.enqueue(
                packId: stickerPack.packID,
                packKey: stickerPack.packKey,
                tx: context.tx
            )
        } catch {
            return .failure([.restoreFrameError(.databaseInsertionFailed(error), StickerPackId(stickerPack.packID))])
        }
        return .success
    }

}
