//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct CombinedGroupSendEndorsementRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "CombinedGroupSendEndorsement"

    public typealias RowId = GroupRecord.RowId

    public let groupRowId: RowId
    let endorsement: Data
    public let expiration: Date

    enum CodingKeys: String, CodingKey {
        case groupRowId
        case endorsement
        case expiration
    }

    init(groupRowId: RowId, endorsement: Data, expiration: Date) {
        self.groupRowId = groupRowId
        self.endorsement = endorsement
        self.expiration = expiration
    }

    var expirationTimestamp: UInt64 {
        return UInt64(expiration.timeIntervalSince1970)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.groupRowId, forKey: .groupRowId)
        try container.encode(self.endorsement, forKey: .endorsement)
        try container.encode(Int64(bitPattern: UInt64(self.expiration.timeIntervalSince1970)), forKey: .expiration)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.groupRowId = try container.decode(RowId.self, forKey: .groupRowId)
        self.endorsement = try container.decode(Data.self, forKey: .endorsement)
        self.expiration = try Date(timeIntervalSince1970: TimeInterval(UInt64(bitPattern: container.decode(Int64.self, forKey: .expiration))))
    }
}

struct IndividualGroupSendEndorsementRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "IndividualGroupSendEndorsement"

    let groupRowId: CombinedGroupSendEndorsementRecord.RowId
    let recipientId: SignalRecipient.RowId
    let endorsement: Data

    enum CodingKeys: String, CodingKey {
        case groupRowId
        case recipientId
        case endorsement
    }
}
