//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

/// Represents an error encountered while making a receipt credential request.
///
/// These are persisted in the ``SubscriptionReceiptCredentialRequestResultStore``
/// by the ``SubscriptionReceiptCredentialRedemptionJobQueue``'s
/// ``SubscriptionReceiptCredentailRedemptionOperation``.
public struct SubscriptionReceiptCredentialRequestError: Codable, Equatable {
    public enum ErrorCode: Int {
        case paymentStillProcessing = 204
        case paymentFailed = 402

        case localValidationFailed = 1
        case serverValidationFailed = 400
        case paymentNotFound = 404
        case paymentIntentRedeemed = 409
    }

    public let errorCode: ErrorCode

    /// If our error code is `.paymentFailed`, this holds the associated charge
    /// failure.
    ///
    /// We may have legacy or exceptional `.paymentFailed` errors persisted with
    /// this `nil`.
    public let chargeFailureCodeIfPaymentFailed: String?

    /// We may have legacy errors persisted with this `nil`.
    public let badge: ProfileBadge?

    /// We may have legacy errors persisted with this `nil`.
    public let amount: FiatMoney?

    /// We may have legacy errors persisted with this `nil`.
    public let paymentMethod: DonationPaymentMethod?

    /// The epoch timestamp at which this error was created.
    public let timestampMs: UInt64

    public init(
        errorCode: ErrorCode,
        chargeFailureCodeIfPaymentFailed: String?,
        badge: ProfileBadge,
        amount: FiatMoney,
        paymentMethod: DonationPaymentMethod
    ) {
        owsAssert(
            chargeFailureCodeIfPaymentFailed == nil || errorCode == .paymentFailed,
            "Charge failure must only be populated if the error code is payment failed!"
        )

        self.errorCode = errorCode
        self.chargeFailureCodeIfPaymentFailed = chargeFailureCodeIfPaymentFailed
        self.badge = badge
        self.amount = amount
        self.paymentMethod = paymentMethod
        self.timestampMs = Date().ows_millisecondsSince1970
    }

    /// When dealing with legacy persisted data, we may only have the raw error
    /// code available. This should only be used if a full error cannot be
    /// constructed!
    public init(legacyErrorCode: ErrorCode) {
        self.errorCode = legacyErrorCode
        self.chargeFailureCodeIfPaymentFailed = nil
        self.badge = nil
        self.amount = nil
        self.paymentMethod = nil
        self.timestampMs = Date().ows_millisecondsSince1970
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case errorCode
        case chargeFailureCodeIfPaymentFailed
        case badge
        case amount
        case paymentMethod
        case timestampMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        chargeFailureCodeIfPaymentFailed = try container.decodeIfPresent(String.self, forKey: .chargeFailureCodeIfPaymentFailed)
        badge = try container.decodeIfPresent(ProfileBadge.self, forKey: .badge)
        amount = try container.decodeIfPresent(FiatMoney.self, forKey: .amount)
        timestampMs = try container.decode(UInt64.self, forKey: .timestampMs)

        let errorCodeInt = try container.decode(Int.self, forKey: .errorCode)
        let paymentMethodString = try container.decodeIfPresent(String.self, forKey: .paymentMethod)

        guard let errorCode = ErrorCode(rawValue: errorCodeInt) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [CodingKeys.errorCode],
                debugDescription: "Unexpected error code value: \(errorCodeInt)"
            ))
        }
        self.errorCode = errorCode

        guard let paymentMethodString else {
            paymentMethod = nil
            return
        }

        guard let paymentMethod = DonationPaymentMethod(rawValue: paymentMethodString) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [CodingKeys.paymentMethod],
                debugDescription: "Unexpected payment method value: \(paymentMethodString)"
            ))
        }
        self.paymentMethod = paymentMethod
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(chargeFailureCodeIfPaymentFailed, forKey: .chargeFailureCodeIfPaymentFailed)
        try container.encodeIfPresent(badge, forKey: .badge)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encode(timestampMs, forKey: .timestampMs)

        try container.encode(errorCode.rawValue, forKey: .errorCode)
        try container.encodeIfPresent(paymentMethod?.rawValue, forKey: .paymentMethod)
    }
}
