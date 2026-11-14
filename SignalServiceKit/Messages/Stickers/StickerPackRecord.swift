//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public final class StickerPackRecord: SDSCodableModel, Decodable, Equatable, NSCopying {
    public static let databaseTableName: String = "model_StickerPack"

    public var id: Int64?
    public let uniqueId: String
    public let info: StickerPackInfo
    public let title: String?
    public let author: String?
    public let cover: StickerPackItem
    public let items: [StickerPackItem]
    public let dateCreated: Date
    public private(set) var isInstalled: Bool
    public private(set) var sortOrder: Int64

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case recordType
        case uniqueId
        case author
        case cover
        case dateCreated
        case info
        case isInstalled
        case items
        case title
        case sortOrder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
        let infoData = try container.decode(Data.self, forKey: .info)
        self.info = try LegacySDSSerializer().deserializeLegacySDSData(infoData, ofClass: StickerPackInfo.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.author = try container.decodeIfPresent(String.self, forKey: .author)
        let coverData = try container.decode(Data.self, forKey: .cover)
        self.cover = try LegacySDSSerializer().deserializeLegacySDSData(coverData, ofClass: StickerPackItem.self)
        let itemsData = try container.decode(Data.self, forKey: .items)
        self.items = try LegacySDSSerializer().deserializeLegacyArchivedArray(itemsData, ofClass: StickerPackItem.self)
        self.dateCreated = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .dateCreated))
        self.isInstalled = try container.decode(Bool.self, forKey: .isInstalled)
        self.sortOrder = try container.decode(Int64.self, forKey: .sortOrder)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.id, forKey: .id)
        try container.encode(self.uniqueId, forKey: .uniqueId)
        try container.encode(0, forKey: .recordType)
        try container.encode(LegacySDSSerializer().serializeAsLegacySDSData(self.info), forKey: .info)
        try container.encodeIfPresent(self.title, forKey: .title)
        try container.encodeIfPresent(self.author, forKey: .author)
        try container.encode(LegacySDSSerializer().serializeAsLegacySDSData(self.cover), forKey: .cover)
        try container.encode(LegacySDSSerializer().serializeAsLegacySDSData(self.items as [NSSecureCoding] as NSArray), forKey: .items)
        try container.encode(self.dateCreated.timeIntervalSince1970, forKey: .dateCreated)
        try container.encode(self.isInstalled, forKey: .isInstalled)
        try container.encode(self.sortOrder, forKey: .sortOrder)
    }

    public static func ==(lhs: StickerPackRecord, rhs: StickerPackRecord) -> Bool {
        guard lhs.author == rhs.author else { return false }
        guard lhs.cover == rhs.cover else { return false }
        guard lhs.dateCreated == rhs.dateCreated else { return false }
        guard lhs.info == rhs.info else { return false }
        guard lhs.isInstalled == rhs.isInstalled else { return false }
        guard lhs.items == rhs.items else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.sortOrder == rhs.sortOrder else { return false }
        return true
    }

    convenience init(
        info: StickerPackInfo,
        title: String?,
        author: String?,
        cover: StickerPackItem,
        items: [StickerPackItem],
    ) {
        owsAssertDebug(!info.packId.isEmpty)
        owsAssertDebug(!info.packKey.isEmpty)
        owsAssertDebug(!items.isEmpty)
        self.init(
            id: nil,
            uniqueId: Self.uniqueId(forStickerPackInfo: info),
            info: info,
            title: title,
            author: author,
            cover: cover,
            items: items,
            dateCreated: Date(),
            isInstalled: false,
            sortOrder: 0,
        )
    }

    private init(
        id: Int64?,
        uniqueId: String,
        info: StickerPackInfo,
        title: String?,
        author: String?,
        cover: StickerPackItem,
        items: [StickerPackItem],
        dateCreated: Date,
        isInstalled: Bool,
        sortOrder: Int64,
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.info = info
        self.title = title
        self.author = author
        self.cover = cover
        self.items = items
        self.dateCreated = dateCreated
        self.isInstalled = isInstalled
        self.sortOrder = sortOrder
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return Self(
            id: self.id,
            uniqueId: self.uniqueId,
            info: self.info,
            title: self.title,
            author: self.author,
            cover: self.cover,
            items: self.items,
            dateCreated: self.dateCreated,
            isInstalled: self.isInstalled,
            sortOrder: self.sortOrder,
        )
    }

    public var packId: Data {
        // This was the effective behavior in Swift via Obj-C.
        return self.info.packId ?? Data()
    }

    public var packKey: Data {
        // This was the effective behavior in Swift via Obj-C.
        return self.info.packKey ?? Data()
    }

    public var coverInfo: StickerInfo {
        let packId = self.info.packId
        let packKey = self.info.packKey
        return StickerInfo(packId: packId ?? Data(), packKey: packKey ?? Data(), stickerId: self.cover.stickerId)
    }

    public func stickerInfos() -> [StickerInfo] {
        return self.items.map({ $0.stickerInfoWith(stickerPack: self) })
    }

    static func uniqueId(forStickerPackInfo stickerPackInfo: StickerPackInfo) -> String {
        return stickerPackInfo.asKey
    }

    func updateWith(isInstalled: Bool, tx: DBWriteTransaction) {
        anyUpdate(transaction: tx, block: { $0.isInstalled = isInstalled })
    }

    func updateWith(sortOrder: Int64, tx: DBWriteTransaction) {
        anyUpdate(transaction: tx, block: {
            $0.sortOrder = sortOrder
        })
    }

    func updateWith(isInstalled: Bool, sortOrder: Int64, tx: DBWriteTransaction) {
        anyUpdate(transaction: tx, block: {
            $0.isInstalled = isInstalled
            $0.sortOrder = sortOrder
        })
    }

    func item(forStickerId stickerId: UInt32) -> StickerPackItem? {
        if cover.stickerId == stickerId { return cover }
        return items.first { $0.stickerId == stickerId }
    }

    static func maxInstalledSortOrder(tx: DBReadTransaction) -> Int64? {
        return failIfThrows {
            try StickerPackRecord
                .filter(Column(CodingKeys.isInstalled) == true)
                .select(max(Column(CodingKeys.sortOrder)), as: Int64.self)
                .fetchOne(tx.database)
        }
    }
}
