//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum PaymentsError: Error {
    case notEnabled
    case userNotRegisteredOrAppNotReady
    case userHasNoPublicAddress
    case invalidCurrency
    case invalidWalletKey
    case invalidAmount
    case invalidFee
    case insufficientFunds
    case timeout
    case invalidModel
    case tooOldToSubmit
    case indeterminateState
    case unknownSDKError
    case invalidInput
    case connectionFailure
    case authorizationFailure
    case invalidServerResponse
    case attestationVerificationFailed
    case outdatedClient
    case serverRateLimited
    case serializationError
    case verificationStatusUnknown
    case ledgerBlockTimestampUnknown
    case missingModel
    case defragmentationRequired
    case invalidTransaction
    case inputsAlreadySpent
    case defragmentationFailed
    case invalidPassphrase
    case invalidEntropy
    case killSwitch
    case outgoingVerificationTakingTooLong
}

// MARK: -

@objc
public protocol PaymentsHelper: AnyObject {

    var arePaymentsEnabled: Bool { get }
    func setArePaymentsEnabled(for address: SignalServiceAddress, hasPaymentsEnabled: Bool, transaction: SDSAnyWriteTransaction)
    func arePaymentsEnabled(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool

    @objc(processIncomingPaymentSyncMessage:messageTimestamp:transaction:)
    func processIncomingPaymentSyncMessage(_ paymentProto: SSKProtoSyncMessageOutgoingPayment,
                                           messageTimestamp: UInt64,
                                           transaction: SDSAnyWriteTransaction)

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
}

// MARK: -

public protocol PaymentsHelperSwift: PaymentsHelper {
}

// MARK: -

public protocol SendPaymentRecipient {
    var address: SignalServiceAddress? { get }
    var isIdentifiedPayment: Bool { get }
}

// MARK: -

public protocol PreparedPayment {
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

public enum PaymentsState: Equatable, Dependencies {

    case disabled
    case disabledWithPaymentsEntropy(paymentsEntropy: Data)
    case enabled(paymentsEntropy: Data)

    // We should almost always construct instances of PaymentsState
    // using this method.  It enforces important invariants.
    //
    // * paymentsEntropy is not discarded.
    // * Payments are only enabled if paymentsEntropy is valid.
    // * Payments are only enabled if paymentsEntropy has valid length.
    public static func build(arePaymentsEnabled: Bool,
                             paymentsEntropy: Data?) -> PaymentsState {
        guard let paymentsEntropy = paymentsEntropy else {
            return .disabled
        }
        guard paymentsEntropy.count == PaymentsConstants.paymentsEntropyLength else {
            owsFailDebug("paymentsEntropy has invalid length: \(paymentsEntropy.count) != \(PaymentsConstants.paymentsEntropyLength).")
            return .disabled
        }
        if arePaymentsEnabled {
            return .enabled(paymentsEntropy: paymentsEntropy)
        } else {
            return .disabledWithPaymentsEntropy(paymentsEntropy: paymentsEntropy)
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .enabled:
            return true
        case .disabled, .disabledWithPaymentsEntropy:
            return false
        }
    }

    public var paymentsEntropy: Data? {
        switch self {
        case .enabled(let paymentsEntropy):
            return paymentsEntropy
        case .disabled:
            return nil
        case .disabledWithPaymentsEntropy(let paymentsEntropy):
            return paymentsEntropy
        }
    }

    // MARK: Equatable

    public static func == (lhs: PaymentsState, rhs: PaymentsState) -> Bool {
        return (lhs.isEnabled == rhs.isEnabled &&
                    lhs.paymentsEntropy == rhs.paymentsEntropy)
    }
}

// MARK: -

public class MockPaymentsHelper: NSObject {
}

// MARK: -

extension MockPaymentsHelper: PaymentsHelperSwift {

    public var arePaymentsEnabled: Bool {
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
}

// MARK: -

@objc
public protocol PaymentsCurrencies: AnyObject {

    // Expressed as a ratio:
    //
    // price of fiat currency / price of payment currency (MobileCoin)
    typealias CurrencyConversionRate = Double

    var currentCurrencyCode: Currency.Code { get }

    func setCurrentCurrencyCode(_ currencyCode: Currency.Code, transaction: SDSAnyWriteTransaction)

    func updateConversationRatesIfStale()

    func warmCaches()
}

// MARK: -

public protocol PaymentsCurrenciesSwift: PaymentsCurrencies {

    var preferredCurrencyInfos: [Currency.Info] { get }

    var supportedCurrencyInfos: [Currency.Info] { get }

    var supportedCurrencyInfosWithCurrencyConversions: [Currency.Info] { get }

    func conversionInfo(forCurrencyCode currencyCode: Currency.Code) -> CurrencyConversionInfo?
}

// MARK: -

public class PaymentsConstants {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private init() {}

    @objc
    public static let picoMobPerMob: UInt64 = 1000 * 1000 * 1000 * 1000

    @objc
    public static let mobileCoinCurrencyIdentifier = "MOB"

    @objc
    public static let currencyCodeGBP = "GBP"

    public static func convertMobToPicoMob(_ mob: Double) -> UInt64 {
        UInt64(round(mob * Double(picoMobPerMob)))
    }

    public static func convertPicoMobToMob(_ picoMob: UInt64) -> Double {
        Double(picoMob) / Double(picoMobPerMob)
    }

    // The number of decimal digits in a picoMob.
    public static let maxMobDecimalDigits: UInt = 12

    // The largest number of non-decimal digits a user can enter
    // that can be safely expressed as picoMob in UInt64.
    //
    // Safe:    9,999,999.999,999,999,999.
    // Unsafe: 99,999,999.999,999,999,999.
    public static let maxMobNonDecimalDigits: UInt = 7

    public static let passphraseWordCount: Int = 24

    private struct DecimalFormattingInfo {
        let decimalSeparator: String
        let groupingSeparator: String
        let groupingSize: Int
        let shouldUseGroupingSeparatorsAfterDecimal: Bool
    }

    private static let decimalFormattingInfo: DecimalFormattingInfo = {
        // NumberFormatter.numberStyle affects the separator and grouping behavior.
        // We prefer to derive the values we'll use for payments from .currency,
        // but we failover to .decimal.
        let numberFormatterCurrency = NumberFormatter()
        numberFormatterCurrency.locale = .current
        numberFormatterCurrency.numberStyle = .currency

        let numberFormatterDecimal = NumberFormatter()
        numberFormatterDecimal.locale = .current
        numberFormatterDecimal.numberStyle = .decimal

        // https://en.wikipedia.org/wiki/Decimal_separator
        let validDecimalSeparators = [",", ".", "'", "·"]
        let validGroupingSeparators = [",", ".", " ", "'",
                                       // NOTE: NumberFormatter sometimes uses a 'NARROW NO-BREAK SPACE' (U+202F) as a grouping separator.
                                       " "]
        let validGroupingSizes = [2, 3, 4]

        let decimalSeparator: String = {
            if let decimalSeparator = numberFormatterCurrency.decimalSeparator.nilIfEmpty,
               validDecimalSeparators.contains(decimalSeparator) {
                return decimalSeparator
            }
            if let decimalSeparator = numberFormatterDecimal.decimalSeparator.nilIfEmpty,
               validDecimalSeparators.contains(decimalSeparator) {
                return decimalSeparator
            }
            return ""
        }()
        let groupingSeparator: String = {
            if let groupingSeparator = numberFormatterCurrency.groupingSeparator.nilIfEmpty,
               validGroupingSeparators.contains(groupingSeparator) {
                return groupingSeparator
            }
            if let groupingSeparator = numberFormatterDecimal.groupingSeparator.nilIfEmpty,
               validGroupingSeparators.contains(groupingSeparator) {
                return groupingSeparator
            }
            return ""
        }()
        let groupingSize: Int = {
            if validGroupingSizes.contains(numberFormatterCurrency.groupingSize) {
                return numberFormatterCurrency.groupingSize
            }
            if validGroupingSizes.contains(numberFormatterDecimal.groupingSize) {
                return numberFormatterDecimal.groupingSize
            }
            return 0
        }()

        // NumberFormatter doesn't expose a property for this behavior,
        // but we can infer the appropriate behavior for the user's locale
        // by examining NumberFormatter's output.
        let shouldUseGroupingSeparatorsAfterDecimal: Bool = {
            let defaultValue = true

            // Build a decimal formatter for user locale.
            let formatter = NumberFormatter()
            formatter.locale = Locale.current
            formatter.numberStyle = .decimal
            formatter.usesSignificantDigits = false
            formatter.maximumSignificantDigits = 32
            formatter.maximumFractionDigits = 32
            formatter.minimumFractionDigits = 32

            // Format an exemplary value that should have a grouping separator
            // after the decimal if that's appropriate for the locale.
            guard let formatted = formatter.string(from: NSNumber(value: 1.23456789)) else {
                owsFailDebug("Could not format exemplary value.")
                return defaultValue
            }
            let components = formatted.components(separatedBy: formatter.decimalSeparator)
            guard components.count == 2,
                  let decimalComponent = components[safe: 1] else {
                owsFailDebug("Could not parse exemplary value.")
                return defaultValue
            }
            let shouldUseGroupingSeparatorsAfterDecimal = decimalComponent.contains(formatter.groupingSeparator)
            return shouldUseGroupingSeparatorsAfterDecimal
        }()

        guard validDecimalSeparators.contains(decimalSeparator),
              validGroupingSeparators.contains(groupingSeparator),
              validGroupingSizes.contains(groupingSize),
              decimalSeparator != groupingSeparator else {

            // Fall back to the most common international style formatting.
            return DecimalFormattingInfo(decimalSeparator: ",",
                                         groupingSeparator: ".",
                                         groupingSize: 3,
                                         shouldUseGroupingSeparatorsAfterDecimal: shouldUseGroupingSeparatorsAfterDecimal)
        }
        return DecimalFormattingInfo(decimalSeparator: decimalSeparator,
                                     groupingSeparator: groupingSeparator,
                                     groupingSize: groupingSize,
                                     shouldUseGroupingSeparatorsAfterDecimal: shouldUseGroupingSeparatorsAfterDecimal)
    }()

    public static var decimalSeparator: String {
        decimalFormattingInfo.decimalSeparator
    }

    public static var groupingSeparator: String {
        decimalFormattingInfo.groupingSeparator
    }

    public static var groupingSize: Int {
        decimalFormattingInfo.groupingSize
    }

    public static var shouldUseGroupingSeparatorsAfterDecimal: Bool {
        decimalFormattingInfo.shouldUseGroupingSeparatorsAfterDecimal
    }

    public static let paymentsEntropyLength: UInt = 32
}

// MARK: -

public struct CurrencyConversionInfo {
    public let currencyCode: Currency.Code
    public let name: String
    // Don't use this field; use convertToFiatCurrency() instead.
    private let conversionRate: PaymentsCurrencies.CurrencyConversionRate
    // How fresh is this conversion info?
    public let conversionDate: Date

    public init(currencyCode: Currency.Code,
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

    public var asCurrencyInfo: Currency.Info {
        Currency.Info(code: currencyCode, name: name)
    }

    public static func areEqual(_ left: CurrencyConversionInfo?,
                                _ right: CurrencyConversionInfo?) -> Bool {
        return (left?.currencyCode == right?.currencyCode &&
                    left?.conversionRate == right?.conversionRate)
    }
}

// MARK: -

public class MockPaymentsCurrencies: NSObject, PaymentsCurrenciesSwift {

    public let currentCurrencyCode: Currency.Code = PaymentsConstants.currencyCodeGBP

    public func setCurrentCurrencyCode(_ currencyCode: Currency.Code, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func warmCaches() {}

    public let preferredCurrencyInfos: [Currency.Info] = []

    public let supportedCurrencyInfos: [Currency.Info] = []

    public let supportedCurrencyInfosWithCurrencyConversions: [Currency.Info] = []

    public func updateConversationRatesIfStale() {}

    public func conversionInfo(forCurrencyCode currencyCode: Currency.Code) -> CurrencyConversionInfo? {
        return nil
    }
}
