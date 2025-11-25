//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Stripe {
    /// Create a payment method entry with the Signal service for a subscription
    /// processed by Stripe.
    ///
    /// - Returns
    /// A Stripe secret used to authorize payment for the new subscription.
    public static func createSignalPaymentMethodForSubscription(subscriberId: Data) async throws -> String {
        let request = OWSRequestFactory.subscriptionCreateStripePaymentMethodRequest(subscriberID: subscriberId)

        let response = try await SSKEnvironment.shared.networkManagerRef
            .asyncRequest(request, retryPolicy: .hopefullyRecoverable)

        guard response.responseStatusCode == 200 else {
            throw response.asError()
        }

        guard let parser = response.responseBodyParamParser else {
            throw OWSAssertionError("Missing or invalid response.")
        }

        do {
            let clientSecret: String = try parser.required(key: "clientSecret")
            return clientSecret
        } catch {
            throw OWSAssertionError("Missing clientID key")
        }
    }

    /// Perform the relevant Stripe API calls to set up a new subscription with
    /// the given client secret and payment method.
    ///
    /// - Parameter clientSecret
    /// A Stripe secret retrieved from the Signal service, used to authorize
    /// payment for the new subscription. See ``createSignalPaymentMethodForSubscription(withSubscriberId:)``.
    /// - Returns
    /// The new payment ID.
    public static func setupNewSubscription(
        clientSecret: String,
        paymentMethod: PaymentMethod
    ) async throws -> ConfirmedSetupIntent {
        let paymentMethodId = try await createPaymentMethod(with: paymentMethod)
        // Pass in the correct callback URL
        return try await confirmSetupIntent(
            mandate: paymentMethod.mandate,
            paymentMethodId: paymentMethodId,
            clientSecret: clientSecret,
            callbackURL: paymentMethod.callbackURL
        )
    }
}
