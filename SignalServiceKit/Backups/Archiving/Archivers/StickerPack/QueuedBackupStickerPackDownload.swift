//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

public struct QueuedBackupStickerPackDownload: Codable, FetchableRecord, MutablePersistableRecord {

    public typealias IDType = Int64

    /// Sqlite row id
    public private(set) var id: IDType?

    public let packId: Data
    public let packKey: Data

    // MARK: FetchableRecord

    public static var databaseTableName: String { "BackupStickerPackDownloadQueue" }

    // MARK: MutablePersistableRecord

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    enum CodingKeys: CodingKey {
        case id
        case packId
        case packKey
    }
}
