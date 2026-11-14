//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

class BackupArchiveFavoriteStickerArchiver {
    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult
    typealias ArchiveFrameError = BackupArchive.ArchiveFrameError
    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult

    private let stickerManager: StickerManager

    init(stickerManager: StickerManager) {
        self.stickerManager = stickerManager
    }

    // MARK: -

    func archiveFavoriteStickers(
        stream: BackupArchiveOutputStream,
        context: BackupArchive.ArchivingContext,
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var favoriteStickerProtos = [BackupProto_FavoriteStickerList.FavoriteSticker]()
        try stickerManager.enumerateAllStickerFavorites(tx: context.tx) { favoriteSticker throws(CancellationError) -> Bool in
            if Task.isCancelled {
                throw CancellationError()
            }

            guard let favoritedAt = favoriteSticker.favoritedAt else {
                return true
            }
            guard let packKey = favoriteSticker.packKey else {
                owsFailDebug("Favorited sticker should always have packKey")
                return true
            }

            var favoriteStickerProto = BackupProto_FavoriteStickerList.FavoriteSticker()
            favoriteStickerProto.packID = favoriteSticker.packId
            favoriteStickerProto.packKey = packKey
            favoriteStickerProto.stickerID = favoriteSticker.stickerId
            favoriteStickerProto.favoritedAtTimestamp = UInt64(clamping: favoritedAt)
            favoriteStickerProtos.append(favoriteStickerProto)
            return true
        }

        guard !favoriteStickerProtos.isEmpty else {
            return .success
        }

        let error: ArchiveFrameError? = context.processFrame { frameBencher in
            context.writeFrame(
                toStream: stream,
                flush: nil,
                frameBencher: frameBencher,
            ) {
                var favoriteStickerList = BackupProto_FavoriteStickerList()
                favoriteStickerList.favoriteSticker = favoriteStickerProtos

                var frame = BackupProto_Frame()
                frame.item = .favoriteStickerList(favoriteStickerList)
                return frame
            }
        }

        if let error {
            return .partialSuccess([error])
        }

        return .success
    }

    // MARK: -

    // Only favorited stickers are included in Backups, so all records should have a packKey.
    func restore(
        _ favoriteStickers: BackupProto_FavoriteStickerList,
        context: BackupArchive.RestoringContext,
    ) -> RestoreFrameResult {
        var partialErrors = [BackupArchive.RestoreFrameError]()

        for favoriteSticker in favoriteStickers.favoriteSticker {
            guard !favoriteSticker.packID.isEmpty, !favoriteSticker.packKey.isEmpty else {
                partialErrors.append(
                    .restoreFrameError(
                        .invalidProtoData(
                            .invalidFavoriteStickerPackInfo,
                        ),
                    ),
                )
                continue
            }

            // Passing nil for existingRecord means we will always overwrite
            // an earlier favorited record with the latest one. In practice though,
            // each favorited sticker should only be archived & restored once.
            stickerManager.addFavoritesStickerPlaceholder(
                stickerInfo: StickerInfo(
                    packId: favoriteSticker.packID,
                    packKey: favoriteSticker.packKey,
                    stickerId: favoriteSticker.stickerID,
                ),
                favoritedAtTimestamp: favoriteSticker.favoritedAtTimestamp,
                existingRecord: nil,
                tx: context.tx,
            )
        }

        if !partialErrors.isEmpty {
            return .partialRestore(partialErrors)
        }

        return .success
    }
}
