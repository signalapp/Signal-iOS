//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Create a payment

public extension Paypal {
    /// Create a payment and get a PayPal approval URL to present to the user.
    static func createBoost(
        amount: FiatMoney,
        level: OneTimeBadgeLevel
    ) -> Promise<URL> {
        firstly(on: .sharedUserInitiated) {
            let createBoostRequest = OWSRequestFactory.boostPaypalCreatePayment(
                integerMoneyValue: DonationUtilities.integralAmount(for: amount),
                inCurrencyCode: amount.currencyCode,
                level: level.rawValue,
                returnUrl: Paypal.returnUrl,
                cancelUrl: Paypal.cancelUrl
            )

            return networkManager.makePromise(request: createBoostRequest)
        }.map(on: .sharedUserInitiated) { response throws -> URL in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("[Donations] Missing or invalid JSON")
            }

            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("[Donations] Failed to decode JSON response")
            }

            let approvalUrlString: String = try parser.required(key: "approvalUrl")

            guard let approvalUrl = URL(string: approvalUrlString) else {
                throw OWSAssertionError("[Donations] Approval URL was not a valid URL!")
            }

            return approvalUrl
        }
    }
}

// MARK: - Confirm a payment

public extension Paypal {
    /// Confirms a payment after a successful authentication via PayPal's web
    /// UI. Returns a payment ID that can be used to get receipt credentials.
    static func confirmBoost(
        amount: FiatMoney,
        level: OneTimeBadgeLevel,
        approvalParams: WebAuthApprovalParams
    ) -> Promise<String> {
        firstly(on: .sharedUserInitiated) {
            let confirmBoostRequest = OWSRequestFactory.boostPaypalConfirmPayment(
                integerMoneyValue: DonationUtilities.integralAmount(for: amount),
                inCurrencyCode: amount.currencyCode,
                level: level.rawValue,
                payerId: approvalParams.payerId,
                paymentId: approvalParams.paymentId,
                paymentToken: approvalParams.paymentToken
            )

            return networkManager.makePromise(request: confirmBoostRequest)
        }.map(on: .sharedUserInitiated) { response throws -> String in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("[Donations] Missing or invalid JSON")
            }

            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("[Donations] Failed to decode JSON response")
            }

            return try parser.required(key: "paymentId")
        }
    }
}
