//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct KyberPreKeyUseRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "KyberPreKeyUse"

    var kyberRowId: Int64
    var signedPreKeyIdentity: OWSIdentity
    var signedPreKeyId: UInt32
    var baseKey: Data

    enum CodingKeys: String, CodingKey {
        case kyberRowId
        case signedPreKeyIdentity
        case signedPreKeyId
        case baseKey
    }
}
