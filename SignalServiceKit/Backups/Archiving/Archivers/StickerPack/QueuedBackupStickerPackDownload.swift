//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

struct QueuedBackupStickerPackDownload: Codable, FetchableRecord, MutablePersistableRecord {

    typealias IDType = Int64

    /// Sqlite row id
    private(set) var id: IDType?

    let packId: Data
    let packKey: Data

    // MARK: FetchableRecord

    static var databaseTableName: String { "BackupStickerPackDownloadQueue" }

    // MARK: MutablePersistableRecord

    mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    enum CodingKeys: CodingKey {
        case id
        case packId
        case packKey
    }
}
