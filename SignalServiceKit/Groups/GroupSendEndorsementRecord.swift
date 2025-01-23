//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct CombinedGroupSendEndorsementRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "CombinedGroupSendEndorsement"

    let threadId: Int64
    let endorsement: Data
    let expiration: Date

    enum CodingKeys: String, CodingKey {
        case threadId
        case endorsement
        case expiration
    }

    init(threadId: Int64, endorsement: Data, expiration: Date) {
        self.threadId = threadId
        self.endorsement = endorsement
        self.expiration = expiration
    }

    var expirationTimestamp: UInt64 {
        return UInt64(expiration.timeIntervalSince1970)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.threadId, forKey: .threadId)
        try container.encode(self.endorsement, forKey: .endorsement)
        try container.encode(Int64(bitPattern: UInt64(self.expiration.timeIntervalSince1970)), forKey: .expiration)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadId = try container.decode(Int64.self, forKey: .threadId)
        self.endorsement = try container.decode(Data.self, forKey: .endorsement)
        self.expiration = try Date(timeIntervalSince1970: TimeInterval(UInt64(bitPattern: container.decode(Int64.self, forKey: .expiration))))
    }
}

struct IndividualGroupSendEndorsementRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "IndividualGroupSendEndorsement"

    let threadId: Int64
    let recipientId: Int64
    let endorsement: Data

    enum CodingKeys: String, CodingKey {
        case threadId
        case recipientId
        case endorsement
    }
}
