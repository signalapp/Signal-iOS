//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public class StickerFavoriteStore {
    func addStickerToFavorites(
        stickerInfo: StickerInfo,
        contentType: String?,
        emojiString: String?,
        localKey: Data?,
        plaintextLength: UInt32?,
        favoritedAtTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try FavoriteStickerRecord.favoriteSticker(
                info: stickerInfo,
                contentType: contentType,
                emojiString: emojiString,
                localKey: localKey,
                plaintextLength: plaintextLength,
                favoritedAt: favoritedAtTimestamp,
                tx: tx,
            )
        }
    }

    func updateDownloadedStickerRecord(
        stickerInfo: StickerInfo,
        contentType: String?,
        emojiString: String?,
        localKey: Data,
        plaintextLength: UInt32,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try FavoriteStickerRecord
                .filter(packId: stickerInfo.packId, stickerId: stickerInfo.stickerId, currentFavoritesOnly: true)
                .updateAll(
                    tx.database,
                    [
                        Column(FavoriteStickerRecord.CodingKeys.localKey).set(to: localKey),
                        Column(FavoriteStickerRecord.CodingKeys.plaintextLength).set(to: plaintextLength),
                        Column(FavoriteStickerRecord.CodingKeys.contentType).set(to: contentType),
                        Column(FavoriteStickerRecord.CodingKeys.emojiString).set(to: emojiString),
                    ],
                )
        }
    }

    func isFavoritedSticker(
        stickerInfo: StickerInfo,
        tx: DBReadTransaction,
    ) -> Bool {
        return failIfThrows {
            try !FavoriteStickerRecord
                .filter(packId: stickerInfo.packId, stickerId: stickerInfo.stickerId, currentFavoritesOnly: true)
                .isEmpty(tx.database)
        }
    }

    func fetchFavoriteSticker(
        packId: Data,
        stickerId: UInt32,
        tx: DBReadTransaction,
    ) -> FavoriteStickerRecord? {
        return failIfThrows {
            try FavoriteStickerRecord
                .filter(
                    packId: packId,
                    stickerId: stickerId,
                    currentFavoritesOnly: true,
                ).fetchOne(tx.database)
        }
    }

    func fetchRecord(
        packId: Data,
        stickerId: UInt32,
        tx: DBReadTransaction,
    ) -> FavoriteStickerRecord? {
        return failIfThrows {
            try FavoriteStickerRecord
                .filter(
                    Column(FavoriteStickerRecord.CodingKeys.packId) == packId
                        && Column(FavoriteStickerRecord.CodingKeys.stickerId) == stickerId,
                ).fetchOne(tx.database)
        }
    }

    /// If a sticker is favorited, this nils out favoritedAt and sets unfavoritedAt.
    /// If a sticker is already unfavorited, this sets the unfavoritedAt timestamp to the new timestamp.
    /// If an existing sticker record does not exist, this adds a new unfavorited record.
    func removeStickerFromFavoritesOrUpdateUnfavoritedAt(
        packId: Data,
        stickerId: UInt32,
        unfavoritedAtTimestamp: Int64,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try FavoriteStickerRecord.unfavoriteSticker(
                packId: packId,
                stickerId: stickerId,
                unfavoritedAt: unfavoritedAtTimestamp,
                tx: tx,
            )
        }
    }

    func stickerFavoriteCount(tx: DBReadTransaction) -> Int {
        return failIfThrows {
            return try FavoriteStickerRecord
                .filter(Column(FavoriteStickerRecord.CodingKeys.favoritedAt) != nil)
                .fetchCount(tx.database)
        }
    }

    func downloadedFavoritedStickers(tx: DBReadTransaction) -> [FavoriteStickerRecord] {
        return failIfThrows {
            return try FavoriteStickerRecord
                .filter(Column(FavoriteStickerRecord.CodingKeys.favoritedAt) != nil)
                .filter(Column(FavoriteStickerRecord.CodingKeys.localKey) != nil)
                .filter(Column(FavoriteStickerRecord.CodingKeys.plaintextLength) != nil)
                .order(Column(FavoriteStickerRecord.CodingKeys.favoritedAt).desc)
                .fetchAll(tx.database)
        }
    }

    func favoritedAndUnfavoritedStickers(tx: DBReadTransaction) -> [FavoriteStickerRecord] {
        return failIfThrows {
            return try FavoriteStickerRecord.fetchAll(tx.database)
        }
    }

    func undownloadedFavoritedStickers(tx: DBReadTransaction) -> [FavoriteStickerRecord] {
        return failIfThrows {
            return try FavoriteStickerRecord
                .filter(
                    Column(FavoriteStickerRecord.CodingKeys.favoritedAt) != nil
                        && (
                            Column(FavoriteStickerRecord.CodingKeys.localKey) == nil
                                || Column(FavoriteStickerRecord.CodingKeys.plaintextLength) == nil
                        ),
                )
                .fetchAll(tx.database)
        }
    }

    func enumerateAllStickerFavorites(
        tx: DBReadTransaction,
        block: (FavoriteStickerRecord) throws(CancellationError) -> Bool,
    ) throws(CancellationError) {
        var cursor = FailIfThrowsRecordCursor {
            return try FavoriteStickerRecord
                .filter(Column(FavoriteStickerRecord.CodingKeys.favoritedAt) != nil)
                .fetchCursor(tx.database)
        }

        while let stickerFavorite = cursor.next(), try block(stickerFavorite) {}
    }

    // MARK: - Expiration of unfavorited stickers

    func oldestUnfavoritedSticker(tx: DBReadTransaction) -> FavoriteStickerRecord? {
        return failIfThrows {
            return try FavoriteStickerRecord
                .filter(Column(FavoriteStickerRecord.CodingKeys.unfavoritedAt) != nil)
                .order(Column(FavoriteStickerRecord.CodingKeys.unfavoritedAt).asc)
                .fetchOne(tx.database)
        }
    }

    /// Returns true if the row was deleted, or false if its missing, or unfavoritedAt is nil, indicating its been re-favorited.
    func deleteUnfavoritedSticker(_ record: FavoriteStickerRecord, tx: DBWriteTransaction) -> Bool {
        return failIfThrows {
            return try FavoriteStickerRecord
                .filter(Column(FavoriteStickerRecord.CodingKeys.id) == record.id)
                .filter(Column(FavoriteStickerRecord.CodingKeys.unfavoritedAt) != nil)
                .deleteAll(tx.database) > 0
        }
    }

    func unfavoriteNewestOverStickerLimit(
        unfavoritedAt: Int64,
        tx: DBWriteTransaction,
    ) -> [FavoriteStickerRecord] {
        let favoriteCount = stickerFavoriteCount(tx: tx)
        let stickersToDelete = favoriteCount - StickerManager.maxStickerFavorites
        guard stickersToDelete > 0 else {
            return []
        }

        return failIfThrows {
            let newestFavorites = try FavoriteStickerRecord
                .filter(Column(FavoriteStickerRecord.CodingKeys.favoritedAt) != nil)
                .order(
                    Column(FavoriteStickerRecord.CodingKeys.favoritedAt).desc,
                    Column(FavoriteStickerRecord.CodingKeys.id).desc,
                )
                .limit(stickersToDelete)
                .fetchAll(tx.database)

            for favorite in newestFavorites {
                var unfavorited = favorite
                unfavorited.unfavoritedAt = unfavoritedAt
                unfavorited.favoritedAt = nil
                unfavorited.packKey = nil
                unfavorited.localKey = nil
                unfavorited.plaintextLength = nil
                try unfavorited.update(tx.database)
            }

            return newestFavorites
        }
    }
}
