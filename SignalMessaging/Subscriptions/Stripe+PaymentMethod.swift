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

        public struct SEPA: Equatable {
            // Payment info
            public let name: String
            public let iban: String
            public let email: String

            /// Creates a SEPA account.
            ///
            /// These fields should be fully valid.
            public init(name: String, iban: String, email: String) {
                self.name = name
                self.iban = iban
                self.email = email
            }

            public var country: String {
                String(iban.prefix(2))
            }
        }

        /// A representation of a user's acceptance of the bank transfer mandate.
        ///
        /// - Important: Never instantiate this unless the user has seen and accepted the mandate.
        public struct Mandate: Equatable {
            public enum Mode: Equatable {
                case online(userAgent: String, ipAddress: String)
            }

            private let mode: Mode

            public init(mode: Mode) {
                self.mode = mode
            }

            var parameters: [String: any Encodable] {
                switch mode {
                case .online(let userAgent, let ipAddress):
                    return [
                        "mandate_data[customer_acceptance][type]": "online",
                        "mandate_data[customer_acceptance][online][user_agent]": userAgent,
                        "mandate_data[customer_acceptance][online][ip_address]": ipAddress,
                    ]
                }
            }
        }

        case applePay(payment: PKPayment)
        case creditOrDebitCard(creditOrDebitCard: CreditOrDebitCard)
        case bankTransferSEPA(mandate: Mandate, account: SEPA)

        public var stripePaymentMethod: OWSRequestFactory.StripePaymentMethod {
            switch self {
            case .applePay, .creditOrDebitCard:
                return .card
            case .bankTransferSEPA:
                return .bankTransfer(.sepa)
            }
        }

        var mandate: Mandate? {
            switch self {
            case .applePay, .creditOrDebitCard:
                return nil
            case let .bankTransferSEPA(mandate: sepaMandate, account: _):
                return sepaMandate
            }
        }
    }
}
