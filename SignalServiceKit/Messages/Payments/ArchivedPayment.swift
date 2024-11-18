//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient
public import GRDB

public struct ArchivedPayment: Codable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "ArchivedPayment"

    public enum CodingKeys: String, CodingKey {
        case id
        case amount
        case fee
        case note
        case mobileCoinIdentification
        case status
        case failureReason
        case direction
        case timestamp
        case blockIndex
        case blockTimestamp
        case transaction
        case receipt
        case _senderOrRecipientAci = "senderOrRecipientAci"
        case interactionUniqueId
    }

    public var id: Int64?
    public var amount: String?
    public var fee: String?
    public var note: String?
    public let mobileCoinIdentification: TransactionIdentifier?
    public let status: Status
    public let failureReason: FailureReason
    public let direction: Direction
    public let timestamp: UInt64?
    public let blockIndex: UInt64?
    public let blockTimestamp: UInt64?
    public let transaction: Data?
    public let receipt: Data?
    private let _senderOrRecipientAci: UUID?
    public let interactionUniqueId: String?

    public var senderOrRecipientAci: Aci? {
        _senderOrRecipientAci.map { Aci(fromUUID: $0) }
    }

    public init(
        amount: String?,
        fee: String?,
        note: String?,
        mobileCoinIdentification: TransactionIdentifier?,
        status: Status,
        failureReason: FailureReason,
        direction: Direction,
        timestamp: UInt64?,
        blockIndex: UInt64?,
        blockTimestamp: UInt64?,
        transaction: Data?,
        receipt: Data?,
        senderOrRecipientAci: Aci?,
        interactionUniqueId: String?
    ) {
        self.amount = amount
        self.fee = fee
        self.note = note
        self.mobileCoinIdentification = mobileCoinIdentification
        self.status = status
        self.failureReason = failureReason
        self.direction = direction
        self.timestamp = timestamp
        self.blockIndex = blockIndex
        self.blockTimestamp = blockTimestamp
        self.transaction = transaction
        self.receipt = receipt
        self._senderOrRecipientAci = senderOrRecipientAci?.rawUUID
        self.interactionUniqueId = interactionUniqueId
    }

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    public enum Direction: Int, Codable {
        case unknown = 0
        case incoming = 1
        case outgoing = 2
    }

    public enum Status: Int, Codable {
        case error = 0
        case initial = 1
        case submitted = 2
        case successful = 3

        public var isFailure: Bool {
            return self == .error
        }
    }

    public enum FailureReason: Int, Codable {
        case none = 0
        case genericFailure = 1
        case networkFailure = 2
        case insufficientFundsFailure = 3
    }

    public struct TransactionIdentifier: Codable, Hashable {
        public let publicKey: [Data]?
        public let keyImages: [Data]?
    }
}

extension ArchivedPayment {
    func toTransactionDetailsProto() -> BackupProto_PaymentNotification.TransactionDetails {
        var transactionDetails = BackupProto_PaymentNotification.TransactionDetails()

        if status.isFailure {
            let reason: BackupProto_PaymentNotification.TransactionDetails.FailedTransaction.FailureReason = {
                switch failureReason {
                case .genericFailure: return .generic
                case .networkFailure: return .network
                case .insufficientFundsFailure: return .insufficientFunds
                case .none:
                    owsFailDebug("Invalid status for failure type")
                    return .generic
                }
            }()

            var failedTransaction = BackupProto_PaymentNotification.TransactionDetails.FailedTransaction()
            failedTransaction.reason = reason

            transactionDetails.payment = .failedTransaction(failedTransaction)
        } else {
            let success: BackupProto_PaymentNotification.TransactionDetails.Transaction.Status = {
                switch status {
                case .initial: return .initial
                case .submitted: return .submitted
                case .successful: return .successful
                case .error:
                    owsFailDebug("Invalid status for success type")
                    return .successful
                }
            }()

            var transaction = BackupProto_PaymentNotification.TransactionDetails.Transaction()
            transaction.status = success

            var identification = BackupProto_PaymentNotification.TransactionDetails.MobileCoinTxoIdentification()
            switch direction {
            case .incoming:
                if let publicKey = mobileCoinIdentification?.publicKey {
                    identification.publicKey = publicKey
                }
            case .outgoing:
                if let keyImages = mobileCoinIdentification?.keyImages {
                    identification.keyImages = keyImages
                }
            case .unknown:
                owsFailDebug("Direction of payment not specified.")
            }
            transaction.mobileCoinIdentification = identification

            if let timestamp { transaction.timestamp = timestamp }
            if let blockIndex { transaction.blockIndex = blockIndex }
            if let blockTimestamp { transaction.blockTimestamp = blockTimestamp }
            if let _transaction = self.transaction { transaction.transaction = _transaction }
            if let receipt { transaction.receipt = receipt }

            transactionDetails.payment = .transaction(transaction)
        }

        return transactionDetails
    }
}

extension TSPaymentModel {
    func asArchivedPayment() -> ArchivedPayment {

        var identifier: ArchivedPayment.TransactionIdentifier?
        if let incomingTransactionPublicKeys = mobileCoin?.incomingTransactionPublicKeys {
            identifier = ArchivedPayment.TransactionIdentifier(
                publicKey: incomingTransactionPublicKeys,
                keyImages: nil
            )
        } else if (mcOutputPublicKeys?.nilIfEmpty != nil || mcSpentKeyImages?.nilIfEmpty != nil) {
            if (mcOutputPublicKeys?.nilIfEmpty == nil || mcSpentKeyImages?.nilIfEmpty == nil) {
                owsFailDebug("one of public Keys or spent keys is nil")
                identifier = nil
            } else {
                identifier = ArchivedPayment.TransactionIdentifier(
                    publicKey: nil,
                    keyImages: mcSpentKeyImages
                )
            }
        }

        let status: ArchivedPayment.Status = {
            guard !isFailed else { return .error }
            switch paymentState {
            case .incomingComplete,
                    .incomingVerified,
                    .incomingUnverified,
                    .outgoingComplete,
                    .outgoingVerified,
                    .outgoingUnverified:
                return .successful
            case .outgoingSent,
                    .outgoingSending:
                return .submitted
            case .outgoingUnsubmitted:
                return .initial
            case .incomingFailed,
                    .outgoingFailed:
                owsFailDebug("Invalid failure state in success path")
                return .initial
            @unknown default:
                owsFailDebug("Encountered invalid payment state")
                return .initial
            }
        }()

        let failureReason: ArchivedPayment.FailureReason = {
            guard isFailed else { return .none }
            switch paymentFailure {
            case .insufficientFunds:
                return .insufficientFundsFailure
            case .notificationSendFailed:
                return .networkFailure
            case .expired,
                    .invalid,
                    .validationFailed,
                    .unknown,
                    .none:
                return .genericFailure
            @unknown default:
                owsFailDebug("Encountered invalid payment state")
                return .genericFailure
            }
        }()

        let direction: ArchivedPayment.Direction = {
            switch paymentState {
            case .incomingComplete,
                 .incomingVerified,
                 .incomingUnverified,
                 .incomingFailed,
                 .outgoingFailed:
                return .incoming
            case .outgoingComplete,
                 .outgoingVerified,
                 .outgoingUnverified,
                 .outgoingUnsubmitted,
                 .outgoingSent,
                 .outgoingSending:
                return .outgoing
            @unknown default:
                owsFailDebug("Encountered invalid payment state")
                return .unknown
            }
        }()

        let formattedAmount = paymentAmount.map {PaymentsFormat.format(paymentAmount: $0, isShortForm: true)}
        let formattedFee = mobileCoin?.feeAmount.map {PaymentsFormat.format(paymentAmount: $0, isShortForm: true)}

        return ArchivedPayment(
            amount: formattedAmount,
            fee: formattedFee,
            note: memoMessage,
            mobileCoinIdentification: identifier,
            status: status,
            failureReason: failureReason,
            direction: direction,
            timestamp: createdTimestamp,
            blockIndex: mcLedgerBlockIndex,
            blockTimestamp: mcLedgerBlockTimestamp,
            transaction: mcTransactionData,
            receipt: mcReceiptData,
            senderOrRecipientAci: senderOrRecipientAci?.wrappedAciValue,
            interactionUniqueId: interactionUniqueId
        )
    }
}
