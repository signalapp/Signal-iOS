//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol TSPaymentBaseModel: AnyObject {
    var isValid: Bool { get }
}

// MARK: -

@objc
extension TSPaymentAmount: TSPaymentBaseModel {

    public static var zeroMob: TSPaymentAmount {
        TSPaymentAmount(currency: .mobileCoin, picoMob: 0)
    }

    public var isValid: Bool {
        isValidAmount(canBeEmpty: false)
    }

    public func isValidAmount(canBeEmpty: Bool) -> Bool {
        if canBeEmpty {
            return currency != .unknown && picoMob >= 0
        } else {
            return currency != .unknown && picoMob > 0
        }
    }

    public func buildProto() throws -> SSKProtoDataMessagePaymentAmount {
        guard isValid,
              currency == .mobileCoin else {
            throw PaymentsError.invalidModel
        }

        let mobileCoinBuilder = SSKProtoDataMessagePaymentAmountMobileCoin.builder(picoMob: picoMob)
        let builder = SSKProtoDataMessagePaymentAmount.builder()
        builder.setMobileCoin(try mobileCoinBuilder.build())
        return try builder.build()
    }

    public class func fromProto(_ proto: SSKProtoDataMessagePaymentAmount) throws -> TSPaymentAmount {
        guard let mobileCoin = proto.mobileCoin else {
            throw PaymentsError.invalidModel
        }
        let instance = TSPaymentAmount(currency: .mobileCoin,
                                       picoMob: mobileCoin.picoMob)
        guard instance.isValid else {
            throw PaymentsError.invalidModel
        }
        return instance
    }

    public func plus(_ other: TSPaymentAmount) -> TSPaymentAmount {
        owsAssertDebug(isValid)
        owsAssertDebug(other.isValid)
        owsAssertDebug(currency == .mobileCoin)
        owsAssertDebug(other.currency == .mobileCoin)

        return TSPaymentAmount(currency: currency, picoMob: self.picoMob + other.picoMob)
    }

    public var formatted: String {
        owsAssertDebug(currency == .mobileCoin)

        return "picoMob: \(picoMob)"
    }
}

// MARK: -

@objc
extension TSPaymentAddress: TSPaymentBaseModel {
    public var isValid: Bool {
        guard currency == .mobileCoin else {
            owsFailDebug("Unexpected currency.")
            return false
        }
        return SSKEnvironment.shared.payments.isValidMobileCoinPublicAddress(mobileCoinPublicAddressData)
    }

    public func buildProto() throws -> SSKProtoPaymentAddress {
        guard isValid,
              currency == .mobileCoin else {
            throw PaymentsError.invalidModel
        }

        let mobileCoinBuilder = SSKProtoPaymentAddressMobileCoin.builder(publicAddress: mobileCoinPublicAddressData)
        let builder = SSKProtoPaymentAddress.builder()
        builder.setMobileCoin(try mobileCoinBuilder.build())
        return try builder.build()
    }

    public class func fromProto(_ proto: SSKProtoPaymentAddress) throws -> TSPaymentAddress {
        guard let mobileCoin = proto.mobileCoin else {
            throw PaymentsError.invalidModel
        }
        let instance = TSPaymentAddress(currency: .mobileCoin,
                                        mobileCoinPublicAddressData: mobileCoin.publicAddress)
        guard instance.isValid else {
            throw PaymentsError.invalidModel
        }
        return instance
    }
}

// MARK: -

@objc
extension TSPaymentRequest: TSPaymentBaseModel {
    public var isValid: Bool {
        paymentAmount.isValid && paymentAmount.picoMob > 0
    }

    public func buildProto() throws -> SSKProtoDataMessagePaymentRequest {
        guard isValid else {
            throw PaymentsError.invalidModel
        }

        let requestIdBuilder = SSKProtoDataMessagePaymentRequestId.builder(uuid: requestUuidString)
        let builder = SSKProtoDataMessagePaymentRequest.builder(requestID: try requestIdBuilder.build(),
                                                                amount: try paymentAmount.buildProto())
        if let memoMessage = memoMessage {
            builder.setNote(memoMessage)
        }
        return try builder.build()
    }

    @objc(addToDataBuilder:error:)
    public func add(toDataBuilder dataBuilder: SSKProtoDataMessage.SSKProtoDataMessageBuilder) throws {
        let paymentBuilder = SSKProtoDataMessagePayment.builder()
        paymentBuilder.setRequest(try buildProto())
        dataBuilder.setPayment(try paymentBuilder.build())
    }

    public class func fromProto(_ proto: SSKProtoDataMessagePaymentRequest,
                                dataMessage: SSKProtoDataMessage) throws -> TSPaymentRequest {
        guard let requestUuidString = TSPaymentRequest.parseRequestUuidString(proto.requestID.uuid) else {
            throw PaymentsError.invalidModel
        }
        let paymentAmount = try TSPaymentAmount.fromProto(proto.amount)
        let instance = TSPaymentRequest(requestUuidString: requestUuidString,
                                        paymentAmount: paymentAmount,
                                        memoMessage: proto.note)
        guard instance.isValid else {
            throw PaymentsError.invalidModel
        }
        return instance
    }

    fileprivate static func parseRequestUuidString(_ requestIdString: String?) -> String? {
        guard let requestIdString = requestIdString else {
            return nil
        }
        guard nil != UUID(uuidString: requestIdString) else {
            owsFailDebug("Invalid requestUuidString: \(requestIdString)")
            return nil
        }
        return requestIdString
    }
}

// MARK: -

@objc
extension TSPaymentNotification: TSPaymentBaseModel {
    public var isValid: Bool {
        guard mcReceiptData.count > 0 else {
            return false
        }
        return true
    }

    public func buildProto() throws -> SSKProtoDataMessagePaymentNotification {
        guard isValid else {
            throw PaymentsError.invalidModel
        }
        let mobileCoinBuilder = SSKProtoDataMessagePaymentNotificationMobileCoin.builder(receipt: mcReceiptData)
        let builder = SSKProtoDataMessagePaymentNotification.builder()
        builder.setMobileCoin(try mobileCoinBuilder.build())
        if let requestUuidString = requestUuidString {
            let requestIdBuilder = SSKProtoDataMessagePaymentRequestId.builder(uuid: requestUuidString)
            builder.setRequestID(try requestIdBuilder.build())
        }
        if let memoMessage = memoMessage {
            builder.setNote(memoMessage)
        }
        return try builder.build()
    }

    @objc(addToDataBuilder:error:)
    public func add(toDataBuilder dataBuilder: SSKProtoDataMessage.SSKProtoDataMessageBuilder) throws {
        let paymentBuilder = SSKProtoDataMessagePayment.builder()
        paymentBuilder.setNotification(try buildProto())
        dataBuilder.setPayment(try paymentBuilder.build())
    }

    public class func fromProto(_ proto: SSKProtoDataMessagePaymentNotification,
                                dataMessage: SSKProtoDataMessage) throws -> TSPaymentNotification {
        let requestUuidString = TSPaymentRequest.parseRequestUuidString(proto.requestID?.uuid)
        guard let mobileCoin = proto.mobileCoin else {
            owsFailDebug("Missing mobileCoin.")
            throw PaymentsError.invalidModel
        }
        let mcReceiptData = mobileCoin.receipt
        let instance = TSPaymentNotification(memoMessage: proto.note,
                                             requestUuidString: requestUuidString,
                                             mcReceiptData: mcReceiptData)
        guard instance.isValid else {
            throw PaymentsError.invalidModel
        }
        return instance
    }
}

// MARK: -

@objc
extension TSPaymentCancellation: TSPaymentBaseModel {
    public var isValid: Bool {
        true
    }

    public func buildProto() throws -> SSKProtoDataMessagePaymentCancellation {
        guard isValid else {
            throw PaymentsError.invalidModel
        }

        let requestIdBuilder = SSKProtoDataMessagePaymentRequestId.builder(uuid: requestUuidString)
        let builder = SSKProtoDataMessagePaymentCancellation.builder(requestID: try requestIdBuilder.build())
        return try builder.build()
    }

    @objc(addToDataBuilder:error:)
    public func add(toDataBuilder dataBuilder: SSKProtoDataMessage.SSKProtoDataMessageBuilder) throws {
        let paymentBuilder = SSKProtoDataMessagePayment.builder()
        paymentBuilder.setCancellation(try buildProto())
        dataBuilder.setPayment(try paymentBuilder.build())
    }

    public class func fromProto(_ proto: SSKProtoDataMessagePaymentCancellation) throws -> TSPaymentCancellation {
        guard let requestUuidString = TSPaymentRequest.parseRequestUuidString(proto.requestID.uuid) else {
            throw PaymentsError.invalidModel
        }
        let instance = TSPaymentCancellation(requestUuidString: requestUuidString)
        guard instance.isValid else {
            throw PaymentsError.invalidModel
        }
        return instance
    }
}

// MARK: -

@objc
public class TSPaymentModels: NSObject {

    // MARK: - Dependencies

    private class var payments: PaymentsSwift {
        SSKEnvironment.shared.payments as! PaymentsSwift
    }

    // MARK: -

    @objc
    public var request: TSPaymentRequest?

    @objc
    public var notification: TSPaymentNotification?

    @objc
    public var cancellation: TSPaymentCancellation?

    private init(request: TSPaymentRequest? = nil,
                 notification: TSPaymentNotification? = nil,
                 cancellation: TSPaymentCancellation? = nil) {
        assert(request != nil || notification != nil || cancellation != nil)

        self.request = request
        self.notification = notification
        self.cancellation = cancellation
    }

    @objc(parsePaymentProtosInDataMessage:thread:)
    public class func parsePaymentProtos(dataMessage: SSKProtoDataMessage,
                                         thread: TSThread) -> TSPaymentModels? {
        guard FeatureFlags.payments,
              payments.arePaymentsEnabled else {
            return nil
        }
        guard let paymentProto = dataMessage.payment else {
            return nil
        }
        owsAssertDebug(DebugFlags.paymentsOnlyInContactThreads)
        guard nil != thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return nil
        }
        do {
            if FeatureFlags.paymentsRequests,
               let requestProto = paymentProto.request {
                let request = try TSPaymentRequest.fromProto(requestProto,
                                                             dataMessage: dataMessage)
                if request.isValid {
                    return TSPaymentModels(request: request)
                } else {
                    owsFailDebug("Invalid payment request proto.")
                }
            }
            if let notificationProto = paymentProto.notification {
                let notification = try TSPaymentNotification.fromProto(notificationProto,
                                                                       dataMessage: dataMessage)
                if notification.isValid {
                    return TSPaymentModels(notification: notification)
                } else {
                    owsFailDebug("Invalid payment notification proto.")
                }
            }
            if FeatureFlags.paymentsRequests,
               let cancellationProto = paymentProto.cancellation {
                let cancellation = try TSPaymentCancellation.fromProto(cancellationProto)
                if cancellation.isValid {
                    return TSPaymentModels(cancellation: cancellation)
                } else {
                    owsFailDebug("Invalid payment cancellation proto.")
                }
            }
            owsFailDebug("Empty payment proto.")
        } catch {
            owsFailDebug("Error: \(error)")
        }
        return nil
    }
}

// MARK: -

@objc
public extension TSPaymentModel {

    // We need to be cautious when updating the state of payment records,
    // to avoid races.
    @objc(isCurrentPaymentState:transaction:)
    func isCurrentPaymentState(paymentState: TSPaymentState, transaction: SDSAnyReadTransaction) -> Bool {
        guard self.paymentState == paymentState else {
            owsFailDebug("Payment model in memory has unexpected state: \(self.paymentState.formatted) != expected: \(paymentState.formatted)")
            return false
        }
        guard let latestModel = TSPaymentModel.anyFetch(uniqueId: self.uniqueId, transaction: transaction) else {
            owsFailDebug("Payment model no longer exists.")
            return false
        }
        guard latestModel.paymentState == paymentState else {
            owsFailDebug("Payment model in database has unexpected state: \(latestModel.paymentState.formatted) != expected: \(paymentState.formatted)")
            return false
        }
        return true
    }

    // We need to be cautious when updating the state of payment records,
    // to avoid races.
    func updatePaymentModelState(fromState: TSPaymentState,
                                 toState: TSPaymentState,
                                 transaction: SDSAnyWriteTransaction) throws {
        Logger.verbose("[\(uniqueId)] fromState: \(fromState.formatted) -> toState: \(toState.formatted)")
        guard isCurrentPaymentState(paymentState: fromState, transaction: transaction) else {
            throw OWSAssertionError("Payment model has unexpected state.")
        }
        self.update(paymentState: toState, transaction: transaction)
    }
}

// MARK: -

@objc
extension TSPaymentModel: TSPaymentBaseModel {

    public var isValid: Bool {
        var isValid = true

        let formattedState = descriptionForLogs

        if isIncoming != paymentState.isIncoming {
            Logger.verbose("isIncoming: \(isIncoming), paymentState.isIncoming: \(paymentState.isIncoming), ")
            owsFailDebug("Invalid payment: \(formattedState).")
            isValid = false
        }

        let hasFailedPaymentState = (paymentState == .incomingFailed || paymentState == .outgoingFailed)
        let hasFailureType = paymentFailure != .none
        if hasFailedPaymentState, !hasFailureType {
            owsFailDebug("Failed payment state: \(formattedState), no paymentFailure: \(paymentFailure.formatted).")
            isValid = false
        } else if !hasFailedPaymentState, hasFailureType {
            owsFailDebug("Payment state: \(formattedState), unexpected paymentFailure: \(paymentFailure.formatted).")
            isValid = false
        }

        if let paymentAmount = paymentAmount {
            if !paymentAmount.isValidAmount(canBeEmpty: false) {
                owsFailDebug("Invalid paymentAmount: \(formattedState).")
                isValid = false
            }
        } else {
            let shouldHavePaymentAmount = paymentState != .incomingUnverified && !isFailed
            if shouldHavePaymentAmount {
                owsFailDebug("Missing paymentAmount: \(formattedState).")
                isValid = false
            }
        }

        if let feeAmount = mobileCoin?.feeAmount {
            if !feeAmount.isValidAmount(canBeEmpty: false) {
                owsFailDebug("Invalid feeAmount: \(formattedState).")
                isValid = false
            }
        } else {
            let shouldHaveFeeAmount = !isUnidentified && isOutgoing && !isFailed
            if shouldHaveFeeAmount {
                owsFailDebug("Missing feeAmount: \(formattedState).")
                isValid = false
            }
        }

        if !isUnidentified, !isOutgoingTransfer, addressUuidString == nil {
            owsFailDebug("Missing addressUuidString: \(formattedState).")
            isValid = false
        }

        let shouldHaveMCReceiptData = isIncoming && !isUnidentified && !isFailed
        if shouldHaveMCReceiptData, mcReceiptData == nil {
            owsFailDebug("Missing mcReceiptData: \(formattedState).")
            isValid = false
        }

        let shouldHaveMCRecipientPublicAddressData = isOutgoing && !isUnidentified
        if shouldHaveMCRecipientPublicAddressData, mcRecipientPublicAddressData == nil {
            // This is valid for payments sent from a linked device.
            //
            // TODO: ?
            Logger.warn("Missing mcRecipientPublicAddressData: \(formattedState).")
        }

        let shouldHaveMCTransaction = isOutgoing && !isUnidentified
        if shouldHaveMCTransaction, mcTransactionData == nil {
            // This is valid for payments sent from a linked device.
            //
            // TODO: ?
            Logger.warn("Missing mcTransactionData: \(formattedState).")
        }

        let shouldHaveMCReceipt = isIncoming && !isUnidentified && !isFailed
        if shouldHaveMCReceipt, mcReceiptData == nil {
            owsFailDebug("Missing mcReceiptData: \(formattedState).")
            isValid = false
        }

        let shouldHaveMCIncomingTransaction = isIncoming && !isFailed
        if shouldHaveMCIncomingTransaction, !hasMCIncomingTransaction {
            owsFailDebug("Missing mcIncomingTransaction: \(formattedState).")
            isValid = false
        } else if !shouldHaveMCIncomingTransaction, hasMCIncomingTransaction {
            owsFailDebug("Unexpected mcIncomingTransaction: \(formattedState).")
            isValid = false
        }

        let shouldHaveRecipient = !isUnidentified && isOutgoing
        let hasRecipient = addressUuidString != nil || mcRecipientPublicAddressData != nil
        if shouldHaveRecipient, !hasRecipient {
            owsFailDebug("Missing recipient: \(formattedState).")
            isValid = false
        }

        let shouldHaveMCSpentKeyImages = isOutgoing
        if shouldHaveMCSpentKeyImages,
           mcSpentKeyImages == nil {
            owsFailDebug("Missing mcSpentKeyImages: \(formattedState).")
            isValid = false
        } else if !shouldHaveMCSpentKeyImages,
                  mcSpentKeyImages != nil {
            owsFailDebug("Unexpected mcSpentKeyImages: \(formattedState).")
            isValid = false
        }

        let canHaveMCOutputPublicKeys = isOutgoing
        let shouldHaveMCOutputPublicKeys = isOutgoing && !isUnidentified
        if shouldHaveMCOutputPublicKeys,
           mcOutputPublicKeys == nil {
            owsFailDebug("Missing mcOutputPublicKeys: \(formattedState).")
            isValid = false
        } else if !canHaveMCOutputPublicKeys,
                  mcOutputPublicKeys != nil {
            owsFailDebug("Unexpected mcOutputPublicKeys: \(formattedState).")
            isValid = false
        }

        let shouldHaveMCLedgerBlockTimestamp = isComplete
        if shouldHaveMCLedgerBlockTimestamp,
           !hasMCLedgerBlockTimestamp {
            // For some payments, we'll never be able to fill in the block timestamp.
            Logger.warn("Missing mcLedgerBlockTimestamp: \(formattedState).")
        }

        let shouldHaveMCLedgerBlockIndex = isVerified || isUnidentified
        if shouldHaveMCLedgerBlockIndex,
           !hasMCLedgerBlockIndex {
            owsFailDebug("Missing mcLedgerBlockIndex: \(formattedState).")
            isValid = false
        }

        return isValid
    }

    public var isComplete: Bool {
        switch paymentState {
        case .outgoingComplete,
             .incomingComplete:
            return true
        default:
            return false
        }
    }

    public var isFailed: Bool {
        switch paymentState {
        case .outgoingFailed,
             .incomingFailed:
            return true
        default:
            return false
        }
    }

    public var isVerified: Bool {
        switch paymentState {
        case .outgoingUnsubmitted,
             .outgoingUnverified:
            return false
        case .outgoingVerified,
             .outgoingSending,
             .outgoingSent,
             .outgoingMissingLedgerTimestamp,
             .outgoingComplete:
            return true
        case .outgoingFailed:
            return false
        case .incomingUnverified:
            return false
        case .incomingVerified,
             .incomingMissingLedgerTimestamp,
             .incomingComplete:
            return true
        case .incomingFailed:
            return false
        @unknown default:
            owsFailDebug("Unknown payment state.")
            return false
        }
    }

    public var isIncoming: Bool {
        paymentType.isIncoming
    }

    public var isOutgoingTransfer: Bool {
        paymentType == .outgoingTransfer
    }

    public var isOutgoing: Bool {
        !isIncoming
    }

    public var isIdentifiedPayment: Bool {
        paymentType.isIdentifiedPayment
    }

    public var isUnidentified: Bool {
        paymentType.isUnidentified
    }

    public var hasMCIncomingTransaction: Bool {
        if let mcIncomingTransaction = mcIncomingTransaction,
           !mcIncomingTransaction.isEmpty {
            return true
        } else {
            return false
        }
    }

    public var hasMCLedgerBlockIndex: Bool {
        mcLedgerBlockIndex > 0
    }

    public var hasMCLedgerBlockTimestamp: Bool {
        mcLedgerBlockTimestamp > 0
    }

    // Only set for outgoing mobileCoin payments.
    //
    // This only applies to mobilecoin.
    public var mcRecipientPublicAddressData: Data? {
        mobileCoin?.recipientPublicAddressData
    }

    // Only set for outgoing mobileCoin payments.
    //
    // This only applies to mobilecoin.
    public var mcTransactionData: Data? {
        mobileCoin?.transactionData
    }

    // This only applies to mobilecoin.
    public var mcReceiptData: Data? {
        mobileCoin?.receiptData
    }

    // Only set for outgoing mobileCoin payments.
    //
    // This only applies to mobilecoin.
    public var mcSpentKeyImages: [Data]? {
        mobileCoin?.spentKeyImages
    }

    // Only set for outgoing mobileCoin payments.
    //
    // This only applies to mobilecoin.
    public var mcOutputPublicKeys: [Data]? {
        mobileCoin?.outputPublicKeys
    }

    // This only applies to mobilecoin.
    public var mcLedgerBlockTimestamp: UInt64 {
        mobileCoin?.ledgerBlockTimestamp ?? 0
    }

    // This only applies to mobilecoin.
    public var mcLedgerBlockDate: Date? {
        if mcLedgerBlockTimestamp != 0 {
            return NSDate.ows_date(withMillisecondsSince1970: mcLedgerBlockTimestamp)
        }
        return nil
    }

    public var descriptionForLogs: String {
        DebugFlags.internalLogging ? descriptionInternal : descriptionProduction
    }

    public var descriptionInternal: String {
        buildDescription(isForProduction: false)
    }

    public var descriptionProduction: String {
        buildDescription(isForProduction: true)
    }

    private func buildDescription(isForProduction: Bool) -> String {
        var components = [String]()
        components.append("paymentType: \(paymentType.formatted)")
        components.append("paymentState: \(paymentState.formatted)")
        if isFailed {
            components.append("paymentFailure: \(paymentFailure.formatted)")
        }
        if !isForProduction {
            if let paymentAmount = paymentAmount {
                components.append("paymentAmount: \(paymentAmount.formatted)")
            }

            if let address = address {
                components.append("address: \(address)")
            }
            if let memoMessage = memoMessage {
                components.append("memoMessage: '\(memoMessage)'")
            }
        }
        return "[" + components.joined(separator: ", ") + "]"
    }
}

// MARK: -

@objc
extension TSPaymentRequestModel: TSPaymentBaseModel {
    public var isValid: Bool {
        paymentAmount.isValid && paymentAmount.picoMob > 0
    }
}

// MARK: - DeepCopyable

extension TSPaymentAmount: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        try TSPaymentAmount(dictionary: self.dictionaryValue)
    }
}

// MARK: -

public extension Array where Element == TSPaymentModel {
    private func sortBySortDateBlock(descending: Bool) -> (TSPaymentModel, TSPaymentModel) -> Bool {
        return { (left, right) -> Bool in
            if descending {
                return left.sortDate > right.sortDate
            } else {
                return left.sortDate < right.sortDate
            }
        }
    }

    func sortedBySortDate(descending: Bool) -> [TSPaymentModel] {
        sorted(by: sortBySortDateBlock(descending: descending))
    }

    mutating func sortBySortDate(descending: Bool) {
        sort(by: sortBySortDateBlock(descending: descending))
    }
}

// MARK: -

extension TSPaymentState {
    public var isIncoming: Bool {
        switch self {
        case .outgoingUnsubmitted,
             .outgoingUnverified,
             .outgoingVerified,
             .outgoingSending,
             .outgoingSent,
             .outgoingMissingLedgerTimestamp,
             .outgoingComplete,
             .outgoingFailed:
            return false
        case .incomingUnverified,
             .incomingVerified,
             .incomingMissingLedgerTimestamp,
             .incomingComplete,
             .incomingFailed:
            return true
        @unknown default:
            owsFailDebug("Unknown value: \(rawValue)")
            return false
        }
    }

    public var formatted: String {
        NSStringFromTSPaymentState(self)
    }
}

// MARK: -

extension TSPaymentType {
    public var isIncoming: Bool {
        switch self {
        case .incomingPayment,
             .incomingUnidentified:
            return true
        case .outgoingPayment,
             .outgoingUnidentified,
             .outgoingTransfer:
            return false
        @unknown default:
            owsFailDebug("Invalid value: \(rawValue)")
            return false
        }
    }

    public var isIdentifiedPayment: Bool {
        switch self {
        case .incomingPayment,
             .outgoingPayment:
            return true
        case .incomingUnidentified,
             .outgoingUnidentified,
             .outgoingTransfer:
            return false
        @unknown default:
            owsFailDebug("Invalid value: \(rawValue)")
            return false
        }
    }

    public var isUnidentified: Bool {
        switch self {
        case .incomingUnidentified,
             .outgoingUnidentified:
            return true
        case .incomingPayment,
             .outgoingPayment,
             .outgoingTransfer:
            return false
        @unknown default:
            owsFailDebug("Invalid value: \(rawValue)")
            return false
        }
    }

    public var formatted: String {
        NSStringFromTSPaymentType(self)
    }
}

// MARK: -

extension TSPaymentFailure {
    public var formatted: String {
        NSStringFromTSPaymentFailure(self)
    }
}

// MARK: -

@objc
@available(swift, obsoleted: 1.0)
public class PaymentUtils: NSObject {

    @available(*, unavailable, message:"Do not instantiate this class.")
    private override init() {}

    @objc
    public static func isIncomingPaymentState(_ value: TSPaymentState) -> Bool {
        value.isIncoming
    }

    @objc
    public static func isIncomingPaymentType(_ value: TSPaymentType) -> Bool {
        value.isIncoming
    }
}
