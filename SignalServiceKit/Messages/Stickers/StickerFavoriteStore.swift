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

    func isFavoritedSticker(
        stickerInfo: StickerInfo,
        tx: DBReadTransaction,
    ) -> Bool {
        return failIfThrows {
            try !FavoriteStickerRecord
                .filter(stickerInfo: stickerInfo, currentFavoritesOnly: true)
                .isEmpty(tx.database)
        }
    }

    func fetchFavoriteSticker(
        stickerInfo: StickerInfo,
        tx: DBReadTransaction,
    ) -> FavoriteStickerRecord? {
        return failIfThrows {
            try FavoriteStickerRecord
                .filter(
                    stickerInfo: stickerInfo,
                    currentFavoritesOnly: true,
                ).fetchOne(tx.database)
        }
    }

    func removeStickerFromFavorites(
        stickerInfo: StickerInfo,
        unfavoritedAtTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try FavoriteStickerRecord
                .filter(
                    stickerInfo: stickerInfo,
                    currentFavoritesOnly: true,
                ).updateAll(
                    tx.database,
                    [
                        Column(FavoriteStickerRecord.CodingKeys.unfavoritedAt).set(to: unfavoritedAtTimestamp),
                        Column(FavoriteStickerRecord.CodingKeys.favoritedAt).set(to: nil),
                        Column(FavoriteStickerRecord.CodingKeys.packKey).set(to: nil),
                    ],
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

    func favoritedStickers(tx: DBReadTransaction) -> [FavoriteStickerRecord] {
        return failIfThrows {
            return try FavoriteStickerRecord
                .filter(Column(FavoriteStickerRecord.CodingKeys.favoritedAt) != nil)
                .order(Column(FavoriteStickerRecord.CodingKeys.id).desc)
                .fetchAll(tx.database)
        }
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

    func deleteUnfavoritedSticker(_ record: FavoriteStickerRecord, tx: DBWriteTransaction) {
        failIfThrows {
            _ = try FavoriteStickerRecord
                .filter(Column(FavoriteStickerRecord.CodingKeys.id) == record.id)
                .filter(Column(FavoriteStickerRecord.CodingKeys.unfavoritedAt) != nil)
                .deleteAll(tx.database)
        }
    }
}
