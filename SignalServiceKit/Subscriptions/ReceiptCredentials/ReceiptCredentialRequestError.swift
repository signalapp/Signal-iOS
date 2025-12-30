//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Represents a recognized error returned from a receipt credential request.
public struct ReceiptCredentialRequestError: Error {
    public enum ErrorCode: Int {
        case paymentStillProcessing = 204
        case paymentFailed = 402

        case localValidationFailed = 1
        case serverValidationFailed = 400
        case paymentNotFound = 404
        case paymentIntentRedeemed = 409
    }

    public let errorCode: ErrorCode
    /// If this error represents a payment failure, contains a string from
    /// the payment processor describing the payment failure.
    public let chargeFailureCodeIfPaymentFailed: String?

    init(
        errorCode: ErrorCode,
        chargeFailureCodeIfPaymentFailed: String? = nil,
    ) {
        owsPrecondition(
            chargeFailureCodeIfPaymentFailed == nil || errorCode == .paymentFailed,
            "Must only provide a charge failure if payment failed!",
        )

        self.errorCode = errorCode
        self.chargeFailureCodeIfPaymentFailed = chargeFailureCodeIfPaymentFailed
    }
}
