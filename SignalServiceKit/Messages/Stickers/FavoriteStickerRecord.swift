//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// For StorageService, we require an "unfavoritedAt" timestamp to handle races.
/// If unfavoritedAt is set, favoritedAt should be nil, and vice-versa.
public struct FavoriteStickerRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "FavoriteStickerRecord"

    public let id: Int64
    public let emojiString: String?
    public let contentType: String?
    public let localKey: Data?
    public let plaintextLength: UInt32?
    public let favoritedAt: Int64?
    public let unfavoritedAt: Int64?

    // Pack info
    public let packId: Data
    public let packKey: Data?
    public let stickerId: UInt32

    public enum CodingKeys: String, CodingKey {
        case id
        case emojiString
        case contentType
        case localKey
        case plaintextLength
        case favoritedAt
        case unfavoritedAt
        case packId
        case packKey
        case stickerId
    }

    // A specific ON CONFLICT policy is required here because
    // because we don't delete unfavorited stickers, instead
    // we store them with a null favoritedAt value, and
    // non-null unfavoritedAt value. So, if a sticker has been
    // favorited before and then un-favorited, it will exist in
    // the table and we should update its unfavorited value to NULL.
    static func favoriteSticker(
        info: StickerInfo,
        contentType: String?,
        emojiString: String?,
        localKey: Data?,
        plaintextLength: UInt32?,
        favoritedAt: UInt64,
        tx: DBWriteTransaction,
    ) throws -> Self {
        owsAssertDebug(!info.packId.isEmpty)
        owsAssertDebug(!info.packKey.isEmpty)

        return try FavoriteStickerRecord.fetchOne(
            tx.database,
            sql: """
            INSERT INTO \(FavoriteStickerRecord.databaseTableName) (
                \(CodingKeys.emojiString.rawValue),
                \(CodingKeys.contentType.rawValue),
                \(CodingKeys.localKey.rawValue),
                \(CodingKeys.plaintextLength.rawValue),
                \(CodingKeys.favoritedAt.rawValue),
                \(CodingKeys.packId.rawValue),
                \(CodingKeys.packKey.rawValue),
                \(CodingKeys.stickerId.rawValue)
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?) 
            ON CONFLICT(\(CodingKeys.packId.rawValue), \(CodingKeys.stickerId.rawValue)) DO UPDATE SET
                \(CodingKeys.favoritedAt.rawValue) = excluded.\(CodingKeys.favoritedAt.rawValue),
                \(CodingKeys.unfavoritedAt.rawValue) = NULL,
                \(CodingKeys.localKey.rawValue) = excluded.\(CodingKeys.localKey.rawValue),
                \(CodingKeys.plaintextLength.rawValue) = excluded.\(CodingKeys.plaintextLength.rawValue),
                \(CodingKeys.contentType.rawValue) = excluded.\(CodingKeys.contentType.rawValue),
                \(CodingKeys.emojiString.rawValue) = excluded.\(CodingKeys.emojiString.rawValue),
                \(CodingKeys.packKey.rawValue) = excluded.\(CodingKeys.packKey.rawValue)
            RETURNING *
            """,
            arguments: [
                emojiString,
                contentType,
                localKey,
                plaintextLength,
                favoritedAt,
                info.packId,
                info.packKey,
                info.stickerId,
            ],
        )!
    }

    static func filter(stickerInfo: StickerInfo, currentFavoritesOnly: Bool) -> QueryInterfaceRequest<FavoriteStickerRecord> {
        var request = filter(
            Column(CodingKeys.packId) == stickerInfo.packId
                && Column(CodingKeys.stickerId) == stickerInfo.stickerId,
        )
        if currentFavoritesOnly {
            request = request.filter(Column(CodingKeys.favoritedAt) != nil)
        }
        return request
    }
}
