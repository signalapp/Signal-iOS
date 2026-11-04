//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public final class InstalledStickerRecord: SDSCodableModel, Decodable {
    public static let databaseTableName: String = "model_InstalledSticker"

    public var id: Int64?
    public let uniqueId: String
    public let info: StickerInfo
    public let emojiString: String?
    public let contentType: String?
    public let localKey: Data?
    public let plaintextLength: UInt32?

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case recordType
        case uniqueId
        case info
        case emojiString
        case contentType
        case localKey
        case plaintextLength
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
        let infoData = try container.decode(Data.self, forKey: .info)
        self.info = try LegacySDSSerializer().deserializeLegacySDSData(infoData, ofClass: StickerInfo.self)
        self.emojiString = try container.decodeIfPresent(String.self, forKey: .emojiString)
        self.contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        self.localKey = try container.decodeIfPresent(Data.self, forKey: .localKey)
        self.plaintextLength = try container.decodeIfPresent(UInt32.self, forKey: .plaintextLength)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.id, forKey: .id)
        try container.encode(self.uniqueId, forKey: .uniqueId)
        try container.encode(0, forKey: .recordType)
        try container.encode(LegacySDSSerializer().serializeAsLegacySDSData(self.info), forKey: .info)
        try container.encodeIfPresent(self.emojiString, forKey: .emojiString)
        try container.encodeIfPresent(self.contentType, forKey: .contentType)
        try container.encodeIfPresent(self.localKey, forKey: .localKey)
        try container.encodeIfPresent(self.plaintextLength, forKey: .plaintextLength)
    }

    init(
        info: StickerInfo,
        contentType: String?,
        emojiString: String?,
        localKey: Data,
        plaintextLength: UInt32,
    ) {
        owsAssertDebug(!info.packId.isEmpty)
        owsAssertDebug(!info.packKey.isEmpty)

        self.id = nil
        self.uniqueId = StickerManager.uniqueId(for: info)
        self.info = info
        self.contentType = contentType?.nilIfEmpty
        self.emojiString = emojiString
        self.localKey = localKey
        self.plaintextLength = plaintextLength
    }

    private init(
        id: Int64?,
        uniqueId: String,
        info: StickerInfo,
        contentType: String?,
        emojiString: String?,
        localKey: Data?,
        plaintextLength: UInt32?,
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.info = info
        self.contentType = contentType
        self.emojiString = emojiString
        self.localKey = localKey
        self.plaintextLength = plaintextLength
    }

    func deepCopy() -> Self {
        return Self(
            id: self.id,
            uniqueId: self.uniqueId,
            info: self.info,
            contentType: self.contentType,
            emojiString: self.emojiString,
            localKey: self.localKey,
            plaintextLength: self.plaintextLength,
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
}

#if TESTABLE_BUILD
extension InstalledStickerRecord {
    static func mockPlaintext(
        info: StickerInfo = StickerInfo(
            packId: Randomness.generateRandomBytes(16),
            packKey: Randomness.generateRandomBytes(StickerManager.packKeyLength),
            stickerId: UInt32.random(in: 0..<1024),
        ),
        contentType: String? = MimeType.imageWebp.rawValue,
        emojiString: String? = nil,
    ) -> InstalledStickerRecord {
        return InstalledStickerRecord(
            id: nil,
            uniqueId: StickerManager.uniqueId(for: info),
            info: info,
            contentType: contentType,
            emojiString: emojiString,
            localKey: nil,
            plaintextLength: nil,
        )
    }
}
#endif
