//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct SubscriptionFetcher {
    private let networkManager: NetworkManager
    private let retryPolicy: NetworkManager.RetryPolicy

    public init(
        networkManager: NetworkManager,
        retryPolicy: NetworkManager.RetryPolicy = .dont,
    ) {
        self.networkManager = networkManager
        self.retryPolicy = retryPolicy
    }

    public func fetch(subscriberID: Data) async throws -> Subscription? {
        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(
                .fetchSubscription(subscriberID: subscriberID),
                retryPolicy: retryPolicy,
            )
        } catch where error.httpStatusCode == 404 {
            return nil
        }

        switch response.responseStatusCode {
        case 200:
            guard let parser = response.responseBodyParamParser else {
                throw OWSAssertionError("Missing or invalid response body!")
            }

            guard let subscriptionDict: [String: Any] = try parser.optional(key: "subscription") else {
                return nil
            }

            let chargeFailureDict: [String: Any]? = try parser.optional(key: "chargeFailure")

            return try Subscription(
                subscriptionDict: subscriptionDict,
                chargeFailureDict: chargeFailureDict,
            )
        default:
            throw OWSAssertionError("Got bad response code! \(response.responseStatusCode)")
        }
    }

}

private extension TSRequest {
    static func fetchSubscription(subscriberID: Data) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberID.asBase64Url)")!,
            method: "GET",
            parameters: nil,
        )
        result.auth = .anonymous
        result.applyRedactionStrategy(.redactURL())
        return result
    }
}

// MARK: -

/// Represents a *recurring* subscription, associated with a subscriber ID and
/// fetched from the service using that ID.
public struct Subscription: Equatable {
    public struct ChargeFailure: Equatable {
        /// The error code reported by the server.
        ///
        /// If nil, we know there was a charge failure but don't know the code. This is unusual,
        /// but can happen if the server sends an invalid response.
        public let code: String?

        init(jsonDictionary: [String: Any]) {
            code = try? ParamParser(jsonDictionary).optional(key: "code")
        }
    }

    /// The state of the subscription as understood by the backend
    ///
    /// A subscription will be in the `active` state as long as the current
    /// subscription payment has been successfully processed by the payment
    /// processor.
    ///
    /// - Note
    /// Signal servers get a callback when a subscription is going to renew. If
    /// the user hasn't performed a "subscription keep-alive in ~30-45 days, the
    /// server will, upon getting that callback, cancel the subscription.
    public enum SubscriptionStatus: Equatable {
        /// Indicates the subscription has been paid successfully for the
        /// current period, and all is well.
        case active

        /// Indicates the subscription has been unrecoverably canceled. This may
        /// be due to terminal failures while renewing (in which case the charge
        /// failure should be populated), or due to inactivity (in which case
        /// there will be no charge failure, as Signal servers canceled the
        /// subscription artificially).
        case canceled

        /// Indicates the subscription failed to renew, but the payment
        /// processor is planning to retry the renewal. If the future renewal
        /// succeeds, the subscription will go back to being "active". Continued
        /// renewal failures will result in the subscription being canceled.
        ///
        /// - Note
        /// Retries are not predictable, but are expected to happen on the scale
        /// of days, for up to circa two weeks.
        case pastDue

        /// An unrecognized status.
        case unrecognized(rawValue: String)

        init(rawValue: String) {
            switch rawValue {
            case "active": self = .active
            case "canceled": self = .canceled
            case "past_due": self = .pastDue
            default: self = .unrecognized(rawValue: rawValue)
            }
        }
    }

    public let level: UInt
    public let amount: FiatMoney
    public let endOfCurrentPeriod: Date
    public let active: Bool
    public let cancelAtEndOfPeriod: Bool
    public let status: SubscriptionStatus

    /// The payment processor, if a recognized processor for donations.
    public let donationPaymentProcessor: DonationPaymentProcessor?
    /// The payment method, if a recognized method for donations.
    /// - Note
    /// This will never be `.applePay`, since the server treats Apple Pay
    /// payments like credit card payments.
    public let donationPaymentMethod: DonationPaymentMethod?

    /// Whether the payment for this subscription is actively processing, and
    /// has not yet succeeded nor failed.
    public let isPaymentProcessing: Bool

    /// Indicates that payment for this subscription failed.
    public let chargeFailure: ChargeFailure?

    public var debugDescription: String {
        [
            "Subscription",
            "End of current period: \(endOfCurrentPeriod)",
            "Cancel at end of period?: \(cancelAtEndOfPeriod)",
            "Status: \(status)",
            "Charge failure: \(chargeFailure.debugDescription)",
        ].joined(separator: ". ")
    }

    public init(subscriptionDict: [String: Any], chargeFailureDict: [String: Any]?) throws {
        let params = ParamParser(subscriptionDict)
        level = try params.required(key: "level")
        let currencyCode: Currency.Code = try {
            let raw: String = try params.required(key: "currency")
            return raw.uppercased()
        }()
        amount = FiatMoney(
            currencyCode: currencyCode,
            value: try {
                let integerValue: Int64 = try params.required(key: "amount")
                let decimalValue = Decimal(integerValue)
                if DonationUtilities.zeroDecimalCurrencyCodes.contains(currencyCode) {
                    return decimalValue
                } else {
                    return decimalValue / 100
                }
            }(),
        )
        let _endOfCurrentPeriod: TimeInterval = try params.required(key: "endOfCurrentPeriod")
        endOfCurrentPeriod = Date(timeIntervalSince1970: _endOfCurrentPeriod)
        active = try params.required(key: "active")
        cancelAtEndOfPeriod = try params.required(key: "cancelAtPeriodEnd")
        status = SubscriptionStatus(rawValue: try params.required(key: "status"))

        let processorString: String = try params.required(key: "processor")
        if let donationPaymentProcessor = DonationPaymentProcessor(rawValue: processorString) {
            self.donationPaymentProcessor = donationPaymentProcessor
        } else if BackupPaymentProcessor(rawValue: processorString) != nil {
            self.donationPaymentProcessor = nil
        } else {
            owsFailDebug("[Donations] Unrecognized payment processor while parsing subscription: \(processorString)")
            self.donationPaymentProcessor = nil
        }

        let paymentMethodString: String? = try params.optional(key: "paymentMethod")
        if let donationPaymentMethod = paymentMethodString.map({ DonationPaymentMethod(serverRawValue: $0) }) {
            self.donationPaymentMethod = donationPaymentMethod
        } else if paymentMethodString.map({ BackupPaymentMethod(rawValue: $0) }) != nil {
            self.donationPaymentMethod = nil
        } else {
            owsFailDebug("[Donations] Unrecognized payment method while parsing subscription: \(paymentMethodString ?? "nil")")
            self.donationPaymentMethod = nil
        }

        isPaymentProcessing = try params.required(key: "paymentProcessing")

        if let chargeFailureDict {
            chargeFailure = ChargeFailure(jsonDictionary: chargeFailureDict)
        } else {
            chargeFailure = nil
        }
    }
}
