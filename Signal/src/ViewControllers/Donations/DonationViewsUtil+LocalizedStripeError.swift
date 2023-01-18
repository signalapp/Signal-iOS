//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonationViewsUtil {
    static func localizedDonationFailure(
        chargeErrorCode: String?,
        paymentMethod: DonationPaymentMethod?
    ) -> String {
        switch paymentMethod {
        case .applePay:
            return localizedDonationFailureForApplePay(chargeErrorCode: chargeErrorCode)
        case .creditOrDebitCard:
            return localizedDonationFailureForCreditOrDebitCard(chargeErrorCode: chargeErrorCode)
        case .paypal, nil:
            // TODO: [PayPal] Use the charge error code to put together a non-generic error.
            return OWSLocalizedString(
                "SUSTAINER_VIEW_CANT_ADD_BADGE_MESSAGE",
                comment: "Action sheet message for Couldn't Add Badge sheet"
            )
        }
    }

    private static func localizedDonationFailureForApplePay(chargeErrorCode: String?) -> String {
        switch chargeErrorCode {
        case "authentication_required":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_AUTHENTICATION_REQUIRED",
                comment: "Apple Pay donation error for decline failures where authentication is required."
            )
        case "approve_with_id":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_PAYMENT_CANNOT_BE_AUTHORIZED",
                comment: "Apple Pay donation error for decline failures where the payment cannot be authorized."
            )
        case "call_issuer":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_CALL_ISSUER",
                comment: "Apple Pay donation error for decline failures where the user may need to contact their card or bank."
            )
        case "card_not_supported":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_CARD_NOT_SUPPORTED",
                comment: "Apple Pay donation error for decline failures where the card is not supported."
            )
        case "expired_card":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_EXPIRED_CARD",
                comment: "Apple Pay donation error for decline failures where the card has expired."
            )
        case "incorrect_number":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INCORRECT_CARD_NUMBER",
                comment: "Apple Pay donation error for decline failures where the card number is incorrect."
            )
        case "incorrect_cvc", "invalid_cvc":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INCORRECT_CARD_VERIFICATION_CODE",
                comment: "Apple Pay donation error for decline failures where the card verification code (often called CVV or CVC) is incorrect."
            )
        case "insufficient_funds":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INSUFFICIENT_FUNDS",
                comment: "Apple Pay donation error for decline failures where the card has insufficient funds."
            )
        case "invalid_expiry_month":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_EXPIRY_MONTH",
                comment: "Apple Pay donation error for decline failures where the expiration month on the payment method is incorrect."
            )
        case "invalid_expiry_year":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_EXPIRY_YEAR",
                comment: "Apple Pay donation error for decline failures where the expiration year on the payment method is incorrect."
            )
        case "invalid_number":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_NUMBER",
                comment: "Apple Pay donation error for decline failures where the card number is incorrect."
            )
        case "issuer_not_available", "processing_error", "reenter_transaction":
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_ISSUER_NOT_AVAILABLE",
                comment: "Apple Pay donation error for \"issuer not available\" decline failures. The user should try again or contact their card/bank."
            )
        default:
            return NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_OTHER",
                comment: "Apple Pay donation error for unspecified decline failures."
            )
        }
    }

    private static func localizedDonationFailureForCreditOrDebitCard(chargeErrorCode: String?) -> String {
        switch chargeErrorCode {
        case "approve_with_id":
            return NSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_PAYMENT_CANNOT_BE_AUTHORIZED",
                comment: "Credit/debit card donation error for decline failures where the payment cannot be authorized."
            )
        case "expired_card":
            return NSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_EXPIRED_CARD",
                comment: "Credit/debit card donation error for decline failures where the card has expired."
            )
        case "incorrect_number", "invalid_number":
            return NSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_INCORRECT_CARD_NUMBER",
                comment: "Credit/debit card donation error for decline failures where the card number is incorrect."
            )
        case "incorrect_cvc", "invalid_cvc":
            return NSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_INCORRECT_CARD_VERIFICATION_CODE",
                comment: "Credit/debit card donation error for decline failures where the card verification code (often called CVV or CVC) is incorrect."
            )
        case "invalid_expiry_month":
            return NSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_INVALID_EXPIRY_MONTH",
                comment: "Credit/debit card donation error for decline failures where the expiration month on the payment method is incorrect."
            )
        case "invalid_expiry_year":
            return NSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_INVALID_EXPIRY_YEAR",
                comment: "Credit/debit card donation error for decline failures where the expiration year on the payment method is incorrect."
            )
        default:
            return NSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_OTHER",
                comment: "Credit/debit card donation error for unspecified decline failures."
            )
        }
    }
}
