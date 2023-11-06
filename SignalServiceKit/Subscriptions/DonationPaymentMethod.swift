//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Payment methods that a user could pay with.
///
/// May be confused with ``Stripe.PaymentMethod``, which represents a payment
/// method that's ready to submit to Stripe.
///
/// - Note
/// The raw value of this type is used for on-disk persistence, for historical
/// compatibility. However, a different format is used when parsing payment
/// methods from the service.
public enum DonationPaymentMethod: String {
    case applePay
    case creditOrDebitCard
    case paypal
    case sepa

    /// Parse a payment method from a string provided by the service.
    ///
    /// - Note
    /// Payments made using Apple Pay are returned as "card payments" by the
    /// service.
    public init?(serverRawValue: String) {
        switch serverRawValue {
        case "CARD":
            self = .creditOrDebitCard
        case "PAYPAL":
            self = .paypal
        case "SEPA_DEBIT":
            self = .sepa
        default:
            return nil
        }
    }
}
