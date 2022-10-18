//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalCoreKit

public class DonationUtilities: NSObject {
    public static let sendGiftBadgeJobQueue = SendGiftBadgeJobQueue()

    public static var isApplePayAvailable: Bool {
        PKPaymentAuthorizationController.canMakePayments()
    }

    public static var canSendGiftBadges: Bool {
        isApplePayAvailable && RemoteConfig.canSendGiftBadges
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
        public let amounts: [Decimal]
    }

    private static let currencyFormatter: NumberFormatter = {
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .decimal
        return currencyFormatter
    }()

    public static func formatCurrency(_ value: Decimal, currencyCode: Currency.Code, includeSymbol: Bool = true) -> String {
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

    public static func newPaymentRequest(for amount: Decimal, currencyCode: String, isRecurring: Bool) -> PKPaymentRequest {
        let nsAmount = amount as NSDecimalNumber
        let paymentSummaryItem: PKPaymentSummaryItem
        if isRecurring {
            if #available(iOS 15, *) {
                let recurringSummaryItem = PKRecurringPaymentSummaryItem(
                    label: donationToSignal(),
                    amount: nsAmount
                )
                recurringSummaryItem.intervalUnit = .month
                recurringSummaryItem.intervalCount = 1  // once per month
                paymentSummaryItem = recurringSummaryItem
            } else {
                paymentSummaryItem = PKPaymentSummaryItem(
                    label: monthlyDonationToSignal(),
                    amount: nsAmount
                )
            }
        } else {
            paymentSummaryItem = PKPaymentSummaryItem(label: donationToSignal(), amount: nsAmount)
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
