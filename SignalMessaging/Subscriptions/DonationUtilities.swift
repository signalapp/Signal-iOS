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

    /// Returns a set of donation payment methods available to the local user,
    /// for donating in a specific currency.
    public static func supportedDonationPaymentMethods(
        forDonationMode donationMode: DonationMode,
        usingCurrency currencyCode: Currency.Code,
        withConfiguration configuration: SubscriptionManagerImpl.DonationConfiguration.PaymentMethodsConfiguration,
        localNumber: String?
    ) -> Set<DonationPaymentMethod> {
        let generallySupportedMethods = supportedDonationPaymentMethods(
            forDonationMode: donationMode,
            localNumber: localNumber
        )

        let currencySupportedMethods = configuration.supportedPaymentMethods(
            forCurrencyCode: currencyCode
        )

        return generallySupportedMethods.intersection(currencySupportedMethods)
    }

    /// Returns a set of the donation payment methods available to the local
    /// user for the given donation mode, without considering what currency
    /// they will be donating in.
    public static func supportedDonationPaymentMethods(
        forDonationMode donationMode: DonationMode,
        localNumber: String?
    ) -> Set<DonationPaymentMethod> {
        guard let localNumber else { return [] }

        let isApplePayAvailable: Bool = {
            if
                PKPaymentAuthorizationController.canMakePayments(),
                !RemoteConfig.applePayDisabledRegions.contains(e164: localNumber)
            {
                switch donationMode {
                case .oneTime:
                    return RemoteConfig.canDonateOneTimeWithApplePay
                case .gift:
                    return RemoteConfig.canDonateGiftWithApplePay
                case .monthly:
                    return RemoteConfig.canDonateMonthlyWithApplePay
                }
            }

            return false
        }()

        let isPaypalAvailable = {
            if
                #available(iOS 14, *),
                !RemoteConfig.paypalDisabledRegions.contains(e164: localNumber)
            {
                switch donationMode {
                case .oneTime:
                    return RemoteConfig.canDonateOneTimeWithPaypal
                case .gift:
                    return RemoteConfig.canDonateGiftWithPayPal
                case .monthly:
                    return RemoteConfig.canDonateMonthlyWithPaypal
                }
            }

            return false
        }()

        let isCardAvailable = {
            if
                !RemoteConfig.creditAndDebitCardDisabledRegions.contains(e164: localNumber)
            {
                switch donationMode {
                case .oneTime:
                    return RemoteConfig.canDonateOneTimeWithCreditOrDebitCard
                case .gift:
                    return RemoteConfig.canDonateGiftWithCreditOrDebitCard
                case .monthly:
                    return RemoteConfig.canDonateMonthlyWithCreditOrDebitCard
                }
            }

            return false
        }()

        let isSEPAAvailable = {
            guard FeatureFlags.allowSEPADonations else { return false }
            switch donationMode {
            case .oneTime, .monthly:
                return true
            case .gift:
                return false
            }
        }()

        var result = Set<DonationPaymentMethod>()

        if isApplePayAvailable {
            result.insert(.applePay)
        }

        if isPaypalAvailable {
            result.insert(.paypal)
        }

        if isCardAvailable {
            result.insert(.creditOrDebitCard)
        }

        if isSEPAAvailable {
            result.insert(.sepa)
        }

        return result
    }

    /// Can the user donate in the given donation mode?
    public static func canDonate(
        inMode donationMode: DonationMode,
        localNumber: String?
    ) -> Bool {
        !supportedDonationPaymentMethods(
            forDonationMode: donationMode,
            localNumber: localNumber
        ).isEmpty
    }

    /// Can the user donate in any donation mode?
    public static func canDonateInAnyWay(localNumber: String?) -> Bool {
        DonationMode.allCases.contains { mode in
            canDonate(inMode: mode, localNumber: localNumber)
        }
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

        public init(currencyCode: Currency.Code, amounts: [FiatMoney]) {
            self.currencyCode = currencyCode
            self.amounts = amounts
        }
    }

    private static let currencyFormatter: NumberFormatter = {
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .decimal
        return currencyFormatter
    }()

    public static func format(money: FiatMoney, includeSymbol: Bool = true) -> String {
        let value = money.value
        let currencyCode = money.currencyCode

        let isZeroDecimalCurrency = zeroDecimalCurrencyCodes.contains(currencyCode)

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

// MARK: - Money amounts

/// The values in this extension are drawn largely from Stripe's documentation,
/// which means they may not be exactly correct for PayPal transactions.
/// However: 1) they are probably "good enough"; and 2) they should be replaced
/// with Signal-server values fetched from a configuration endpoint like
/// `/v1/subscription/configuration` eventually, anyway.
public extension DonationUtilities {
    /// A list of currencies known not to use decimal values
    static let zeroDecimalCurrencyCodes: Set<Currency.Code> = [
        "BIF",
        "CLP",
        "DJF",
        "GNF",
        "JPY",
        "KMF",
        "KRW",
        "MGA",
        "PYG",
        "RWF",
        "UGX",
        "VND",
        "VUV",
        "XAF",
        "XOF",
        "XPF"
    ]

    /// Is an amount of money too small, given a minimum?
    static func isBoostAmountTooSmall(_ amount: FiatMoney, minimumAmount: FiatMoney) -> Bool {
        (amount.value <= 0) || (integralAmount(for: amount) < integralAmount(for: minimumAmount))
    }

    static func isBoostAmountTooLarge(_ amount: FiatMoney, maximumAmount: FiatMoney) -> Bool {
        return integralAmount(for: amount) > integralAmount(for: maximumAmount)
    }

    /// Convert the given money amount to an integer that can be passed to
    /// service APIs. Applies rounding and scaling as appropriate for the
    /// currency.
    static func integralAmount(for amount: FiatMoney) -> UInt {
        let scaled: Decimal
        if Self.zeroDecimalCurrencyCodes.contains(amount.currencyCode.uppercased()) {
            scaled = amount.value
        } else {
            scaled = amount.value * 100
        }

        let rounded = scaled.rounded()

        guard rounded >= 0 else { return 0 }
        guard rounded <= Decimal(UInt.max) else { return UInt.max }

        return (rounded as NSDecimalNumber).uintValue
    }
}
