//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public final class TSMention: NSObject, SDSCodableModel, Decodable {
    public static let databaseTableName = "model_TSMention"
    public static var recordType: UInt { SDSRecordType.mention.rawValue }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case uniqueMessageId
        case uniqueThreadId
        case uuidString
        case creationTimestamp
    }

    public var id: Int64?
    @objc
    public let uniqueId: String

    @objc
    public let uniqueMessageId: String
    @objc
    public let uniqueThreadId: String
    @objc
    public let uuidString: String
    @objc
    public let creationDate: Date

    @objc
    public var address: SignalServiceAddress { SignalServiceAddress(uuidString: uuidString) }

    @objc
    required public init(uniqueMessageId: String, uniqueThreadId: String, uuidString: String) {
        self.uniqueId = UUID().uuidString
        self.uniqueMessageId = uniqueMessageId
        self.uniqueThreadId = uniqueThreadId
        self.uuidString = uuidString
        self.creationDate = Date()
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)

        uniqueMessageId = try container.decode(String.self, forKey: .uniqueMessageId)
        uniqueThreadId = try container.decode(String.self, forKey: .uniqueThreadId)
        uuidString = try container.decode(String.self, forKey: .uuidString)
        creationDate = try container.decode(Date.self, forKey: .creationTimestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try id.map { try container.encode($0, forKey: .id) }
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)

        try container.encode(uniqueMessageId, forKey: .uniqueMessageId)
        try container.encode(uniqueThreadId, forKey: .uniqueThreadId)
        try container.encode(uuidString, forKey: .uuidString)
        try container.encode(creationDate, forKey: .creationTimestamp)
    }

    @objc
    public func anyInsertObjc(transaction: SDSAnyWriteTransaction) {
        anyInsert(transaction: transaction)
    }

    @objc
    public static func anyEnumerateObjc(
        transaction: SDSAnyReadTransaction,
        batched: Bool,
        block: @escaping (TSMention, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchingPreference: BatchingPreference = batched ? .batched() : .unbatched
        anyEnumerate(transaction: transaction, batchingPreference: batchingPreference, block: block)
    }
}
