//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

/// A record of incomplete payments activation requests.
/// When we activate payments, we use these to find the senders that requested we
/// activate, so we can send them a ``OWSPaymentActivationRequestFinishedMessage``,
/// then we delete these models.
public struct TSPaymentsActivationRequestModel: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "TSPaymentsActivationRequestModel"

    public var id: Int64?
    public let threadUniqueId: String
    public let senderAci: Aci

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    public init(
        threadUniqueId: String,
        senderAci: Aci,
    ) {
        self.threadUniqueId = threadUniqueId
        self.senderAci = senderAci
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.threadUniqueId = try container.decode(String.self, forKey: .threadUniqueId)
        let rawAci = try container.decode(Data.self, forKey: .senderAci)
        self.senderAci = try Aci.parseFrom(serviceIdBinary: rawAci)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(threadUniqueId, forKey: .threadUniqueId)
        try container.encode(senderAci.serviceIdBinary, forKey: .senderAci)
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case threadUniqueId
        case senderAci
    }

    public static func createIfNotExists(
        threadUniqueId: String,
        senderAci: Aci,
        transaction: DBWriteTransaction,
    ) {
        let sql = """
            SELECT EXISTS (
                SELECT 1 FROM \(Self.databaseTableName)
                WHERE \(CodingKeys.threadUniqueId.rawValue) IS ?
            )
        """
        let arguments: StatementArguments = [
            threadUniqueId,
        ]
        failIfThrows {
            let exists = try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
            if exists {
                return
            }
            let model = Self(threadUniqueId: threadUniqueId, senderAci: senderAci)
            try model.insert(transaction.database)
        }
    }

    public static func allThreadsWithPaymentActivationRequests(
        transaction: DBReadTransaction,
    ) -> [TSThread] {
        // This could be a SQL join, but the table is really small
        // so its fine to do an in-memory join.
        failIfThrows {
            return try TSPaymentsActivationRequestModel.fetchAll(transaction.database)
                .compactMap { model in
                    return TSThread.anyFetch(uniqueId: model.threadUniqueId, transaction: transaction)
                }
        }
    }
}
