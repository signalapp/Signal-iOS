//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
    }

    public struct Presets {
        public struct Preset {
            public let symbol: Symbol
            public let amounts: [UInt]
        }

        public static let presets: [Currency.Code: Preset] = [
            "USD": Preset(symbol: .before("$"), amounts: [3, 5, 10, 20, 50, 100]),
            "AUD": Preset(symbol: .before("A$"), amounts: [5, 10, 15, 25, 65, 125]),
            "BRL": Preset(symbol: .before("R$"), amounts: [15, 25, 50, 100, 250, 525]),
            "GBP": Preset(symbol: .before("£"), amounts: [3, 5, 10, 15, 35, 70]),
            "CAD": Preset(symbol: .before("CA$"), amounts: [5, 10, 15, 25, 60, 125]),
            "CNY": Preset(symbol: .before("CN¥"), amounts: [20, 35, 65, 130, 320, 650]),
            "EUR": Preset(symbol: .before("€"), amounts: [3, 5, 10, 15, 40, 80]),
            "HKD": Preset(symbol: .before("HK$"), amounts: [25, 40, 80, 150, 400, 775]),
            "INR": Preset(symbol: .before("₹"), amounts: [100, 200, 300, 500, 1_000, 5_000]),
            "JPY": Preset(symbol: .before("¥"), amounts: [325, 550, 1_000, 2_200, 5_500, 11_000]),
            "KRW": Preset(symbol: .before("₩"), amounts: [3_500, 5_500, 11_000, 22_500, 55_500, 100_000]),
            "PLN": Preset(symbol: .after("zł"), amounts: [10, 20, 40, 75, 150, 375]),
            "SEK": Preset(symbol: .after("kr"), amounts: [25, 50, 75, 150, 400, 800]),
            "CHF": Preset(symbol: .currencyCode, amounts: [3, 5, 10, 20, 50, 100])
        ]

        public static func symbol(for code: Currency.Code) -> Symbol {
            presets[code]?.symbol ?? .currencyCode
        }
    }

    private static let currencyFormatter: NumberFormatter = {
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .decimal
        return currencyFormatter
    }()

    public static func formatCurrency(_ value: NSDecimalNumber, currencyCode: Currency.Code, includeSymbol: Bool = true) -> String {
        let isZeroDecimalCurrency = Stripe.zeroDecimalCurrencyCodes.contains(currencyCode)

        let decimalPlaces: Int
        if isZeroDecimalCurrency {
            decimalPlaces = 0
        } else if value.doubleValue == Double(value.intValue) {
            decimalPlaces = 0
        } else {
            decimalPlaces = 2
        }

        currencyFormatter.minimumFractionDigits = decimalPlaces
        currencyFormatter.maximumFractionDigits = decimalPlaces

        let valueString = currencyFormatter.string(from: value) ?? value.stringValue

        guard includeSymbol else { return valueString }

        switch Presets.symbol(for: currencyCode) {
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

    public static func newPaymentRequest(for amount: NSDecimalNumber, currencyCode: String, isRecurring: Bool) -> PKPaymentRequest {
        let paymentSummaryItem: PKPaymentSummaryItem
        if isRecurring {
            if #available(iOS 15, *) {
                let recurringSummaryItem = PKRecurringPaymentSummaryItem(label: donationToSignal(), amount: amount)
                recurringSummaryItem.intervalUnit = .month
                recurringSummaryItem.intervalCount = 1  // once per month
                paymentSummaryItem = recurringSummaryItem
            } else {
                paymentSummaryItem = PKPaymentSummaryItem(label: monthlyDonationToSignal(), amount: amount)
            }
        } else {
            paymentSummaryItem = PKPaymentSummaryItem(label: donationToSignal(), amount: amount)
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
