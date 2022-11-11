//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MobileCoin

public class PaymentsFormat {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private init() {}
}

// MARK: -

public extension PaymentsFormat {

    private static func buildMobFormatter(isShortForm: Bool,
                                          locale: Locale? = nil) -> NumberFormatter {

        let numberFormatter = NumberFormatter()
        numberFormatter.locale = locale ?? Locale.current
        // We use .decimal and not .currency because we don't
        // want to append currency symbol.
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.maximumFractionDigits = (isShortForm
                                                    ? 4
                                                    : Int(PaymentsConstants.maxMobDecimalDigits))
        numberFormatter.usesSignificantDigits = false
        if isShortForm {
            numberFormatter.roundingMode = .halfEven
        }
        return numberFormatter
    }

    private static let mobFormatShort: NumberFormatter = {
        buildMobFormatter(isShortForm: true)
    }()

    private static let mobFormatLong: NumberFormatter = {
        buildMobFormatter(isShortForm: false)
    }()

    // Used for formatting MOB (not picoMob) values for display.
    private static func mobFormat(isShortForm: Bool) -> NumberFormatter {
        isShortForm ? mobFormatShort : mobFormatLong
    }

    // Used for formatting decimal numbers in the
    // send payment flow.  _NOT_ used for display.
    // The format is convenient to parse into an "input string"
    // the corresponds to our custom keyboard.
    private static var doubleFormat: NumberFormatter = {
        // For formatting numbers as arabic numerals without
        // any commas, etc. 1234567.890123
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "en_US")
        // Hide commas.
        numberFormatter.groupingSeparator = ""
        numberFormatter.numberStyle = .decimal

        numberFormatter.maximumFractionDigits = Int(PaymentsConstants.maxMobDecimalDigits)
        numberFormatter.usesSignificantDigits = false
        numberFormatter.roundingMode = .halfEven

        return numberFormatter
    }()

    static func format(paymentAmount: TSPaymentAmount,
                       isShortForm: Bool,
                       withCurrencyCode: Bool = false,
                       withSpace: Bool = false,
                       withPaymentType paymentType: TSPaymentType? = nil) -> String {
        guard paymentAmount.currency == .mobileCoin else {
            owsFailDebug("Unknown currency.")
            return OWSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                     comment: "Indicator for unknown currency.")
        }
        guard let amountString = format(picoMob: paymentAmount.picoMob,
                                        isShortForm: isShortForm) else {
            owsFailDebug("Couldn't format currency.")
            return OWSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                     comment: "Indicator for unknown currency.")
        }

        var result = ""

        if let paymentType = paymentType {
            result += paymentType.isIncoming ? "+" : "-"
        }

        result += amountString

        if withCurrencyCode {
            if withSpace {
                result += " "
            }
            result += PaymentsConstants.mobileCoinCurrencyIdentifier
        }
        return result
    }

    static func formatOrError(picoMob: UInt64, isShortForm: Bool) -> String {
        guard let string = format(picoMob: picoMob, isShortForm: isShortForm) else {
            owsFailDebug("Couldn't format currency.")
            return OWSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                     comment: "Indicator for unknown currency.")
        }
        return string
    }

    static func format(mob: Double, isShortForm: Bool) -> String? {
        format(picoMob: PaymentsConstants.convertMobToPicoMob(mob),
               isShortForm: isShortForm)
    }

    static func format(picoMob: UInt64, isShortForm: Bool) -> String? {
        let mob = PaymentsConstants.convertPicoMobToMob(picoMob)
        let mobFormat = Self.mobFormat(isShortForm: isShortForm)
        guard let result = mobFormat.string(from: NSNumber(value: mob)) else {
            owsFailDebug("Couldn't format currency.")
            return nil
        }
        return result
    }

    static func formatAsDoubleString(picoMob: UInt64) -> String? {
        formatAsDoubleString(PaymentsConstants.convertPicoMobToMob(picoMob))
    }

    static func formatAsDoubleString(_ value: Double) -> String? {
        guard let result = doubleFormat.string(from: NSNumber(value: value)) else {
            owsFailDebug("Couldn't format double.")
            return nil
        }
        return result
    }

    static func attributedFormat(paymentAmount: TSPaymentAmount,
                                 isShortForm: Bool,
                                 paymentType: TSPaymentType? = nil,
                                 withSpace: Bool = false) -> NSAttributedString {
        guard paymentAmount.currency == .mobileCoin else {
            owsFailDebug("Unknown currency.")
            return NSAttributedString(string: OWSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                                                comment: "Indicator for unknown currency."))
        }

        return attributedFormat(mobileCoinString: format(paymentAmount: paymentAmount,
                                                         isShortForm: isShortForm,
                                                         withPaymentType: paymentType),
                                withSpace: withSpace)
    }

    static func attributedFormat(mobileCoinString: String,
                                 withSpace: Bool = false) -> NSAttributedString {
        attributedFormat(currencyString: mobileCoinString,
                         currencyCode: PaymentsConstants.mobileCoinCurrencyIdentifier,
                         withSpace: withSpace)
    }

    static func attributedFormat(fiatCurrencyAmount: Double,
                                 currencyCode: String,
                                 withSpace: Bool = false) -> NSAttributedString? {
        guard let currencyString = format(fiatCurrencyAmount: fiatCurrencyAmount) else {
            owsFailDebug("Invalid fiatCurrencyAmount.")
            return nil
        }
        return attributedFormat(currencyString: currencyString,
                                currencyCode: currencyCode,
                                withSpace: withSpace)
    }

    static func attributedFormat(currencyString: String,
                                 currencyCode: String,
                                 withSpace: Bool = false) -> NSAttributedString {
        let text = NSMutableAttributedString()

        text.append(currencyString.ows_stripped(),
                    attributes: [
                        .foregroundColor: Theme.primaryTextColor
                    ])

        if withSpace {
            text.append(" ", attributes: [:])
        }

        text.append(currencyCode.ows_stripped(),
                    attributes: [
                        .foregroundColor: Theme.secondaryTextAndIconColor
                    ])

        return text
    }

    static func formatAsFiatCurrency(paymentAmount: TSPaymentAmount,
                                     currencyConversionInfo: CurrencyConversionInfo,
                                     locale: Locale? = nil) -> String? {
        guard let fiatCurrencyAmount = currencyConversionInfo.convertToFiatCurrency(paymentAmount: paymentAmount) else {
            return nil
        }
        return format(fiatCurrencyAmount: fiatCurrencyAmount,
                      locale: locale)
    }

    // Used to format fiat currency values for display.
    static func format(fiatCurrencyAmount: Double,
                       minimumFractionDigits: Int = 2,
                       maximumFractionDigits: Int = 2,
                       locale: Locale? = nil) -> String? {
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = locale ?? Locale.current
        // We use .decimal and not .currency because we don't
        // want to append currency symbol.
        numberFormatter.numberStyle = .decimal
        // TODO: Check with design.
        numberFormatter.minimumFractionDigits = minimumFractionDigits
        numberFormatter.maximumFractionDigits = maximumFractionDigits
        return numberFormatter.string(from: NSNumber(value: fiatCurrencyAmount))
    }
}
