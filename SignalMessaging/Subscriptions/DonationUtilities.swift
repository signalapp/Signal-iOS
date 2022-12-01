//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalServiceKit
import SignalCoreKit

public class DonationUtilities: Dependencies {
    public static var sendGiftBadgeJobQueue: SendGiftBadgeJobQueue { smJobQueues.sendGiftBadgeJobQueue }

    public static func supportedDonationPaymentMethodOptions(
        localNumber: String?
    ) -> Set<DonationPaymentMethod> {
        guard let localNumber else { return [] }

        var result = Set<DonationPaymentMethod>()

        let isApplePayAvailable = (
            PKPaymentAuthorizationController.canMakePayments() &&
            !RemoteConfig.applePayDisabledRegions.contains(e164: localNumber)
        )
        if isApplePayAvailable {
            result.insert(.applePay)
        }

        let isCardAvailable = (
            RemoteConfig.canDonateWithCreditOrDebitCard &&
            !RemoteConfig.creditAndDebitCardDisabledRegions.contains(e164: localNumber)
        )
        if isCardAvailable {
            result.insert(.creditOrDebitCard)
        }

        let isPaypalAvailable = (
            FeatureFlags.canDonateWithPaypal &&
            !RemoteConfig.paypalDisabledRegions.contains(e164: localNumber)
        )
        if isPaypalAvailable {
            result.insert(.paypal)
        }

        return result
    }

    /// Can the user donate to Signal in the app?
    public static func canDonate(localNumber: String?) -> Bool {
        !supportedDonationPaymentMethodOptions(localNumber: localNumber).isEmpty
    }

    public static var supportedNetworks: [PKPaymentNetwork] {
        return [
            .visa,
            .masterCard,
            .amex,
            .discover,
            .maestro
        ]
    }

    public enum Symbol: Equatable {
        case before(String)
        case after(String)
        case currencyCode

        private static let symbols: [Currency.Code: Symbol] = [
            "USD": .before("$"),
            "AUD": .before("A$"),
            "BRL": .before("R$"),
            "GBP": .before("£"),
            "CAD": .before("CA$"),
            "CNY": .before("CN¥"),
            "EUR": .before("€"),
            "HKD": .before("HK$"),
            "INR": .before("₹"),
            "JPY": .before("¥"),
            "KRW": .before("₩"),
            "PLN": .after("zł"),
            "SEK": .after("kr")
        ]

        public static func `for`(currencyCode: Currency.Code) -> Symbol {
            return symbols[currencyCode, default: .currencyCode]
        }
    }

    public struct Preset: Equatable {
        public let currencyCode: Currency.Code
        public let amounts: [FiatMoney]
    }

    private static let currencyFormatter: NumberFormatter = {
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .decimal
        return currencyFormatter
    }()

    public static func format(money: FiatMoney, includeSymbol: Bool = true) -> String {
        let value = money.value
        let currencyCode = money.currencyCode

        let isZeroDecimalCurrency = Stripe.zeroDecimalCurrencyCodes.contains(currencyCode)

        let decimalPlaces: Int
        if isZeroDecimalCurrency {
            decimalPlaces = 0
        } else if value.isInteger {
            decimalPlaces = 0
        } else {
            decimalPlaces = 2
        }

        currencyFormatter.minimumFractionDigits = decimalPlaces
        currencyFormatter.maximumFractionDigits = decimalPlaces

        let nsValue = value as NSDecimalNumber
        let valueString = currencyFormatter.string(from: nsValue) ?? nsValue.stringValue

        guard includeSymbol else { return valueString }

        switch Symbol.for(currencyCode: currencyCode) {
        case .before(let symbol): return symbol + valueString
        case .after(let symbol): return valueString + symbol
        case .currencyCode: return currencyCode + " " + valueString
        }
    }

    /// Given a list of currencies in preference order and a collection of
    /// supported ones, pick a default currency.
    ///
    /// For example, we might want to use EUR with a USD fallback if EUR is
    /// unsupported.
    ///
    /// ```
    /// DonationUtilities.chooseDefaultCurrency(
    ///     preferred: ["EUR", "USD"],
    ///     supported: ["USD"]
    /// )
    /// // => "USD"
    /// ```
    ///
    /// - Parameter preferred: A list of currencies in preference order.
    ///   As a convenience, can contain `nil`, which is ignored.
    /// - Parameter supported: A collection of supported currencies.
    /// - Returns: The first supported currency code, or `nil` if none are found.
    public static func chooseDefaultCurrency(
        preferred: [Currency.Code?],
        supported: any Collection<Currency.Code>
    ) -> Currency.Code? {
        for currency in preferred {
            if let currency = currency, supported.contains(currency) {
                return currency
            }
        }
        return nil
    }

    private static func donationToSignal() -> String {
        OWSLocalizedString(
            "DONATION_VIEW_DONATION_TO_SIGNAL",
            comment: "Text describing to the user that they're going to pay a donation to Signal"
        )
    }

    private static func monthlyDonationToSignal() -> String {
        OWSLocalizedString(
            "DONATION_VIEW_MONTHLY_DONATION_TO_SIGNAL",
            comment: "Text describing to the user that they're going to pay a monthly donation to Signal"
        )
    }

    public static func newPaymentRequest(for amount: FiatMoney, isRecurring: Bool) -> PKPaymentRequest {
        let nsValue = amount.value as NSDecimalNumber
        let currencyCode = amount.currencyCode

        let paymentSummaryItem: PKPaymentSummaryItem
        if isRecurring {
            if #available(iOS 15, *) {
                let recurringSummaryItem = PKRecurringPaymentSummaryItem(
                    label: donationToSignal(),
                    amount: nsValue
                )
                recurringSummaryItem.intervalUnit = .month
                recurringSummaryItem.intervalCount = 1  // once per month
                paymentSummaryItem = recurringSummaryItem
            } else {
                paymentSummaryItem = PKPaymentSummaryItem(
                    label: monthlyDonationToSignal(),
                    amount: nsValue
                )
            }
        } else {
            paymentSummaryItem = PKPaymentSummaryItem(label: donationToSignal(), amount: nsValue)
        }

        let request = PKPaymentRequest()
        request.paymentSummaryItems = [paymentSummaryItem]
        request.merchantIdentifier = "merchant." + Bundle.main.merchantId
        request.merchantCapabilities = .capability3DS
        request.countryCode = "US"
        request.currencyCode = currencyCode
        request.supportedNetworks = DonationUtilities.supportedNetworks
        return request
    }
}
