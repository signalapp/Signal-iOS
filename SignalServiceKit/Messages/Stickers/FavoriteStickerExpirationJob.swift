//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Responsible for cleaning up expired unfavorited ``FavoriteStickerRecord``s.
///
/// Unfavoriting a sticker leaves its row in place, with `unfavoritedAt` set,
/// so StorageService can resolve out-of-order or racing updates from other
/// devices. Once that row has been unfavorited for long enough, this job deletes it.
public final class FavoriteStickerExpirationJob: ExpirationJob<FavoriteStickerRecord> {
    static let unfavoritedExpiresAt: TimeInterval = 45 * .day

    private let stickerFavoriteStore: StickerFavoriteStore

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        stickerFavoriteStore: StickerFavoriteStore,
    ) {
        self.stickerFavoriteStore = stickerFavoriteStore

        super.init(
            dateProvider: dateProvider,
            db: db,
            logger: PrefixedLogger(prefix: "[FavoriteStickerExpJob]"),
        )
    }

    // MARK: -

    override public func nextExpiringElement(tx: DBReadTransaction) -> FavoriteStickerRecord? {
        return stickerFavoriteStore.oldestUnfavoritedSticker(tx: tx)
    }

    override public func expirationDate(ofElement record: FavoriteStickerRecord) -> Date {
        guard let unfavoritedAt = record.unfavoritedAt else {
            owsFailDebug("Only unfavorited records should expire.")
            return .distantFuture
        }
        return Date(millisecondsSince1970: UInt64(clamping: unfavoritedAt))
            .addingTimeInterval(Self.unfavoritedExpiresAt)
    }

    override public func deleteExpiredElement(_ record: FavoriteStickerRecord, tx: DBWriteTransaction) {
        // The sticker's file was deleted when it was unfavorited, so only the
        // row remains.
        stickerFavoriteStore.deleteUnfavoritedSticker(record, tx: tx)
    }
}
