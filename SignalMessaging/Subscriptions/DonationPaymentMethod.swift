//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Payment methods that a user could pay with.
///
/// May be confused with ``Stripe/PaymentMethod``, which represents a payment
/// method that's ready to submit to Stripe.
///
/// To get a new payment method to show up in the donation sheet:
/// 1. Add a new enum case here.
/// 1. Add decoding for it to `parseSupportedPaymentMethods(fromParser:)`
/// in ``SubscriptionManagerImpl/DonationConfiguration``.
/// 1. Add it in its proper sort order to the lists in `DonateChoosePaymentMethodSheet.updateBottom()`.
public enum DonationPaymentMethod: String {
    case applePay
    case creditOrDebitCard
    case paypal
    case sepa

    var paymentProcessor: PaymentProcessor {
        switch self {
        case .applePay, .creditOrDebitCard, .sepa:
            return .stripe
        case .paypal:
            return .braintree
        }
    }
}
