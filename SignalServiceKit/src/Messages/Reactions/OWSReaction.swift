//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

@objc(OWSReaction) // Named explicitly to preserve NSKeyedUnarchiving compatibility
public final class OWSReaction: NSObject, SDSCodableModel, NSSecureCoding {
    public static let databaseTableName = "model_OWSReaction"
    public static var recordType: UInt { SDSRecordType.reaction.rawValue }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case emoji
        case reactorE164
        case reactorUUID
        case receivedAtTimestamp
        case sentAtTimestamp
        case uniqueMessageId
        case read
    }

    public var id: Int64?
    @objc
    public let uniqueId: String

    @objc
    public let uniqueMessageId: String
    @objc
    public let emoji: String
    @objc
    public let reactor: SignalServiceAddress
    @objc
    public let sentAtTimestamp: UInt64
    @objc
    public let receivedAtTimestamp: UInt64
    @objc
    public private(set) var read: Bool

    @objc
    public required init(
        uniqueMessageId: String,
        emoji: String,
        reactor: SignalServiceAddress,
        sentAtTimestamp: UInt64,
        receivedAtTimestamp: UInt64
    ) {
        self.uniqueId = UUID().uuidString
        self.uniqueMessageId = uniqueMessageId
        self.emoji = emoji
        self.reactor = reactor
        self.sentAtTimestamp = sentAtTimestamp
        self.receivedAtTimestamp = receivedAtTimestamp
        self.read = false
    }

    @objc
    public func markAsRead(transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { reaction in
            reaction.read = true
        }
        notificationsManager?.cancelNotifications(reactionId: uniqueId)
    }

    // TODO: Figure out how to avoid having to duplicate this implementation
    // in order to expose the method to ObjC
    @objc
    public class func anyEnumerate(
        transaction: SDSAnyReadTransaction,
        batched: Bool = false,
        block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerate(transaction: transaction, batchSize: batchSize, block: block)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)

        uniqueMessageId = try container.decode(String.self, forKey: .uniqueMessageId)
        emoji = try container.decode(String.self, forKey: .emoji)

        let reactorUuid = try container.decodeIfPresent(UUID.self, forKey: .reactorUUID)
        let reactorE164 = try container.decodeIfPresent(String.self, forKey: .reactorE164)
        reactor = SignalServiceAddress(uuid: reactorUuid, phoneNumber: reactorE164)

        sentAtTimestamp = try container.decode(UInt64.self, forKey: .sentAtTimestamp)
        receivedAtTimestamp = try container.decode(UInt64.self, forKey: .receivedAtTimestamp)
        read = try container.decode(Bool.self, forKey: .read)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try id.map { try container.encode($0, forKey: .id) }
        try container.encode(recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)

        try container.encode(uniqueMessageId, forKey: .uniqueMessageId)
        try container.encode(emoji, forKey: .emoji)

        try reactor.uuid.map { try container.encode($0, forKey: .reactorUUID) }
        try reactor.phoneNumber.map { try container.encode($0, forKey: .reactorE164) }

        try container.encode(sentAtTimestamp, forKey: .sentAtTimestamp)
        try container.encode(receivedAtTimestamp, forKey: .receivedAtTimestamp)
        try container.encode(read, forKey: .read)
    }

    // MARK: - NSSecureCoding

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        id.map { coder.encode(NSNumber(value: $0), forKey: CodingKeys.id.rawValue) }
        coder.encode(uniqueId, forKey: CodingKeys.uniqueId.rawValue)

        coder.encode(uniqueMessageId, forKey: CodingKeys.uniqueMessageId.rawValue)
        coder.encode(emoji, forKey: CodingKeys.emoji.rawValue)

        reactor.uuid.map { coder.encode($0, forKey: CodingKeys.reactorUUID.rawValue) }
        reactor.phoneNumber.map { coder.encode($0, forKey: CodingKeys.reactorE164.rawValue) }

        coder.encode(NSNumber(value: sentAtTimestamp), forKey: CodingKeys.sentAtTimestamp.rawValue)
        coder.encode(NSNumber(value: receivedAtTimestamp), forKey: CodingKeys.receivedAtTimestamp.rawValue)
        coder.encode(NSNumber(value: read), forKey: CodingKeys.read.rawValue)
    }

    public required init?(coder: NSCoder) {
        self.id = coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.id.rawValue)?.int64Value

        guard let uniqueId = coder.decodeObject(of: NSString.self, forKey: CodingKeys.uniqueId.rawValue) as String? else {
            owsFailDebug("Missing uniqueId")
            return nil
        }
        self.uniqueId = uniqueId

        guard let uniqueMessageId = coder.decodeObject(of: NSString.self, forKey: CodingKeys.uniqueMessageId.rawValue) as String? else {
            owsFailDebug("Missing uniqueMessageId")
            return nil
        }
        self.uniqueMessageId = uniqueMessageId

        guard let emoji = coder.decodeObject(of: NSString.self, forKey: CodingKeys.emoji.rawValue) as String? else {
            owsFailDebug("Missing emoji")
            return nil
        }
        self.emoji = emoji

        let reactorUuid = coder.decodeObject(of: NSUUID.self, forKey: CodingKeys.reactorUUID.rawValue) as UUID?
        let reactorE164 = coder.decodeObject(of: NSString.self, forKey: CodingKeys.reactorE164.rawValue) as String?
        self.reactor = SignalServiceAddress(uuid: reactorUuid, phoneNumber: reactorE164)

        guard let sentAtTimestamp = coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.sentAtTimestamp.rawValue)?.uint64Value else {
            owsFailDebug("Missing sentAtTimestamp")
            return nil
        }
        self.sentAtTimestamp = sentAtTimestamp

        guard let receivedAtTimestamp = coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.receivedAtTimestamp.rawValue)?.uint64Value else {
            owsFailDebug("Missing receivedAtTimestamp")
            return nil
        }
        self.receivedAtTimestamp = receivedAtTimestamp

        guard let read = coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.read.rawValue)?.boolValue else {
            owsFailDebug("Missing read")
            return nil
        }
        self.read = read
    }
}
