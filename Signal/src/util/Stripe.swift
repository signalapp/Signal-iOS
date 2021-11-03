//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PassKit

struct Stripe: Dependencies {
    static func donate(amount: NSDecimalNumber, in currencyCode: Currency.Code, for payment: PKPayment) -> Promise<Void> {
        firstly { () -> Promise<API.PaymentIntent> in
            API.createPaymentIntent(for: amount, in: currencyCode)
        }.then { intent in
            API.confirmPaymentIntent(for: payment, clientSecret: intent.clientSecret, paymentIntentId: intent.id)
        }
    }

    static func isAmountTooLarge(_ amount: NSDecimalNumber, in currencyCode: Currency.Code) -> Bool {
        // Stripe supports a maximum of 8 integral digits.
        integralAmount(amount, in: currencyCode) > 99_999_999
    }

    static func isAmountTooSmall(_ amount: NSDecimalNumber, in currencyCode: Currency.Code) -> Bool {
        // Stripe requires different minimums per currency, but they often depend
        // on conversion rates which we don't have access to. It's okay to do a best
        // effort here because stripe will reject the payment anyway, this just allows
        // us to fail sooner / provide a nicer error to the user.
        let minimumIntegralAmount = minimumIntegralChargePerCurrencyCode[currencyCode] ?? 50
        return integralAmount(amount, in: currencyCode) < minimumIntegralAmount
    }

    static func integralAmount(_ amount: NSDecimalNumber, in currencyCode: Currency.Code) -> UInt {
        let roundedAndScaledAmount: Double
        if zeroDecimalCurrencyCodes.contains(currencyCode.uppercased()) {
            roundedAndScaledAmount = amount.doubleValue.rounded(.toNearestOrEven)
        } else {
            roundedAndScaledAmount = (amount.doubleValue * 100).rounded(.toNearestOrEven)
        }

        guard roundedAndScaledAmount <= Double(UInt.max) else { return UInt.max }
        guard roundedAndScaledAmount >= 0 else { return 0 }
        return UInt(roundedAndScaledAmount)
    }
}

// TODO EB Factor this out

// MARK: - API
fileprivate extension Stripe {
    struct API {
        struct PaymentIntent {
            let id: String
            let clientSecret: String
        }
        static func createPaymentIntent(
            for amount: NSDecimalNumber,
            in currencyCode: Currency.Code
        ) -> Promise<(PaymentIntent)> {
            firstly(on: .sharedUserInitiated) { () -> Promise<HTTPResponse> in
                guard !isAmountTooSmall(amount, in: currencyCode) else {
                    throw OWSAssertionError("Amount too small")
                }

                guard !isAmountTooLarge(amount, in: currencyCode) else {
                    throw OWSAssertionError("Amount too large")
                }

                guard supportedCurrencyCodes.contains(currencyCode.uppercased()) else {
                    throw OWSAssertionError("Unexpected currency code")
                }

                // The description is never translated as it's populated into an
                // english only receipt by Stripe.
                let request = OWSRequestFactory.createPaymentIntent(
                    withAmount: integralAmount(amount, in: currencyCode),
                    inCurrencyCode: currencyCode,
                    withDescription: LocalizationNotNeeded("Thank you for your donation. Your contribution helps fuel the mission of developing open source privacy technology that protects free expression and enables secure global communication for millions around the world. Signal Technology Foundation is a tax-exempt nonprofit organization in the United States under section 501c3 of the Internal Revenue Code. Our Federal Tax ID is 82-4506840. No goods or services were provided in exchange for this donation. Please retain this receipt for your tax records.")
                )

                return networkManager.makePromise(request: request)
            }.map(on: .sharedUserInitiated) { response in
                guard let json = response.responseBodyJson else {
                    throw OWSAssertionError("Missing or invalid JSON")
                }
                guard let parser = ParamParser(responseObject: json) else {
                    throw OWSAssertionError("Failed to decode JSON response")
                }
                return PaymentIntent(
                    id: try parser.required(key: "id"),
                    clientSecret: try parser.required(key: "client_secret")
                )
            }
        }

        static func confirmPaymentIntent(for payment: PKPayment, clientSecret: String, paymentIntentId: String) -> Promise<Void> {
            firstly(on: .sharedUserInitiated) { () -> Promise<String> in
                DonationUtilities.createPaymentMethod(with: payment)
            }.then(on: .sharedUserInitiated) { paymentMethodId -> Promise<HTTPResponse> in
                var parameters = [
                    "payment_method": paymentMethodId,
                    "client_secret": clientSecret
                ]
                if let email = payment.shippingContact?.emailAddress {
                    parameters["receipt_email"] = email
                }
                return try DonationUtilities.postForm(endpoint: "payment_intents/\(paymentIntentId)/confirm", parameters: parameters)
            }.asVoid()
        }

    }
}

// MARK: - Currency
// See https://stripe.com/docs/currencies

extension Stripe {
    static let supportedCurrencyCodes: [Currency.Code] = [
        "USD",
        "AED",
        "AFN",
        "ALL",
        "AMD",
        "ANG",
        "AOA",
        "ARS",
        "AUD",
        "AWG",
        "AZN",
        "BAM",
        "BBD",
        "BDT",
        "BGN",
        "BIF",
        "BMD",
        "BND",
        "BOB",
        "BRL",
        "BSD",
        "BWP",
        "BZD",
        "CAD",
        "CDF",
        "CHF",
        "CLP",
        "CNY",
        "COP",
        "CRC",
        "CVE",
        "CZK",
        "DJF",
        "DKK",
        "DOP",
        "DZD",
        "EGP",
        "ETB",
        "EUR",
        "FJD",
        "FKP",
        "GBP",
        "GEL",
        "GIP",
        "GMD",
        "GNF",
        "GTQ",
        "GYD",
        "HKD",
        "HNL",
        "HRK",
        "HTG",
        "HUF",
        "IDR",
        "ILS",
        "INR",
        "ISK",
        "JMD",
        "JPY",
        "KES",
        "KGS",
        "KHR",
        "KMF",
        "KRW",
        "KYD",
        "KZT",
        "LAK",
        "LBP",
        "LKR",
        "LRD",
        "LSL",
        "MAD",
        "MDL",
        "MGA",
        "MKD",
        "MMK",
        "MNT",
        "MOP",
        "MRO",
        "MUR",
        "MVR",
        "MWK",
        "MXN",
        "MYR",
        "MZN",
        "NAD",
        "NGN",
        "NIO",
        "NOK",
        "NPR",
        "NZD",
        "PAB",
        "PEN",
        "PGK",
        "PHP",
        "PKR",
        "PLN",
        "PYG",
        "QAR",
        "RON",
        "RSD",
        "RUB",
        "RWF",
        "SAR",
        "SBD",
        "SCR",
        "SEK",
        "SGD",
        "SHP",
        "SLL",
        "SOS",
        "SRD",
        "STD",
        "SZL",
        "THB",
        "TJS",
        "TOP",
        "TRY",
        "TTD",
        "TWD",
        "TZS",
        "UAH",
        "UGX",
        "UYU",
        "UZS",
        "VND",
        "VUV",
        "WST",
        "XAF",
        "XCD",
        "XOF",
        "XPF",
        "YER",
        "ZAR",
        "ZMW"
    ]
    static let supportedCurrencyInfos: [Currency.Info] = {
        Currency.infos(for: supportedCurrencyCodes, ignoreMissingNames: false, shouldSort: true)
    }()

    static let preferredCurrencyCodes: [Currency.Code] = [
        "USD",
        "AUD",
        "BRL",
        "GBP",
        "CAD",
        "CNY",
        "EUR",
        "HKD",
        "INR",
        "JPY",
        "KRW",
        "PLN",
        "SEK",
        "CHF"
    ]
    static let preferredCurrencyInfos: [Currency.Info] = {
        Currency.infos(for: preferredCurrencyCodes, ignoreMissingNames: true, shouldSort: false)
    }()

    static let zeroDecimalCurrencyCodes: [Currency.Code] = [
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

    static let minimumIntegralChargePerCurrencyCode: [Currency.Code: UInt] = [
        "USD": 50,
        "AED": 200,
        "AUD": 50,
        "BGN": 100,
        "BRL": 50,
        "CAD": 50,
        "CHF": 50,
        "CZK": 1500,
        "DKK": 250,
        "EUR": 50,
        "GBP": 30,
        "HKD": 400,
        "HUF": 17500,
        "INR": 50,
        "JPY": 50,
        "MXN": 10,
        "MYR": 2,
        "NOK": 300,
        "NZD": 50,
        "PLN": 200,
        "RON": 200,
        "SEK": 300,
        "SGD": 50
    ]

    static let defaultCurrencyCode: Currency.Code = {
        if let localeCurrencyCode = Locale.current.currencyCode?.uppercased(), supportedCurrencyCodes.contains(localeCurrencyCode) {
            return localeCurrencyCode
        }

        return "USD"
    }()
}
