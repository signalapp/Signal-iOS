//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalServiceKit

public struct Stripe: Dependencies {
    public struct PaymentIntent {
        let id: String
        let clientSecret: String

        fileprivate init(clientSecret: String) throws {
            self.id = try API.id(for: clientSecret)
            self.clientSecret = clientSecret
        }
    }

    public static func boost(amount: NSDecimalNumber,
                             in currencyCode: Currency.Code,
                             level: OneTimeBadgeLevel,
                             for payment: PKPayment) -> Promise<String> {
        firstly { () -> Promise<PaymentIntent> in
            createBoostPaymentIntent(for: amount, in: currencyCode, level: level)
        }.then { intent in
            confirmPaymentIntent(for: payment, clientSecret: intent.clientSecret, paymentIntentId: intent.id).map { intent.id }
        }
    }

    public static func createBoostPaymentIntent(
        for amount: NSDecimalNumber,
        in currencyCode: Currency.Code,
        level: OneTimeBadgeLevel
    ) -> Promise<PaymentIntent> {
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
            let request = OWSRequestFactory.boostCreatePaymentIntent(
                withAmount: integralAmount(amount, in: currencyCode),
                inCurrencyCode: currencyCode,
                level: level.rawValue
            )

            return networkManager.makePromise(request: request)
        }.map(on: .sharedUserInitiated) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Failed to decode JSON response")
            }
            return try PaymentIntent(
                clientSecret: try parser.required(key: "clientSecret")
            )
        }
    }

    public static func createPaymentMethod(with payment: PKPayment) -> Promise<String> {
        firstly(on: .sharedUserInitiated) { () -> Promise<String> in
            API.createToken(with: payment)
        }.then(on: .sharedUserInitiated) { tokenId -> Promise<HTTPResponse> in

            let parameters: [String: Any] = ["card": ["token": tokenId], "type": "card"]
            return try API.postForm(endpoint: "payment_methods", parameters: parameters)
        }.map(on: .sharedUserInitiated) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing responseBodyJson")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Failed to decode JSON response")
            }
            return try parser.required(key: "id")
        }
    }

    static func confirmPaymentIntent(for payment: PKPayment, clientSecret: String, paymentIntentId: String) -> Promise<Void> {
        firstly(on: .sharedUserInitiated) { () -> Promise<String> in
            createPaymentMethod(with: payment)
        }.then(on: .sharedUserInitiated) { paymentMethodId -> Promise<HTTPResponse> in
            guard !SubscriptionManager.terminateTransactionIfPossible else {
                throw OWSGenericError("Boost transaction chain cancelled")
            }

            return try confirmPaymentIntent(paymentIntentClientSecret: clientSecret,
                                            paymentIntentId: paymentIntentId,
                                            paymentMethodId: paymentMethodId)
        }.asVoid()
    }

    public static func confirmPaymentIntent(paymentIntentClientSecret: String,
                                            paymentIntentId: String,
                                            paymentMethodId: String,
                                            idempotencyKey: String? = nil) throws -> Promise<HTTPResponse> {
        try API.postForm(endpoint: "payment_intents/\(paymentIntentId)/confirm",
                         parameters: [
                            "payment_method": paymentMethodId,
                            "client_secret": paymentIntentClientSecret
                         ],
                         idempotencyKey: idempotencyKey)
    }

    public static func confirmSetupIntent(for paymentIntentID: String, clientSecret: String, payment: PKPayment) throws -> Promise<HTTPResponse> {
        firstly(on: .sharedUserInitiated) { () -> Promise<HTTPResponse> in
            let setupIntentId = try API.id(for: clientSecret)
            return try API.postForm(endpoint: "setup_intents/\(setupIntentId)/confirm", parameters: [
                "payment_method": paymentIntentID,
                "client_secret": clientSecret
            ])
        }
    }

    public static func isAmountTooLarge(_ amount: NSDecimalNumber, in currencyCode: Currency.Code) -> Bool {
        // Stripe supports a maximum of 8 integral digits.
        integralAmount(amount, in: currencyCode) > 99_999_999
    }

    public static func isAmountTooSmall(_ amount: NSDecimalNumber, in currencyCode: Currency.Code) -> Bool {
        // Stripe requires different minimums per currency, but they often depend
        // on conversion rates which we don't have access to. It's okay to do a best
        // effort here because stripe will reject the payment anyway, this just allows
        // us to fail sooner / provide a nicer error to the user.
        let minimumIntegralAmount = minimumIntegralChargePerCurrencyCode[currencyCode] ?? 50
        return integralAmount(amount, in: currencyCode) < minimumIntegralAmount
    }

    public static func integralAmount(_ amount: NSDecimalNumber, in currencyCode: Currency.Code) -> UInt {
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

    static let publishableKey: String = TSConstants.isUsingProductionService
        ? "pk_live_6cmGZopuTsV8novGgJJW9JpC00vLIgtQ1D"
        : "pk_test_sngOd8FnXNkpce9nPXawKrJD00kIDngZkD"

    static let authorizationHeader = "Basic \(Data("\(publishableKey):".utf8).base64EncodedString())"

    static let urlSession = OWSURLSession(
        baseUrl: URL(string: "https://api.stripe.com/v1/")!,
        securityPolicy: OWSURLSession.defaultSecurityPolicy,
        configuration: URLSessionConfiguration.ephemeral
    )

    struct API {
        static func id(for clientSecret: String) throws -> String {
            let components = clientSecret.components(separatedBy: "_secret_")
            if components.count >= 2, !components[0].isEmpty {
                return components[0]
            } else {
                throw OWSAssertionError("Invalid client secret")
            }
        }

        // MARK: Common Stripe integrations

        static func parameters(for payment: PKPayment) -> [String: Any] {
            var parameters = [String: Any]()
            parameters["pk_token"] = String(data: payment.token.paymentData, encoding: .utf8)

            if let billingContact = payment.billingContact {
                parameters["card"] = self.parameters(for: billingContact)
            }

            parameters["pk_token_instrument_name"] = payment.token.paymentMethod.displayName?.nilIfEmpty
            parameters["pk_token_payment_network"] = payment.token.paymentMethod.network.map { $0.rawValue }

            if payment.token.transactionIdentifier == "Simulated Identifier" {
                owsAssertDebug(!TSConstants.isUsingProductionService, "Simulated ApplePay only works in staging")
                // Generate a fake transaction identifier
                parameters["pk_token_transaction_id"] = "ApplePayStubs~4242424242424242~0~USD~\(UUID().uuidString)"
            } else {
                parameters["pk_token_transaction_id"] =  payment.token.transactionIdentifier.nilIfEmpty
            }

            return parameters
        }

        static func parameters(for contact: PKContact) -> [String: String] {
            var parameters = [String: String]()

            if let name = contact.name {
                parameters["name"] = OWSFormat.formatNameComponents(name).nilIfEmpty
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

        static func createToken(with payment: PKPayment) -> Promise<String> {
            firstly(on: .sharedUserInitiated) { () -> Promise<HTTPResponse> in
                return try postForm(endpoint: "tokens", parameters: parameters(for: payment))
            }.map(on: .sharedUserInitiated) { response in
                guard let json = response.responseBodyJson else {
                    throw OWSAssertionError("Missing responseBodyJson")
                }
                guard let parser = ParamParser(responseObject: json) else {
                    throw OWSAssertionError("Failed to decode JSON response")
                }
                return try parser.required(key: "id")
            }
        }

        static func postForm(endpoint: String,
                             parameters: [String: Any],
                             idempotencyKey: String? = nil) throws -> Promise<HTTPResponse> {
            guard let formData = AFQueryStringFromParameters(parameters).data(using: .utf8) else {
                throw OWSAssertionError("Failed to generate post body data")
            }

            var headers: [String: String] = [
                "Content-Type": "application/x-www-form-urlencoded",
                "Authorization": authorizationHeader
            ]
            if let idempotencyKey = idempotencyKey {
                headers["Idempotency-Key"] = idempotencyKey
            }

            return urlSession.dataTaskPromise(
                endpoint,
                method: .post,
                headers: headers,
                body: formData
            )
        }

    }
}

// MARK: - Currency
// See https://stripe.com/docs/currencies

public extension Stripe {
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
