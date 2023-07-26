//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

@objc(OWSReaction) // Named explicitly to preserve NSKeyedUnarchiving compatability
public final class OWSReaction: NSObject, SDSCodableModel, Decodable, NSSecureCoding {
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
        notificationsManager.cancelNotifications(reactionId: uniqueId)
    }

    @objc
    public static func anyEnumerateObjc(
        transaction: SDSAnyReadTransaction,
        batched: Bool,
        block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchingPreference: BatchingPreference = batched ? .batched() : .unbatched
        anyEnumerate(transaction: transaction, batchingPreference: batchingPreference, block: block)
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

        // If we have a ServiceId, ignore the phone number.
        if let reactorServiceId = try container.decodeIfPresent(UntypedServiceId.self, forKey: .reactorUUID) {
            reactor = SignalServiceAddress(reactorServiceId)
        } else if let reactorPhoneNumber = try container.decodeIfPresent(String.self, forKey: .reactorE164) {
            reactor = SignalServiceAddress(phoneNumber: reactorPhoneNumber)
        } else {
            reactor = SignalServiceAddress(uuid: nil, phoneNumber: nil)
        }

        sentAtTimestamp = try container.decode(UInt64.self, forKey: .sentAtTimestamp)
        receivedAtTimestamp = try container.decode(UInt64.self, forKey: .receivedAtTimestamp)
        read = try container.decode(Bool.self, forKey: .read)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try id.map { try container.encode($0, forKey: .id) }
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)

        try container.encode(uniqueMessageId, forKey: .uniqueMessageId)
        try container.encode(emoji, forKey: .emoji)

        // If we have a ServiceId, ignore the phone number.
        if let reactorServiceId = reactor.untypedServiceId {
            try container.encode(reactorServiceId.uuidValue, forKey: .reactorUUID)
        } else if let reactorPhoneNumber = reactor.phoneNumber {
            try container.encode(reactorPhoneNumber, forKey: .reactorE164)
        }

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

        // If we have a ServiceId, ignore the phone number.
        if let reactorServiceId = reactor.untypedServiceId {
            coder.encode(reactorServiceId.uuidValue, forKey: CodingKeys.reactorUUID.rawValue)
        } else if let reactorPhoneNumber = reactor.phoneNumber {
            coder.encode(reactorPhoneNumber, forKey: CodingKeys.reactorE164.rawValue)
        }

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

        // If we have a ServiceId, ignore the phone number.
        if let reactorServiceId = coder.decodeObject(of: NSUUID.self, forKey: CodingKeys.reactorUUID.rawValue) {
            reactor = SignalServiceAddress(UntypedServiceId(reactorServiceId as UUID))
        } else if let reactorPhoneNumber = coder.decodeObject(of: NSString.self, forKey: CodingKeys.reactorE164.rawValue) {
            reactor = SignalServiceAddress(phoneNumber: reactorPhoneNumber as String)
        } else {
            reactor = SignalServiceAddress(uuid: nil, phoneNumber: nil)
        }

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
