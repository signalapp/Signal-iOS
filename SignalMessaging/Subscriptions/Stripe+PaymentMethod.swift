//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit

/// A fully valid payment method, ready to submit to Stripe.
///
/// May be confused with ``DonationPaymentMethod``, which represents a payment
/// method the user can choose.
public extension Stripe {
    enum PaymentMethod {
        public struct CreditOrDebitCard: Equatable {
            public let cardNumber: String
            public let expirationMonth: UInt8
            public let expirationTwoDigitYear: UInt8
            public let cvv: String

            /// Creates a credit/debit card.
            ///
            /// These fields should be fully valid.
            public init(
                cardNumber: String,
                expirationMonth: UInt8,
                expirationTwoDigitYear: UInt8,
                cvv: String
            ) {
                self.cardNumber = cardNumber
                self.expirationMonth = expirationMonth
                self.expirationTwoDigitYear = expirationTwoDigitYear
                self.cvv = cvv
            }
        }

        case applePay(payment: PKPayment)
        case creditOrDebitCard(creditOrDebitCard: CreditOrDebitCard)
    }
}
