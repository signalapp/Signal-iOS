//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
import SignalServiceKit

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

    static func formatInChatSuccess(
        paymentAmount: TSPaymentAmount
    ) -> NSAttributedString {
        formatInChat(
            paymentAmount: paymentAmount,
            amountBuilder: inChatSuccessAmountBuilder(_:)
        )
    }

    static func formatInChatFailure(
        paymentAmount: TSPaymentAmount
    ) -> NSAttributedString {
        formatInChat(
            paymentAmount: paymentAmount,
            amountBuilder: inChatFailureAmountBuilder(_:)
        )
    }

    private static func inChatSuccessAmountBuilder(_ amount: String) -> NSAttributedString {
        let firstAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.dynamicTypeLargeTitle1Clamped.withSize(32)]

        let startingFont = UIFont.dynamicTypeLargeTitle1Clamped.withSize(32)
        let traits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.thin]
        let thinFontDescriptor = startingFont.fontDescriptor.addingAttributes(
            [UIFontDescriptor.AttributeName.traits: traits]
        )

        let newThinFont = UIFont(descriptor: thinFontDescriptor, size: startingFont.pointSize)
        let secondAttributes: [NSAttributedString.Key: Any] = [.font: newThinFont]

        let firstString = NSMutableAttributedString(string: amount, attributes: firstAttributes)
        let secondString = NSMutableAttributedString(string: " MOB", attributes: secondAttributes)

        // NOTE: not RTL-friendly. Maybe fix this if it comes up.
        firstString.append(secondString)
        return firstString
    }

    private static func inChatFailureAmountBuilder(_ amount: String) -> NSAttributedString {
        let firstAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.dynamicTypeLargeTitle1Clamped.withSize(17)]

        let startingFont = UIFont.dynamicTypeLargeTitle1Clamped.withSize(15)
        let traits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.light]
        let lightFontDescriptor = startingFont.fontDescriptor.addingAttributes([UIFontDescriptor.AttributeName.traits: traits])

        let newLightFont = UIFont(descriptor: lightFontDescriptor, size: startingFont.pointSize)
        let secondAttributes: [NSAttributedString.Key: Any] = [.font: newLightFont]

        let template = OWSLocalizedString(
            "PAYMENTS_IN_CHAT_FAILURE_MESSAGE_TOP",
            comment: "Payments in-chat message shown if a payment fails to send, top part. Embeds {{ number, amount of MOB coin not sent }}"
        )
        let topPart = String(format: template, amount)

        let bottomPart = OWSLocalizedString(
            "PAYMENTS_IN_CHAT_FAILURE_MESSAGE_BOTTOM",
            comment: "Payments in-chat message shown if a payment fails to send, bottom half.")

        // NOTE: not RTL-friendly. Maybe fix this if it comes up.
        let firstString = NSMutableAttributedString(string: topPart, attributes: firstAttributes)
        let secondString = NSAttributedString(string: bottomPart, attributes: secondAttributes)

        firstString.append("\n")
        firstString.append(secondString)

        return firstString
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

    @objc
    static func paymentThreadPreviewText() -> String {
        return OWSLocalizedString(
            "PAYMENTS_THREAD_PREVIEW_TEXT",
            comment: "Payments Preview Text shown in chat list for payments.")
    }

    @objc
    static func paymentPreviewText(
        paymentMessage: OWSPaymentMessage,
        type: OWSInteractionType,
        transaction: SDSAnyReadTransaction
    ) -> String? {
        // Shared
        guard
            let receipt = paymentMessage.paymentNotification?.mcReceiptData
        else {
            return nil
        }

        return paymentPreviewText(
            receipt: receipt,
            transaction: transaction,
            type: type)
    }

    static func paymentPreviewText(
        receipt: Data,
        transaction: SDSAnyReadTransaction,
        type: OWSInteractionType
    ) -> String? {
        // Payment Amount
        guard let amount: UInt64 = {
            switch type {
            case .incomingMessage:
                return Self.paymentsImpl.unmaskReceiptAmount(data: receipt)?.value
            case .outgoingMessage:
                guard let paymentModel = PaymentFinder.paymentModels(
                    forMcReceiptData: receipt,
                    transaction: transaction
                ).first else {
                    return nil
                }

                return paymentModel.paymentAmount?.picoMob
            default:
                return nil
            }
        }() else {
            return nil
        }

        return paymentPreviewText(amount: amount, transaction: transaction, type: type)
    }

    static func paymentPreviewText(
        amount: UInt64,
        transaction: SDSAnyReadTransaction,
        type: OWSInteractionType
    ) -> String? {
        // Formatted Payment Amount
        guard let formattedAmount = PaymentsFormat.format(picoMob: amount, isShortForm: true) else {
            return OWSLocalizedString(
                "PAYMENTS_PREVIEW_TEXT_UNKNOWN",
                comment: "Payments Preview Text shown in quoted replies, for unknown payments.")
        }

        // Preview Text
        let template = OWSLocalizedString(
            "PAYMENTS_PREVIEW_TEXT_QUOTED_REPLY",
            comment: "Payments Preview Text shown in quoted replies, for payments. Embeds {{ Amount sent (number), Currency (e.g. 'MOB') }}")
        let currencyName = TokenId.MOB.name
        return String(format: template, formattedAmount, currencyName)
    }
}
