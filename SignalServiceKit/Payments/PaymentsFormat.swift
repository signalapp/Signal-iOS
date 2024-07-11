//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class PaymentsFormat: NSObject {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private override init() {}
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

    static func formatInChat(
        paymentAmount: TSPaymentAmount,
        amountBuilder: (String) -> NSAttributedString
    ) -> NSAttributedString {
        let mob = PaymentsConstants.convertPicoMobToMob(paymentAmount.picoMob)
        let mobFormat = buildMobFormatter(isShortForm: true)
        guard let amount = mobFormat.string(from: NSNumber(value: mob)) else {
            owsFailDebug("Couldn't format currency.")
            return NSAttributedString(
                string: OWSLocalizedString(
                    "PAYMENTS_CURRENCY_UNKNOWN",
                    comment: "Indicator for unknown currency."
                )
            )
        }

        return amountBuilder(amount)
    }

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

        return format(
            amountString: amountString,
            withCurrencyCode: withCurrencyCode,
            withSpace: withSpace,
            isIncoming: paymentType?.isIncoming
        )
    }

    static func format(
        amountString: String,
        withCurrencyCode: Bool = false,
        withSpace: Bool = false,
        isIncoming: Bool? = nil
    ) -> String {
        var result = ""

        if let isIncoming = isIncoming {
            result += isIncoming ? "+" : "-"
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

    @objc
    static func paymentThreadPreviewText() -> String {
        return OWSLocalizedString(
            "PAYMENTS_THREAD_PREVIEW_TEXT",
            comment: "Payments Preview Text shown in chat list for payments.")
    }
}
