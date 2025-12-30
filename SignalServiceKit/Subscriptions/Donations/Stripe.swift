//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit

/// Stripe donations
///
/// One-time donation ("boost") process:
/// 1. Start flow
///     - ``Stripe/boost(amount:level:for:)``
/// 2. Intent creation
///     - ``Stripe/createBoostPaymentIntent(for:level:paymentMethod:)``
/// 3. Payment source tokenization
///     - `Stripe.API.createToken(with:)`
///     - Cards need to be tokenized.
///     - SEPA transfers are not tokenized.
/// 4. PaymentMethod creation
///     - ``Stripe/createPaymentMethod(with:)``
/// 5. Intent confirmation
///     - Charges the user's payment method
///     - ``Stripe/confirmPaymentIntent(paymentIntentClientSecret:paymentIntentId:paymentMethodId:idempotencyKey:)``
public enum Stripe {
    public struct PaymentIntent {
        let id: String
        let clientSecret: String

        fileprivate init(clientSecret: String) throws {
            self.id = try API.id(for: clientSecret)
            self.clientSecret = clientSecret
        }
    }

    /// Step 1: Starts the boost payment flow.
    public static func boost(
        amount: FiatMoney,
        level: OneTimeBadgeLevel,
        for paymentMethod: PaymentMethod,
    ) async throws -> ConfirmedPaymentIntent {
        let intent = try await createBoostPaymentIntent(for: amount, level: level, paymentMethod: paymentMethod.stripePaymentMethod)
        return try await confirmPaymentIntent(
            for: paymentMethod,
            clientSecret: intent.clientSecret,
            paymentIntentId: intent.id,
        )
    }

    /// Step 2: Creates boost payment intent
    public static func createBoostPaymentIntent(
        for amount: FiatMoney,
        level: OneTimeBadgeLevel,
        paymentMethod: OWSRequestFactory.StripePaymentMethod,
    ) async throws -> PaymentIntent {
        // The description is never translated as it's populated into an
        // english only receipt by Stripe.
        let request = OWSRequestFactory.boostStripeCreatePaymentIntent(
            integerMoneyValue: DonationUtilities.integralAmount(for: amount),
            inCurrencyCode: amount.currencyCode,
            level: level.rawValue,
            paymentMethod: paymentMethod,
        )

        let response = try await SSKEnvironment.shared.networkManagerRef
            .asyncRequest(request, retryPolicy: .hopefullyRecoverable)
        guard let parser = response.responseBodyParamParser else {
            throw OWSAssertionError("Missing or invalid JSON")
        }
        return try PaymentIntent(
            clientSecret: try parser.required(key: "clientSecret"),
        )
    }

    /// Steps 3 and 4: Payment source tokenization and creates payment method
    public static func createPaymentMethod(
        with paymentMethod: PaymentMethod,
    ) async throws -> PaymentMethodID {
        do {
            let response = try await requestPaymentMethod(with: paymentMethod)
            guard let parser = response.responseBodyParamParser else {
                throw OWSAssertionError("Missing or invalid JSON!")
            }
            return try parser.required(key: "id")
        } catch {
            throw convertToStripeErrorIfPossible(error)
        }
    }

    private static func requestPaymentMethod(
        with paymentMethod: PaymentMethod,
    ) async throws -> HTTPResponse {
        switch paymentMethod {
        case let .applePay(payment: payment):
            return try await requestPaymentMethod(with: API.parameters(for: payment))
        case let .creditOrDebitCard(creditOrDebitCard: card):
            return try await requestPaymentMethod(with: API.parameters(for: card))
        case let .bankTransferSEPA(mandate: _, account: sepaAccount):

            // Step 3 not required.
            // Step 4: Payment method creation
            let parameters: [String: String] = [
                "billing_details[name]": sepaAccount.name,
                "billing_details[email]": sepaAccount.email,
                "sepa_debit[iban]": sepaAccount.iban,
                "type": "sepa_debit",
            ]
            return try await API.postForm(endpoint: "payment_methods", parameters: parameters)
        case let .bankTransferIDEAL(idealAccount):
            let parameters: [String: String] = {
                switch idealAccount {
                case let .oneTime(name: name):
                    return [
                        "billing_details[name]": name,
                        "type": "ideal",
                    ]
                case let .recurring(mandate: _, name: name, email: email):
                    return [
                        "billing_details[name]": name,
                        "billing_details[email]": email,
                        "type": "ideal",
                    ]
                }
            }()

            // Step 4: Payment method creation
            return try await API.postForm(endpoint: "payment_methods", parameters: parameters)
        }
    }

    private static func requestPaymentMethod(
        with tokenizationParameters: [String: any StripeQueryParamValue],
    ) async throws -> HTTPResponse {
        // Step 3: Payment source tokenization
        let tokenId = try await API.createToken(with: tokenizationParameters)

        // Step 4: Payment method creation
        let parameters: [String: any StripeQueryParamValue] = ["card": ["token": tokenId], "type": "card"]
        return try await API.postForm(endpoint: "payment_methods", parameters: parameters)
    }

    public struct ConfirmedPaymentIntent {
        public let paymentIntentId: String
        public let paymentMethodId: String
        public let redirectToUrl: URL?
    }

    public struct ConfirmedSetupIntent {
        public let setupIntentId: String
        public let paymentMethodId: String
        public let redirectToUrl: URL?
    }

    public typealias PaymentMethodID = String

    /// Steps 3, 4, and 5: Tokenizes payment source, creates payment method, and confirms payment intent.
    static func confirmPaymentIntent(
        for paymentMethod: PaymentMethod,
        clientSecret: String,
        paymentIntentId: String,
    ) async throws -> ConfirmedPaymentIntent {
        // Steps 3 and 4: Payment source tokenization and payment method creation
        let paymentMethodId = try await createPaymentMethod(with: paymentMethod)

        // Step 5: Confirm payment intent
        return try await confirmPaymentIntent(
            mandate: paymentMethod.mandate,
            paymentIntentClientSecret: clientSecret,
            paymentIntentId: paymentIntentId,
            paymentMethodId: paymentMethodId,
            callbackURL: paymentMethod.callbackURL,
        )
    }

    /// Step 5: Confirms payment intent
    public static func confirmPaymentIntent(
        mandate: PaymentMethod.Mandate?,
        paymentIntentClientSecret: String,
        paymentIntentId: String,
        paymentMethodId: PaymentMethodID,
        callbackURL: String? = nil,
        idempotencyKey: String? = nil,
    ) async throws -> ConfirmedPaymentIntent {
        do {
            let response = try await API.postForm(
                endpoint: "payment_intents/\(paymentIntentId)/confirm",
                parameters: [
                    "payment_method": paymentMethodId,
                    "client_secret": paymentIntentClientSecret,
                    "return_url": callbackURL ?? RETURN_URL_FOR_3DS,
                ].merging(
                    mandate?.parameters ?? [:],
                    uniquingKeysWith: { _, new in new },
                ),
                idempotencyKey: idempotencyKey,
            )

            return .init(
                paymentIntentId: paymentIntentId,
                paymentMethodId: paymentMethodId,
                redirectToUrl: parseNextActionRedirectUrl(from: response.responseBodyDict),
            )
        } catch {
            throw convertToStripeErrorIfPossible(error)
        }
    }

    public static func confirmSetupIntent(
        mandate: PaymentMethod.Mandate?,
        paymentMethodId: String,
        clientSecret: String,
        callbackURL: String?,
    ) async throws -> ConfirmedSetupIntent {
        do {
            let intentId = try API.id(for: clientSecret)
            let response = try await API.postForm(
                endpoint: "setup_intents/\(intentId)/confirm",
                parameters: [
                    "payment_method": paymentMethodId,
                    "client_secret": clientSecret,
                    "return_url": callbackURL ?? RETURN_URL_FOR_3DS,
                ].merging(
                    mandate?.parameters ?? [:],
                    uniquingKeysWith: { _, new in new },
                ),
            )

            guard let parser = response.responseBodyParamParser else {
                throw OWSAssertionError("Missing or invalid JSON!")
            }
            let setupIntentId: String = try parser.required(key: "id")
            return .init(
                setupIntentId: setupIntentId,
                paymentMethodId: paymentMethodId,
                redirectToUrl: parseNextActionRedirectUrl(from: response.responseBodyDict),
            )
        } catch {
            throw convertToStripeErrorIfPossible(error)
        }
    }
}

// MARK: - API

private extension Stripe {

    static let publishableKey: String = TSConstants.isUsingProductionService
        ? "pk_live_6cmGZopuTsV8novGgJJW9JpC00vLIgtQ1D"
        : "pk_test_sngOd8FnXNkpce9nPXawKrJD00kIDngZkD"

    static let authorizationHeader = "Basic \(Data("\(publishableKey):".utf8).base64EncodedString())"

    static let urlSession = OWSURLSession(
        baseUrl: URL(string: "https://api.stripe.com/v1/")!,
        securityPolicy: OWSURLSession.defaultSecurityPolicy,
        configuration: URLSessionConfiguration.ephemeral,
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

        static func parameters(for payment: PKPayment) -> [String: any StripeQueryParamValue] {
            var parameters = [String: any StripeQueryParamValue]()
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
                parameters["pk_token_transaction_id"] = payment.token.transactionIdentifier.nilIfEmpty
            }

            return parameters
        }

        static func parameters(for contact: PKContact) -> [String: any StripeQueryParamValue] {
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

        /// Get the query parameters for a request to make a Stripe card token.
        ///
        /// See [Stripe's docs][0].
        ///
        /// [0]: https://stripe.com/docs/api/tokens/create_card
        static func parameters(
            for creditOrDebitCard: PaymentMethod.CreditOrDebitCard,
        ) -> [String: String] {
            func pad(_ n: UInt8) -> String { n < 10 ? "0\(n)" : "\(n)" }
            return [
                "card[number]": creditOrDebitCard.cardNumber,
                "card[exp_month]": pad(creditOrDebitCard.expirationMonth),
                "card[exp_year]": pad(creditOrDebitCard.expirationTwoDigitYear),
                "card[cvc]": String(creditOrDebitCard.cvv),
            ]
        }

        typealias Token = String

        /// Step 3 of the process. Payment source tokenization
        static func createToken(with tokenizationParameters: [String: any StripeQueryParamValue]) async throws -> Token {
            let response = try await postForm(endpoint: "tokens", parameters: tokenizationParameters)
            guard let parser = response.responseBodyParamParser else {
                throw OWSAssertionError("Missing or invalid JSON!")
            }
            return try parser.required(key: "id")
        }

        /// Make a `POST` request to the Stripe API.
        static func postForm(
            endpoint: String,
            parameters: [String: any StripeQueryParamValue],
            idempotencyKey: String? = nil,
        ) async throws -> HTTPResponse {
            let formData = Data(try parameters.encodeStripeQueryParamValueToString().utf8)

            var headers: HttpHeaders = [
                "Content-Type": "application/x-www-form-urlencoded",
                "Authorization": authorizationHeader,
            ]
            if let idempotencyKey {
                headers["Idempotency-Key"] = idempotencyKey
            }

            return try await urlSession.performRequest(
                endpoint,
                method: .post,
                headers: headers,
                body: formData,
            )
        }
    }
}

// MARK: - Encoding URL query parameters

private func percentEncodeStringForQueryParam(_ string: String) throws -> String {
    // characters not allowed taken from RFC 3986 Section 2.1 with exceptions for ? and / from RFC 3986 Section 3.4
    var charactersAllowed = CharacterSet.urlQueryAllowed
    charactersAllowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
    guard let result = string.addingPercentEncoding(withAllowedCharacters: charactersAllowed) else {
        throw OWSAssertionError("string percent encoding for query param failed")
    }
    return result
}

/// This protocol is only exposed internal to the module for testing. Do not use.
protocol StripeQueryParamValue {
    func encodeStripeQueryParamValueToString(key: String) throws -> String
}

extension String: StripeQueryParamValue {
    func encodeStripeQueryParamValueToString(key: String) throws -> String {
        let keyEncoded = try percentEncodeStringForQueryParam(key)
        let valueEncoded = try percentEncodeStringForQueryParam(self)
        return "\(keyEncoded)=\(valueEncoded)"
    }
}

extension NSNull: StripeQueryParamValue {
    func encodeStripeQueryParamValueToString(key: String) throws -> String {
        return try percentEncodeStringForQueryParam(key)
    }
}

extension Dictionary<String, any StripeQueryParamValue>: StripeQueryParamValue {
    func encodeStripeQueryParamValueToString(key: String = "") throws -> String {
        var pairs: [String] = []
        for subKey in keys.sorted() {
            let value = self[subKey]!
            let keyName: String
            if key.isEmpty {
                keyName = subKey
            } else {
                keyName = "\(key)[\(subKey)]"
            }
            pairs.append(try value.encodeStripeQueryParamValueToString(key: keyName))
        }
        return pairs.joined(separator: "&")
    }
}

// MARK: - Converting to StripeError

extension Stripe {
    private static func convertToStripeErrorIfPossible(_ error: Error) -> Error {
        guard
            let responseData = error.httpResponseData,
            let responseDict = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let errorJson = responseDict["error"] as? [String: Any],
            let code = errorJson["code"] as? String,
            !code.isEmpty
        else {
            return error
        }
        return StripeError(code: code)
    }
}

// MARK: - Currency

// See https://stripe.com/docs/currencies

public extension Stripe {
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
        "CHF",
    ]
    static let preferredCurrencyInfos: [Currency.Info] = {
        Currency.infos(for: preferredCurrencyCodes, ignoreMissingNames: true, shouldSort: false)
    }()
}

// MARK: - Callbacks

public extension Stripe {

    private static func isStripeIDEALCallback(_ url: URL) -> Bool {
        if
            url.scheme == "https",
            url.host == "signaldonations.org",
            url.path == "/ideal",
            url.user == nil,
            url.password == nil,
            url.port == nil
        {
            return true
        }

        if
            url.scheme == "sgnl",
            url.host == "ideal",
            url.path.isEmpty,
            url.user == nil,
            url.password == nil,
            url.port == nil
        {
            return true
        }

        return false
    }

    enum IDEALCallbackType {
        case oneTime(didSucceed: Bool, paymentIntentId: String)
        case monthly(didSucceed: Bool, clientSecret: String, setupIntentId: String)
    }

    static func parseStripeIDEALCallback(_ url: URL) -> IDEALCallbackType? {
        guard
            isStripeIDEALCallback(url),
            let components = URLComponents(string: url.absoluteString),
            let queryItems = components.queryItems
        else {
            return nil
        }

        /// This is more of an optimization to allow failing fast if the payment was known to be declined.
        /// However, success is assumed and only the 'failed' state is checked here to guard against the
        /// possibility of these strings changing and causing a missing 'success' to result in a false failure.
        /// In the case that the 'failed' string changes, the app will still show the user the failed state, but it
        /// will happend later on in the donation processing flow vs. happening here.
        var redirectSuccess = true
        if
            let resultItem = queryItems.first(where: { $0.name == "redirect_status" }),
            let resultString = resultItem.value,
            resultString == "failed"
        {
            redirectSuccess = false
        }

        if
            let intentItem = queryItems.first(where: { $0.name == "payment_intent" }),
            let paymentIntentId = intentItem.value
        {
            return .oneTime(
                didSucceed: redirectSuccess,
                paymentIntentId: paymentIntentId,
            )
        }

        if
            let clientSecretItem = queryItems.first(where: { $0.name == "setup_intent_client_secret" }),
            let clientSecret = clientSecretItem.value,
            let intentItem = queryItems.first(where: { $0.name == "setup_intent" }),
            let setupIntentId = intentItem.value
        {
            return .monthly(
                didSucceed: redirectSuccess,
                clientSecret: clientSecret,
                setupIntentId: setupIntentId,
            )
        }

        return nil
    }
}
