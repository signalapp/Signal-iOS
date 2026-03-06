//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public final class InstalledStickerRecord: SDSCodableModel, Decodable {
    public static let databaseTableName: String = "model_InstalledSticker"
    private static let recordType: SDSRecordType = .installedSticker

    public var id: Int64?
    public let uniqueId: String
    public let info: StickerInfo
    public let emojiString: String?
    public let contentType: String?

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case recordType
        case uniqueId
        case info
        case emojiString
        case contentType
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
        let infoData = try container.decode(Data.self, forKey: .info)
        self.info = try LegacySDSSerializer().deserializeLegacySDSData(infoData, ofClass: StickerInfo.self)
        self.emojiString = try container.decodeIfPresent(String.self, forKey: .emojiString)
        self.contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.id, forKey: .id)
        try container.encode(self.uniqueId, forKey: .uniqueId)
        try container.encode(Self.recordType.rawValue, forKey: .recordType)
        try container.encode(LegacySDSSerializer().serializeAsLegacySDSData(self.info), forKey: .info)
        try container.encodeIfPresent(self.emojiString, forKey: .emojiString)
        try container.encodeIfPresent(self.contentType, forKey: .contentType)
    }

    init(
        info: StickerInfo,
        contentType: String?,
        emojiString: String?,
    ) {
        owsAssertDebug(!info.packId.isEmpty)
        owsAssertDebug(!info.packKey.isEmpty)

        self.id = nil
        self.uniqueId = Self.uniqueId(for: info)
        self.info = info
        self.contentType = contentType?.nilIfEmpty
        self.emojiString = emojiString
    }

    private init(
        id: Int64?,
        uniqueId: String,
        info: StickerInfo,
        contentType: String?,
        emojiString: String?,
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.info = info
        self.contentType = contentType
        self.emojiString = emojiString
    }

    func deepCopy() -> Self {
        return Self(
            id: self.id,
            uniqueId: self.uniqueId,
            info: self.info,
            contentType: self.contentType,
            emojiString: self.emojiString,
        )
    }

    var packId: Data {
        return self.info.packId
    }

    var packKey: Data {
        return self.info.packKey
    }

    var stickerId: UInt32 {
        return self.info.stickerId
    }

    static func uniqueId(for stickerInfo: StickerInfo) -> String {
        return stickerInfo.asKey()
    }

    public func anyDidInsert(transaction: DBWriteTransaction) {
        SSKEnvironment.shared.modelReadCachesRef.installedStickerCache.didInsertOrUpdate(installedSticker: self, transaction: transaction)
    }

    public func anyDidUpdate(transaction: DBWriteTransaction) {
        SSKEnvironment.shared.modelReadCachesRef.installedStickerCache.didInsertOrUpdate(installedSticker: self, transaction: transaction)
    }

    public func anyDidRemove(transaction: DBWriteTransaction) {
        SSKEnvironment.shared.modelReadCachesRef.installedStickerCache.didRemove(installedSticker: self, transaction: transaction)
    }

    public func anyDidFetchOne(transaction: DBReadTransaction) {
        SSKEnvironment.shared.modelReadCachesRef.installedStickerCache.didReadInstalledSticker(self, transaction: transaction)
    }

    public func anyDidEnumerateOne(transaction: DBReadTransaction) {
        SSKEnvironment.shared.modelReadCachesRef.installedStickerCache.didReadInstalledSticker(self, transaction: transaction)
    }
}
