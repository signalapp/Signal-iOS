//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

// We store payment records separately from interactions.
//
// * Payment records might correspond to transfers to/from exchanges,
//   without an associated interaction.
// * Interactions might be deleted, but we need to maintain records of
//   all payments.
public final class TSPaymentModel: NSObject, SDSCodableModel, Decodable {
    public static let databaseTableName: String = "model_TSPaymentModel"
    private static let recordType: SDSRecordType = .paymentModel

    public var id: Int64?
    public let uniqueId: String

    // Incoming, outgoing, etc.
    //
    // This is inferred from paymentState.
    public let paymentType: TSPaymentType

    public private(set) var paymentState: TSPaymentState

    // This property only applies if paymentState is .incomingFailure
    // or .outgoingFailure.
    public private(set) var paymentFailure: TSPaymentFailure

    // Might not be set for unverified incoming payments.
    public private(set) var paymentAmount: TSPaymentAmount?

    public private(set) var createdTimestamp: UInt64

    // Optional. The address of the sender/recipient, if any.
    //
    // We should not treat this value as valid for unverified incoming payments.
    public private(set) var addressUuidString: String?

    // Optional. Used to construct outgoing notifications.
    //           This should only be set for outgoing payments from the device that
    //           submitted the payment.
    //           We should clear this as soon as sending notification succeeds.
    public private(set) var requestUuidString: String?

    public private(set) var memoMessage: String?

    public private(set) var isUnread: Bool

    // Optional. If set, the unique id of the interaction displayed in chat
    // for this payment. If nil, safe to assume no interaction exists and one
    // can be created.
    public private(set) var interactionUniqueId: String?

    // This only applies to mobilecoin.
    public private(set) var mobileCoin: MobileCoinPayment?

    // This only applies to mobilecoin.
    // Used by PaymentFinder.
    // This value is zero if not set.
    public private(set) var mcLedgerBlockIndex: UInt64

    // Only set for outgoing mobileCoin payments.
    // This only applies to mobilecoin.
    // Used by PaymentFinder.
    public private(set) var mcTransactionData: Data?

    // This only applies to mobilecoin.
    // Used by PaymentFinder.
    public private(set) var mcReceiptData: Data?

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case addressUuidString
        case createdTimestamp
        case isUnread
        case mcLedgerBlockIndex
        case mcReceiptData
        case mcTransactionData
        case memoMessage
        case mobileCoin
        case paymentAmount
        case paymentFailure
        case paymentState
        case paymentType
        case requestUuidString
        case interactionUniqueId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
        self.paymentType = try container.decode(TSPaymentType.self, forKey: .paymentType)
        self.paymentState = try container.decode(TSPaymentState.self, forKey: .paymentState)
        self.paymentFailure = try container.decode(TSPaymentFailure.self, forKey: .paymentFailure)
        let paymentAmountData = try container.decodeIfPresent(Data.self, forKey: .paymentAmount)
        self.paymentAmount = try paymentAmountData.map { try LegacySDSSerializer().deserializeLegacySDSData($0, ofClass: TSPaymentAmount.self) }
        self.createdTimestamp = try container.decode(UInt64.self, forKey: .createdTimestamp)
        self.addressUuidString = try container.decodeIfPresent(String.self, forKey: .addressUuidString)
        self.requestUuidString = try container.decodeIfPresent(String.self, forKey: .requestUuidString)
        self.memoMessage = try container.decodeIfPresent(String.self, forKey: .memoMessage)
        self.isUnread = try container.decode(Bool.self, forKey: .isUnread)
        self.interactionUniqueId = try container.decodeIfPresent(String.self, forKey: .interactionUniqueId)
        let mobileCoinData = try container.decodeIfPresent(Data.self, forKey: .mobileCoin)
        self.mobileCoin = try mobileCoinData.map { try LegacySDSSerializer().deserializeLegacySDSData($0, ofClass: MobileCoinPayment.self) }
        self.mcLedgerBlockIndex = try container.decode(UInt64.self, forKey: .mcLedgerBlockIndex)
        self.mcTransactionData = try container.decodeIfPresent(Data.self, forKey: .mcTransactionData)
        self.mcReceiptData = try container.decodeIfPresent(Data.self, forKey: .mcReceiptData)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.uniqueId, forKey: .uniqueId)
        try container.encode(Self.recordType.rawValue, forKey: .recordType)
        try container.encode(self.paymentType, forKey: .paymentType)
        try container.encode(self.paymentState, forKey: .paymentState)
        try container.encode(self.paymentFailure, forKey: .paymentFailure)
        try container.encode(self.paymentAmount.map { LegacySDSSerializer().serializeAsLegacySDSData($0) }, forKey: .paymentAmount)
        try container.encode(self.createdTimestamp, forKey: .createdTimestamp)
        try container.encode(self.addressUuidString, forKey: .addressUuidString)
        try container.encode(self.requestUuidString, forKey: .requestUuidString)
        try container.encode(self.memoMessage, forKey: .memoMessage)
        try container.encode(self.isUnread, forKey: .isUnread)
        try container.encode(self.interactionUniqueId, forKey: .interactionUniqueId)
        try container.encode(self.mobileCoin.map { LegacySDSSerializer().serializeAsLegacySDSData($0) }, forKey: .mobileCoin)
        try container.encode(self.mcLedgerBlockIndex, forKey: .mcLedgerBlockIndex)
        try container.encode(self.mcTransactionData, forKey: .mcTransactionData)
        try container.encode(self.mcReceiptData, forKey: .mcReceiptData)
    }

    public init(
        paymentType: TSPaymentType,
        paymentState: TSPaymentState,
        paymentAmount: TSPaymentAmount?,
        createdDate: Date,
        senderOrRecipientAci: Aci?,
        memoMessage: String?,
        isUnread: Bool,
        interactionUniqueId: String?,
        mobileCoin: MobileCoinPayment,
    ) {
        self.uniqueId = UUID().uuidString
        self.paymentType = paymentType
        self.paymentState = paymentState
        self.paymentFailure = .none
        self.paymentAmount = paymentAmount
        self.createdTimestamp = createdDate.ows_millisecondsSince1970
        self.addressUuidString = senderOrRecipientAci?.serviceIdUppercaseString
        self.memoMessage = memoMessage
        self.requestUuidString = nil
        self.isUnread = isUnread
        self.interactionUniqueId = interactionUniqueId
        self.mobileCoin = mobileCoin

        self.mcLedgerBlockIndex = mobileCoin.ledgerBlockIndex
        self.mcTransactionData = mobileCoin.transactionData
        self.mcReceiptData = mobileCoin.receiptData

        super.init()

        owsAssertDebug(self.isValid)
        Logger.info("Creating payment model: \(self.descriptionForLogs)")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.addressUuidString)
        hasher.combine(self.createdTimestamp)
        hasher.combine(self.interactionUniqueId)
        hasher.combine(self.isUnread)
        hasher.combine(self.mcLedgerBlockIndex)
        hasher.combine(self.mcReceiptData)
        hasher.combine(self.mcTransactionData)
        hasher.combine(self.memoMessage)
        hasher.combine(self.mobileCoin)
        hasher.combine(self.paymentAmount)
        hasher.combine(self.paymentFailure)
        hasher.combine(self.paymentState)
        hasher.combine(self.paymentType)
        hasher.combine(self.requestUuidString)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.addressUuidString == object.addressUuidString else { return false }
        guard self.createdTimestamp == object.createdTimestamp else { return false }
        guard self.interactionUniqueId == object.interactionUniqueId else { return false }
        guard self.isUnread == object.isUnread else { return false }
        guard self.mcLedgerBlockIndex == object.mcLedgerBlockIndex else { return false }
        guard self.mcReceiptData == object.mcReceiptData else { return false }
        guard self.mcTransactionData == object.mcTransactionData else { return false }
        guard self.memoMessage == object.memoMessage else { return false }
        guard self.mobileCoin == object.mobileCoin else { return false }
        guard self.paymentAmount == object.paymentAmount else { return false }
        guard self.paymentFailure == object.paymentFailure else { return false }
        guard self.paymentState == object.paymentState else { return false }
        guard self.paymentType == object.paymentType else { return false }
        guard self.requestUuidString == object.requestUuidString else { return false }
        return true
    }

    public var createdDate: Date {
        return Date(millisecondsSince1970: self.createdTimestamp)
    }

    public var senderOrRecipientAci: Aci? {
        return Aci.parseFrom(aciString: self.addressUuidString)
    }

    // This uses ledgerBlockDate if available and createdDate otherwise.
    public var sortDate: Date {
        return self.mcLedgerBlockDate ?? self.createdDate
    }

    public func update(paymentState: TSPaymentState, transaction: DBWriteTransaction) {
        anyUpdate(transaction: transaction) {
            owsAssertDebug($0.paymentState.isIncoming == paymentState.isIncoming)
            $0.paymentState = paymentState
        }
    }

    public func update(mcLedgerBlockIndex: UInt64, transaction: DBWriteTransaction) {
        owsAssertDebug(mcLedgerBlockIndex > 0)

        anyUpdate(transaction: transaction) {
            owsAssertDebug(!$0.hasMCLedgerBlockIndex)
            $0.mobileCoin = MobileCoinPayment.copy($0.mobileCoin, withLedgerBlockIndex: mcLedgerBlockIndex)
            $0.mcLedgerBlockIndex = mcLedgerBlockIndex
            owsAssertDebug($0.mobileCoin != nil)
        }
    }

    public func update(mcLedgerBlockTimestamp: UInt64, transaction: DBWriteTransaction) {
        owsAssertDebug(mcLedgerBlockTimestamp > 0)

        anyUpdate(transaction: transaction) {
            owsAssertDebug(!$0.hasMCLedgerBlockTimestamp)
            $0.mobileCoin = MobileCoinPayment.copy($0.mobileCoin, withLedgerBlockTimestamp: mcLedgerBlockTimestamp)
            owsAssertDebug($0.mobileCoin != nil)
        }
    }

    public func update(withPaymentFailure paymentFailure: TSPaymentFailure, paymentState: TSPaymentState, transaction: DBWriteTransaction) {
        owsAssertDebug(paymentFailure != .none)
        owsAssertDebug(paymentState == .incomingFailed || paymentState == .outgoingFailed)

        anyUpdate(transaction: transaction) {
            owsAssertDebug($0.paymentState.isIncoming == paymentState.isIncoming)

            $0.paymentState = paymentState
            $0.paymentFailure = paymentFailure

            // Scrub any MC state associated with the failure payment.
            $0.mobileCoin = nil
            $0.mcLedgerBlockIndex = 0
            $0.mcTransactionData = nil
            $0.mcReceiptData = nil
        }
    }

    public func update(withPaymentAmount paymentAmount: TSPaymentAmount, transaction: DBWriteTransaction) {
        anyUpdate(transaction: transaction) {
            owsAssertDebug($0.paymentAmount == nil || ($0.paymentAmount!.currency == paymentAmount.currency && $0.paymentAmount!.picoMob == paymentAmount.picoMob))
            $0.paymentAmount = paymentAmount
        }
    }

    public func update(withIsUnread isUnread: Bool, transaction: DBWriteTransaction) {
        anyUpdate(transaction: transaction) {
            $0.isUnread = isUnread
        }
    }

    public func update(withInteractionUniqueId interactionUniqueId: String, transaction: DBWriteTransaction) {
        anyUpdate(transaction: transaction) {
            $0.interactionUniqueId = interactionUniqueId
        }
    }

    public func anyWillInsert(transaction: DBWriteTransaction) {
        owsAssertDebug(self.isValid)
        SSKEnvironment.shared.paymentsEventsRef.willInsertPayment(self, transaction: transaction)
    }

    public func anyDidInsert(transaction: DBWriteTransaction) {
        owsAssertDebug(self.isValid)
    }

    public func anyWillUpdate(transaction: DBWriteTransaction) {
        owsAssertDebug(self.isValid)
        SSKEnvironment.shared.paymentsEventsRef.willUpdatePayment(self, transaction: transaction)
    }

    public func anyDidUpdate(transaction: DBWriteTransaction) {
        owsAssertDebug(self.isValid)
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(paymentModelColumn column: TSPaymentModel.CodingKeys) {
        appendLiteral(column.rawValue)
    }
}
