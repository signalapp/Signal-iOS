//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
    case fogOutOfSync
    case serverRateLimited
    case serializationError
    case verificationStatusUnknown
    case ledgerBlockTimestampUnknown
    case missingModel
    case defragmentationRequired
    case invalidTransaction
    case inputsAlreadySpent
    case missingMemo
    case defragmentationFailed
    case invalidPassphrase
    case invalidEntropy
    case killSwitch
    case outgoingVerificationTakingTooLong
}

// MARK: -

public class PaymentsConstants {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private init() {}

    @objc
    public static let arePaymentsEnabledDidChange = Notification.Name("arePaymentsEnabledDidChange")

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
