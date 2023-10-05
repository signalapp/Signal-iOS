//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Boost

public extension Paypal {
    /// Create a payment and get a PayPal approval URL to present to the user.
    static func createBoost(
        amount: FiatMoney,
        level: OneTimeBadgeLevel
    ) -> Promise<URL> {
        firstly(on: DispatchQueue.sharedUserInitiated) {
            let createBoostRequest = OWSRequestFactory.boostPaypalCreatePayment(
                integerMoneyValue: DonationUtilities.integralAmount(for: amount),
                inCurrencyCode: amount.currencyCode,
                level: level.rawValue,
                returnUrl: Self.webAuthReturnUrl,
                cancelUrl: Self.webAuthCancelUrl
            )

            return networkManager.makePromise(request: createBoostRequest)
        }.map(on: DispatchQueue.sharedUserInitiated) { response throws -> URL in
            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("[Donations] Failed to decode JSON response")
            }

            let approvalUrlString: String = try parser.required(key: "approvalUrl")

            guard let approvalUrl = URL(string: approvalUrlString) else {
                throw OWSAssertionError("[Donations] Approval URL was not a valid URL!")
            }

            return approvalUrl
        }
    }

    /// Confirms a payment after a successful authentication via PayPal's web
    /// UI. Returns a payment ID that can be used to get receipt credentials.
    static func confirmOneTimePayment(
        amount: FiatMoney,
        level: OneTimeBadgeLevel,
        approvalParams: OneTimePaymentWebAuthApprovalParams
    ) -> Promise<String> {
        firstly(on: DispatchQueue.sharedUserInitiated) {
            let confirmOneTimePaymentRequest = OWSRequestFactory.oneTimePaypalConfirmPayment(
                integerMoneyValue: DonationUtilities.integralAmount(for: amount),
                inCurrencyCode: amount.currencyCode,
                level: level.rawValue,
                payerId: approvalParams.payerId,
                paymentId: approvalParams.paymentId,
                paymentToken: approvalParams.paymentToken
            )

            return networkManager.makePromise(request: confirmOneTimePaymentRequest)
        }.map(on: DispatchQueue.sharedUserInitiated) { response throws -> String in
            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("[Donations] Failed to decode JSON response")
            }

            return try parser.required(key: "paymentId")
        }
    }
}

// MARK: - Subscription

public extension Paypal {
    struct SubscriptionAuthorizationParams {
        /// A URL to present to the user to authorize the subscription.
        public let approvalUrl: URL

        /// An opaque ID identifying the payment method, for API calls after
        /// subscription authorization.
        public let paymentMethodId: String
    }

    /// Create a payment method entry with the Signal service for a subscription
    /// processed by PayPal.
    ///
    /// - Returns
    /// PayPal params used to authorize payment for the new subscription.
    static func createSignalPaymentMethodForSubscription(
        subscriberId: Data
    ) -> Promise<SubscriptionAuthorizationParams> {
        firstly {
            let request = OWSRequestFactory.subscriptionCreatePaypalPaymentMethodRequest(
                subscriberID: subscriberId,
                returnURL: Self.webAuthReturnUrl,
                cancelURL: Self.webAuthCancelUrl
            )

            return networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.sharedUserInitiated) { response in
            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("[Donations] Missing or invalid response.")
            }

            guard let approvalUrl = URL(string: try parser.required(key: "approvalUrl")) else {
                throw OWSAssertionError("[Donations] Approval URL string was not valid URL!")
            }

            let paymentMethodId: String = try parser.required(key: "token")

            return SubscriptionAuthorizationParams(
                approvalUrl: approvalUrl,
                paymentMethodId: paymentMethodId
            )
        }
    }
}
