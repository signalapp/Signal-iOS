//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension OWSRequestFactory {
    enum StripePaymentMethod {
        public enum BankTransfer: String {
            case sepa = "SEPA_DEBIT"
        }

        case card
        case bankTransfer(BankTransfer)

        fileprivate var rawValue: String {
            switch self {
            case .card:
                return "CARD"
            case .bankTransfer(let bankTransfer):
                return bankTransfer.rawValue
            }
        }
    }

    private enum BoostApiPaths {
        private static let basePath = "v1/subscription/boost"

        static let stripeCreatePaymentIntent = "\(basePath)/create"
        static let paypalCreatePayment = "\(basePath)/paypal/create"
        static let paypalConfirmPayment = "\(basePath)/paypal/confirm"
    }

    /// A request to create a Stripe payment intent for a boost.
    static func boostStripeCreatePaymentIntent(
        integerMoneyValue: UInt,
        inCurrencyCode currencyCode: Currency.Code,
        level: UInt64,
        paymentMethod: StripePaymentMethod
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: BoostApiPaths.stripeCreatePaymentIntent)!,
            method: HTTPMethod.post.methodName,
            parameters: [
                "currency": currencyCode.lowercased(),
                "amount": integerMoneyValue,
                "level": level,
                "paymentMethod": paymentMethod.rawValue
            ]
        )
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    /// A request to create a PayPal payment for a boost.
    static func boostPaypalCreatePayment(
        integerMoneyValue: UInt,
        inCurrencyCode currencyCode: Currency.Code,
        level: UInt64,
        returnUrl: URL,
        cancelUrl: URL
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: BoostApiPaths.paypalCreatePayment)!,
            method: HTTPMethod.post.methodName,
            parameters: [
                "currency": currencyCode.lowercased(),
                "amount": integerMoneyValue,
                "level": level,
                "returnUrl": returnUrl.absoluteString,
                "cancelUrl": cancelUrl.absoluteString
            ]
        )

        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    /// A request to confirm a PayPal payment for a one-time payment.
    static func oneTimePaypalConfirmPayment(
        integerMoneyValue: UInt,
        inCurrencyCode currencyCode: Currency.Code,
        level: UInt64,
        payerId: String,
        paymentId: String,
        paymentToken: String
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: BoostApiPaths.paypalConfirmPayment)!,
            method: HTTPMethod.post.methodName,
            parameters: [
                "currency": currencyCode.lowercased(),
                "amount": integerMoneyValue,
                "level": level,
                "payerId": payerId,
                "paymentId": paymentId,
                "paymentToken": paymentToken
            ]
        )

        request.shouldHaveAuthorizationHeaders = false
        return request
    }
}
