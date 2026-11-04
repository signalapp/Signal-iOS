//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Uniquely identifies a favorited (or unfavorited) sticker, independent of its pack key.
/// Used when constructing records for StorageService.
public struct FavoriteStickerId: Hashable, Codable {
    public let packId: Data
    public let stickerId: UInt32

    public init(packId: Data, stickerId: UInt32) {
        self.packId = packId
        self.stickerId = stickerId
    }
}

/// For StorageService, we require an "unfavoritedAt" timestamp to handle races.
/// If unfavoritedAt is set, favoritedAt should be nil, and vice-versa.
public struct FavoriteStickerRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "FavoriteStickerRecord"

    public let id: Int64
    public var emojiString: String?
    public var contentType: String?
    public var localKey: Data?
    public var plaintextLength: UInt32?
    public var favoritedAt: Int64?
    public var unfavoritedAt: Int64?

    // Pack info
    public let packId: Data
    public var packKey: Data?
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

    // A specific ON CONFLICT policy is required here
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

    static func unfavoriteSticker(
        packId: Data,
        stickerId: UInt32,
        unfavoritedAt: Int64,
        tx: DBWriteTransaction,
    ) throws -> Self {
        owsAssertDebug(!packId.isEmpty)

        return try FavoriteStickerRecord.fetchOne(
            tx.database,
            sql: """
            INSERT INTO \(FavoriteStickerRecord.databaseTableName) (
                \(CodingKeys.unfavoritedAt.rawValue),
                \(CodingKeys.packId.rawValue),
                \(CodingKeys.stickerId.rawValue)
            ) VALUES (?, ?, ?)
            ON CONFLICT(\(CodingKeys.packId.rawValue), \(CodingKeys.stickerId.rawValue)) DO UPDATE SET
                \(CodingKeys.unfavoritedAt.rawValue) = excluded.\(CodingKeys.unfavoritedAt.rawValue),
                \(CodingKeys.favoritedAt.rawValue) = NULL,
                \(CodingKeys.packKey.rawValue) = NULL,
                \(CodingKeys.localKey.rawValue) = NULL,
                \(CodingKeys.plaintextLength.rawValue) = NULL
            RETURNING *
            """,
            arguments: [unfavoritedAt, packId, stickerId],
        )!
    }

    static func filter(packId: Data, stickerId: UInt32, currentFavoritesOnly: Bool) -> QueryInterfaceRequest<FavoriteStickerRecord> {
        var request = filter(
            Column(CodingKeys.packId) == packId
                && Column(CodingKeys.stickerId) == stickerId,
        )
        if currentFavoritesOnly {
            request = request.filter(Column(CodingKeys.favoritedAt) != nil)
        }
        return request
    }

    func nonNilTimestamp() -> Int64 {
        if let favoritedAt {
            return favoritedAt
        }
        if let unfavoritedAt {
            return unfavoritedAt
        }
        owsFailDebug("either favoritedAt or unfavoritedAt should be set")
        return 0
    }
}
