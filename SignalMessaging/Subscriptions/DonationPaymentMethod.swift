//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Payment methods that a user could pay with.
///
/// May be confused with ``Stripe.PaymentMethod``, which represents a payment
/// method that's ready to submit to Stripe.
public enum DonationPaymentMethod: String {
    case applePay
    case creditOrDebitCard
    case paypal

    var paymentProcessor: PaymentProcessor {
        switch self {
        case .applePay, .creditOrDebitCard:
            return .stripe
        case .paypal:
            return .braintree
        }
    }
}
