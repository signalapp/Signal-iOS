//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PassKit
import PromiseKit

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

// MARK: - API
fileprivate extension Stripe {
    struct API {
        static let publishableKey: String = FeatureFlags.isUsingProductionService
            ? "pk_live_6cmGZopuTsV8novGgJJW9JpC00vLIgtQ1D"
            : "pk_test_sngOd8FnXNkpce9nPXawKrJD00kIDngZkD"

        static let urlSession = OWSURLSession(
            baseUrl: URL(string: "https://\(publishableKey):@api.stripe.com/v1/")!,
            securityPolicy: OWSURLSession.defaultSecurityPolicy,
            configuration: URLSessionConfiguration.ephemeral
        )

        struct PaymentIntent {
            let id: String
            let clientSecret: String
        }
        static func createPaymentIntent(
            for amount: NSDecimalNumber,
            in currencyCode: Currency.Code
        ) -> Promise<(PaymentIntent)> {
            firstly(on: .sharedUserInitiated) { () -> Promise<TSNetworkManager.Response> in
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
            }.map(on: .sharedUserInitiated) {  _, responseObject in
                guard let parser = ParamParser(responseObject: responseObject) else {
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
                createPaymentMethod(with: payment)
            }.then(on: .sharedUserInitiated) { paymentMethodId -> Promise<OWSHTTPResponse> in
                var parameters = [
                    "payment_method": paymentMethodId,
                    "client_secret": clientSecret
                ]
                if let email = payment.shippingContact?.emailAddress {
                    parameters["receipt_email"] = email
                }
                return try postForm(endpoint: "payment_intents/\(paymentIntentId)/confirm", parameters: parameters)
            }.asVoid()
        }

        static func createToken(with payment: PKPayment) -> Promise<String> {
            firstly(on: .sharedUserInitiated) { () -> Promise<OWSHTTPResponse> in
                try postForm(endpoint: "tokens", parameters: parameters(for: payment))
            }.map(on: .sharedUserInitiated) { response in
                guard let responseData = response.responseData, !responseData.isEmpty else {
                    throw OWSAssertionError("Missing response data")
                }
                let responseObject = try JSONSerialization.jsonObject(with: responseData, options: .init(rawValue: 0))
                guard let parser = ParamParser(responseObject: responseObject) else {
                    throw OWSAssertionError("Failed to decode JSON response")
                }
                return try parser.required(key: "id")
            }
        }

        static func createPaymentMethod(with payment: PKPayment) -> Promise<String> {
            firstly(on: .sharedUserInitiated) { () -> Promise<String> in
                createToken(with: payment)
            }.then(on: .sharedUserInitiated) { tokenId -> Promise<OWSHTTPResponse> in
                let parameters: [String: Any] = ["card": ["token": tokenId], "type": "card"]
                return try postForm(endpoint: "payment_methods", parameters: parameters)
            }.map(on: .sharedUserInitiated) { response in
                guard let responseData = response.responseData, !responseData.isEmpty else {
                    throw OWSAssertionError("Missing response data")
                }
                let responseObject = try JSONSerialization.jsonObject(with: responseData, options: .init(rawValue: 0))
                guard let parser = ParamParser(responseObject: responseObject) else {
                    throw OWSAssertionError("Failed to decode JSON response")
                }
                return try parser.required(key: "id")
            }
        }

        static func parameters(for payment: PKPayment) -> [String: Any] {
            var parameters = [String: Any]()
            parameters["pk_token"] = String(data: payment.token.paymentData, encoding: .utf8)

            if let billingContact = payment.billingContact {
                parameters["card"] = self.parameters(for: billingContact)
            }

            parameters["pk_token_instrument_name"] = payment.token.paymentMethod.displayName?.nilIfEmpty
            parameters["pk_token_payment_network"] = payment.token.paymentMethod.network.map { $0.rawValue }

            if payment.token.transactionIdentifier == "Simulated Identifier" {
                owsAssertDebug(!FeatureFlags.isUsingProductionService, "Simulated ApplePay only works in staging")
                // Generate a fake transaction identifier
                parameters["pk_token_transaction_id"] = "ApplePayStubs~4242424242424242~0~USD~\(UUID().uuidString)"
            } else {
                parameters["pk_token_transaction_id"] =  payment.token.transactionIdentifier.nilIfEmpty
            }

            return parameters
        }

        static func parameters(for contact: PKContact) -> [String: Any] {
            var parameters = [String: Any]()

            if let name = contact.name {
                parameters["name"] = PersonNameComponentsFormatter.localizedString(from: name, style: .default).nilIfEmpty
            }

            if let email = contact.emailAddress {
                parameters["email"] = email.nilIfEmpty
            }

            if let phoneNumber = contact.phoneNumber {
                parameters["phone"] = phoneNumber.stringValue.nilIfEmpty
            }

            if let address = contact.postalAddress {
                parameters["address_line1"] = address.street.nilIfEmpty
                parameters["address_city"] = address.city.nilIfEmpty
                parameters["address_state"] = address.state.nilIfEmpty
                parameters["address_zip"] = address.postalCode.nilIfEmpty
                parameters["address_country"] = address.isoCountryCode.uppercased()
            }

            return parameters
        }

        static func postForm(endpoint: String, parameters: [String: Any]) throws -> Promise<OWSHTTPResponse> {
            guard let formData = AFQueryStringFromParameters(parameters).data(using: .utf8) else {
                throw OWSAssertionError("Failed to generate post body data")
            }

            return urlSession.dataTaskPromise(
                endpoint,
                method: .post,
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: formData
            )
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
