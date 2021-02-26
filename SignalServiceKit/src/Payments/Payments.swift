//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum PaymentsError: Error {
    case userHasNoPublicAddress
    case invalidSignature
    case invalidCurrency
    case invalidWalletKey
    case invalidAmount
    case invalidFee
    case insufficientFunds
    case timeout
    case userNotRegisteredOrAppNotReady
    case invalidModel
    case notEnabled
    case unknownCurrency
    case tooOldToSubmit
    case indeterminateState
}

// MARK: -

@objc
public protocol Payments: AnyObject {

    func walletAddressBase58() -> String?

    func walletAddressQRUrl() -> URL?

    func localPaymentAddressProtoData() -> Data?

    var arePaymentsEnabled: Bool { get }

    var mcRootEntropy: Data? { get }

    func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool

    func setArePaymentsEnabled(for address: SignalServiceAddress, hasPaymentsEnabled: Bool, transaction: SDSAnyWriteTransaction)
    func arePaymentsEnabled(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool

    func processIncomingPaymentRequest(thread: TSThread,
                                       paymentRequest: TSPaymentRequest,
                                       transaction: SDSAnyWriteTransaction)

    func processIncomingPaymentNotification(thread: TSThread,
                                            paymentNotification: TSPaymentNotification,
                                            senderAddress: SignalServiceAddress,
                                            transaction: SDSAnyWriteTransaction)

    func processIncomingPaymentCancellation(thread: TSThread,
                                            paymentCancellation: TSPaymentCancellation,
                                            transaction: SDSAnyWriteTransaction)

    func processReceivedTranscriptPaymentRequest(thread: TSThread,
                                                 paymentRequest: TSPaymentRequest,
                                                 messageTimestamp: UInt64,
                                                 transaction: SDSAnyWriteTransaction)

    func processReceivedTranscriptPaymentNotification(thread: TSThread,
                                                      paymentNotification: TSPaymentNotification,
                                                      messageTimestamp: UInt64,
                                                      transaction: SDSAnyWriteTransaction)

    func processReceivedTranscriptPaymentCancellation(thread: TSThread,
                                                      paymentCancellation: TSPaymentCancellation,
                                                      messageTimestamp: UInt64,
                                                      transaction: SDSAnyWriteTransaction)

    func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction)
    func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction)

    @objc(processIncomingPaymentSyncMessage:messageTimestamp:transaction:)
    func processIncomingPaymentSyncMessage(_ paymentProto: SSKProtoSyncMessageOutgoingPayment,
                                           messageTimestamp: UInt64,
                                           transaction: SDSAnyWriteTransaction)

    func scheduleReconciliationNow(transaction: SDSAnyWriteTransaction)

    func replaceAsUnidentified(paymentModel oldPaymentModel: TSPaymentModel,
                               transaction: SDSAnyWriteTransaction)

    func warmCaches()
}

// MARK: -

public protocol PaymentsSwift: Payments {

    var paymentsState: PaymentsState { get }
    func setPaymentsState(_ value: PaymentsState, transaction: SDSAnyWriteTransaction)
    func generateRandomMobileCoinRootEntropy() -> Data

    var currentPaymentBalance: PaymentBalance? { get }
    func updateCurrentPaymentBalance()
    func updateCurrentPaymentBalancePromise() -> Promise<TSPaymentAmount>

    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<TSPaymentAmount>

    func submitPaymentTransaction(recipient: SendPaymentRecipient,
                                  paymentAmount: TSPaymentAmount,
                                  memoMessage: String?,
                                  paymentRequestModel: TSPaymentRequestModel?,
                                  isOutgoingTransfer: Bool) -> Promise<TSPaymentModel>
}

// MARK: -

public protocol SendPaymentRecipient {
    var address: SignalServiceAddress? { get }
}

// MARK: -

public struct PaymentBalance {
    public let amount: TSPaymentAmount
    public let date: Date

    public init(amount: TSPaymentAmount, date: Date) {
        self.amount = amount
        self.date = date
    }
}

// MARK: -

public enum PaymentsState: Equatable {
    case disabled
    case enabled(mcRootEntropy: Data)
    case disabledWithMCRootEntropy(mcRootEntropy: Data)

    public static func build(arePaymentsEnabled: Bool, mcRootEntropy: Data?) -> PaymentsState {
        guard let mcRootEntropy = mcRootEntropy else {
            return .disabled
        }
        if arePaymentsEnabled {
            return .enabled(mcRootEntropy: mcRootEntropy)
        } else {
            return .disabledWithMCRootEntropy(mcRootEntropy: mcRootEntropy)
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .enabled:
            return true
        case .disabled, .disabledWithMCRootEntropy:
            return false
        }
    }

    public var mcRootEntropy: Data? {
        switch self {
        case .enabled(let mcRootEntropy):
            return mcRootEntropy
        case .disabled:
            return nil
        case .disabledWithMCRootEntropy(let mcRootEntropy):
            return mcRootEntropy
        }
    }

    // MARK: Equatable

    public static func == (lhs: PaymentsState, rhs: PaymentsState) -> Bool {
        return (lhs.isEnabled == rhs.isEnabled &&
                    lhs.mcRootEntropy == rhs.mcRootEntropy)
    }
}

// MARK: -

public class MockPayments: NSObject {
}

// MARK: -

extension MockPayments: PaymentsSwift {

    public var paymentsState: PaymentsState { .disabled }

    public func setPaymentsState(_ value: PaymentsState, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func generateRandomMobileCoinRootEntropy() -> Data {
        owsFail("Not implemented.")
    }

    public var arePaymentsEnabled: Bool {
        owsFail("Not implemented.")
    }

    public var mcRootEntropy: Data? { nil }

    public func walletAddressBase58() -> String? {
        owsFail("Not implemented.")
    }

    public func walletAddressQRUrl() -> URL? {
        owsFail("Not implemented.")
    }

    public func localPaymentAddressProtoData() -> Data? {
        owsFail("Not implemented.")
    }

    public func warmCaches() {
        owsFail("Not implemented.")
    }

    public var currentPaymentBalance: PaymentBalance? {
        owsFail("Not implemented.")
    }

    public func updateCurrentPaymentBalance() {
        owsFail("Not implemented.")
    }

    public func updateCurrentPaymentBalancePromise() -> Promise<TSPaymentAmount> {
        owsFail("Not implemented.")
    }

    public func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<TSPaymentAmount> {
        owsFail("Not implemented.")
    }

    public func submitPaymentTransaction(recipient: SendPaymentRecipient,
                                         paymentAmount: TSPaymentAmount,
                                         memoMessage: String?,
                                         paymentRequestModel: TSPaymentRequestModel?,
                                         isOutgoingTransfer: Bool) -> Promise<TSPaymentModel> {
        owsFail("Not implemented.")
    }

    public func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool {
        owsFail("Not implemented.")
    }

    public func setArePaymentsEnabled(for address: SignalServiceAddress, hasPaymentsEnabled: Bool, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func arePaymentsEnabled(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentRequest(thread: TSThread,
                                              paymentRequest: TSPaymentRequest,
                                              transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentNotification(thread: TSThread,
                                                   paymentNotification: TSPaymentNotification,
                                                   senderAddress: SignalServiceAddress,
                                                   transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentCancellation(thread: TSThread,
                                                   paymentCancellation: TSPaymentCancellation,
                                                   transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processReceivedTranscriptPaymentRequest(thread: TSThread,
                                                        paymentRequest: TSPaymentRequest,
                                                        messageTimestamp: UInt64,
                                                        transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processReceivedTranscriptPaymentNotification(thread: TSThread,
                                                             paymentNotification: TSPaymentNotification,
                                                             messageTimestamp: UInt64,
                                                             transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processReceivedTranscriptPaymentCancellation(thread: TSThread,
                                                             paymentCancellation: TSPaymentCancellation,
                                                             messageTimestamp: UInt64,
                                                             transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentSyncMessage(_ paymentProto: SSKProtoSyncMessageOutgoingPayment,
                                                  messageTimestamp: UInt64,
                                                  transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func scheduleReconciliationNow(transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func replaceAsUnidentified(paymentModel oldPaymentModel: TSPaymentModel,
                                      transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }
}

// MARK: -

@objc
public protocol PaymentsCurrencies: AnyObject {

    typealias CurrencyCode = String

    // Expressed as a ratio:
    //
    // price of fiat currency / price of payment currency (MobileCoin)
    typealias CurrencyConversionRate = Double

    var currentCurrencyCode: CurrencyCode { get }

    func setCurrentCurrencyCode(_ currencyCode: CurrencyCode, transaction: SDSAnyWriteTransaction)

    func updateConversationRatesIfStale()

    func warmCaches()
}

// MARK: -

public protocol PaymentsCurrenciesSwift: PaymentsCurrencies {

    var preferredCurrencyInfos: [CurrencyInfo] { get }

    var supportedCurrencyInfos: [CurrencyInfo] { get }

    var supportedCurrencyInfosWithCurrencyConversions: [CurrencyInfo] { get }

    func conversionInfo(forCurrencyCode currencyCode: CurrencyCode) -> CurrencyConversionInfo?
}

// MARK: -

public class PaymentsConstants {

    @available(*, unavailable, message:"Do not instantiate this class.")
    private init() {}

    // PAYMENTS TODO: Use SDK constant?
    @objc
    public static let picoMobPerMob: UInt64 = 1000 * 1000 * 1000 * 1000

    @objc
    public static let mobileCoinCurrencyIdentifier = "MOB"

    public static func convertMobToPicoMob(_ mob: Double) -> UInt64 {
        UInt64(round(mob * Double(picoMobPerMob)))
    }

    public static func convertPicoMobToMob(_ picoMob: UInt64) -> Double {
        Double(picoMob) / Double(picoMobPerMob)
    }
}

// MARK: -

public struct CurrencyInfo {
    public let currencyCode: PaymentsCurrencies.CurrencyCode
    public let name: String

    public init(currencyCode: PaymentsCurrencies.CurrencyCode, name: String) {
        self.currencyCode = currencyCode
        self.name = name
    }
}

// MARK: -

public struct CurrencyConversionInfo {
    public let currencyCode: PaymentsCurrencies.CurrencyCode
    public let name: String
    // Don't use this field; use convertToFiatCurrency() instead.
    private let conversionRate: PaymentsCurrencies.CurrencyConversionRate
    // How fresh is this conversion info?
    public let conversionDate: Date

    public init(currencyCode: PaymentsCurrencies.CurrencyCode,
                name: String,
                conversionRate: PaymentsCurrencies.CurrencyConversionRate,
                conversionDate: Date) {
        self.currencyCode = currencyCode
        self.name = name
        self.conversionRate = conversionRate
        self.conversionDate = conversionDate
    }

    public func convertToFiatCurrency(paymentAmount: TSPaymentAmount) -> Double? {
        guard paymentAmount.currency == .mobileCoin else {
            owsFailDebug("Unknown currency: \(paymentAmount.currency).")
            return nil
        }
        let mob = PaymentsConstants.convertPicoMobToMob(paymentAmount.picoMob)
        return conversionRate * mob
    }

    public func convertFromFiatCurrencyToMOB(_ value: Double) -> TSPaymentAmount {
        guard value >= 0 else {
            owsFailDebug("Invalid amount: \(value).")
            return TSPaymentAmount(currency: .mobileCoin, picoMob: 0)
        }
        let mob = value / conversionRate
        let picoMob = PaymentsConstants.convertMobToPicoMob(mob)
        return TSPaymentAmount(currency: .mobileCoin, picoMob: picoMob)
    }

    public var asCurrencyInfo: CurrencyInfo {
        CurrencyInfo(currencyCode: currencyCode, name: name)
    }

    public static func areEqual(_ left: CurrencyConversionInfo?,
                                _ right: CurrencyConversionInfo?) -> Bool {
        return (left?.currencyCode == right?.currencyCode &&
                    left?.conversionRate == right?.conversionRate)
    }
}

// MARK: -

public class MockPaymentsCurrencies: NSObject, PaymentsCurrenciesSwift {

    public let currentCurrencyCode: CurrencyCode = "USD"

    public func setCurrentCurrencyCode(_ currencyCode: PaymentsCurrencies.CurrencyCode, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func warmCaches() {}

    public let preferredCurrencyInfos: [CurrencyInfo] = []

    public let supportedCurrencyInfos: [CurrencyInfo] = []

    public let supportedCurrencyInfosWithCurrencyConversions: [CurrencyInfo] = []

    public func updateConversationRatesIfStale() {}

    public func conversionInfo(forCurrencyCode currencyCode: CurrencyCode) -> CurrencyConversionInfo? {
        return nil
    }
}
