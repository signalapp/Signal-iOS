//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PassKit
import PromiseKit

struct Stripe: Dependencies {
    typealias CurrencyCode = String

    static func donate(amount: Double, in currencyCode: CurrencyCode, for payment: PKPayment) -> Promise<Void> {
        firstly { () -> Promise<API.PaymentIntent> in
            API.createPaymentIntent(for: amount, in: currencyCode)
        }.then { intent in
            API.confirmPaymentIntent(for: payment, clientSecret: intent.clientSecret, paymentIntentId: intent.id)
        }
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
        static func createPaymentIntent(for amount: Double, in currencyCode: String) -> Promise<(PaymentIntent)> {
            firstly(on: .sharedUserInitiated) { () -> Promise<TSNetworkManager.Response> in
                guard amount > 0 else {
                    throw OWSAssertionError("Invalid amount")
                }

                guard Currency.supportedCodes.contains(currencyCode.uppercased()) else {
                    throw OWSAssertionError("Unexpected currency code")
                }

                let integralAmount: UInt
                if Currency.zeroDecimalCodes.contains(currencyCode.uppercased()) {
                    integralAmount = UInt(amount.rounded(.toNearestOrEven))
                } else {
                    integralAmount = UInt((amount * 100).rounded(.toNearestOrEven))
                }

                let request = OWSRequestFactory.createPaymentIntent(
                    withAmount: integralAmount,
                    inCurrencyCode: currencyCode
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
                if let email = payment.billingContact?.emailAddress {
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

extension Stripe {
    struct Currency {
        static let supportedCodes = [
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
        static let supportedInfos: [CurrencyInfo] = {
            PaymentsCurrenciesImpl.currencyInfos(for: supportedCodes, ignoreMissingNames: false, shouldSort: true)
        }()

        static let preferredCodes = [
            "AUD",
            "GBP",
            "CAD",
            "CNY",
            "EUR",
            "JPY",
            "USD"
        ]
        static let preferredInfos: [CurrencyInfo] = {
            PaymentsCurrenciesImpl.currencyInfos(for: preferredCodes, ignoreMissingNames: true, shouldSort: false)
        }()

        static let zeroDecimalCodes = [
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

        static let defaultCode: String = {
            if let localeCurrencyCode = Locale.current.currencyCode?.uppercased(), supportedCodes.contains(localeCurrencyCode) {
                return localeCurrencyCode
            }

            return "USD"
        }()
    }
}
