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
    public static func createSignalPaymentMethodForSubscription(subscriberId: Data) -> Promise<String> {
        return firstly {
            let request = OWSRequestFactory.subscriptionCreateStripePaymentMethodRequest(subscriberId.asBase64Url)

            return networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            let statusCode = response.responseStatusCode

            guard statusCode == 200 else {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }

            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            do {
                let clientSecret: String = try parser.required(key: "clientSecret")
                return clientSecret
            } catch {
                throw OWSAssertionError("Missing clientID key")
            }
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
        paymentMethod: PaymentMethod,
        show3DS: @escaping (URL) -> Promise<Void>
    ) -> Promise<String> {
        firstly {
            createPaymentMethod(with: paymentMethod)
        }.then(on: DispatchQueue.sharedUserInitiated) { paymentId -> Promise<String> in
            firstly { () -> Promise<ConfirmedIntent> in
                confirmSetupIntent(for: paymentId, clientSecret: clientSecret)
            }.then(on: DispatchQueue.sharedUserInitiated) { confirmedIntent -> Promise<Void> in
                if let redirectToUrl = confirmedIntent.redirectToUrl {
                    return show3DS(redirectToUrl)
                } else {
                    return Promise.value(())
                }
            }.map(on: DispatchQueue.sharedUserInitiated) {
                paymentId
            }
        }
    }
}
