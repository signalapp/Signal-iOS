//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonationViewsUtil {
    typealias ErrorSheetDetails = (message: String, actions: ErrorSheetActions)

    enum ErrorSheetActions {
        /// Show a simple "OK" to dismiss the error.
        case dismiss
        /// Show a "learn more" button with the given URL along with an "OK" to dismiss the error.
        case learnMore(link: URL)
    }

    static func localizedDonationFailure(
        chargeErrorCode: String?,
        paymentMethod: DonationPaymentMethod?
    ) -> ErrorSheetDetails {
        switch paymentMethod {
        case .applePay:
            let errorMessage = localizedDonationFailureForApplePay(chargeErrorCode: chargeErrorCode)
            return (errorMessage, .dismiss)
        case .creditOrDebitCard:
            let errorMessage =  localizedDonationFailureForCreditOrDebitCard(chargeErrorCode: chargeErrorCode)
            return (errorMessage, .dismiss)
        case .paypal, nil:
            // TODO: [PayPal] Use the charge error code to put together a non-generic error.
            let errorMessage = OWSLocalizedString(
                "SUSTAINER_VIEW_CANT_ADD_BADGE_MESSAGE",
                comment: "Action sheet message for Couldn't Add Badge sheet"
            )
            return (errorMessage, .dismiss)
        case .sepa, .ideal:
            return localizedDonationFailureForSEPA(chargeErrorCode: chargeErrorCode)
        }
    }

    private static func localizedDonationFailureForApplePay(chargeErrorCode: String?) -> String {
        switch chargeErrorCode {
        case "authentication_required":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_AUTHENTICATION_REQUIRED",
                comment: "Apple Pay donation error for decline failures where authentication is required."
            )
        case "approve_with_id":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_PAYMENT_CANNOT_BE_AUTHORIZED",
                comment: "Apple Pay donation error for decline failures where the payment cannot be authorized."
            )
        case "call_issuer":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_CALL_ISSUER",
                comment: "Apple Pay donation error for decline failures where the user may need to contact their card or bank."
            )
        case "card_not_supported":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_CARD_NOT_SUPPORTED",
                comment: "Apple Pay donation error for decline failures where the card is not supported."
            )
        case "expired_card":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_EXPIRED_CARD",
                comment: "Apple Pay donation error for decline failures where the card has expired."
            )
        case "incorrect_number":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INCORRECT_CARD_NUMBER",
                comment: "Apple Pay donation error for decline failures where the card number is incorrect."
            )
        case "incorrect_cvc", "invalid_cvc":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INCORRECT_CARD_VERIFICATION_CODE",
                comment: "Apple Pay donation error for decline failures where the card verification code (often called CVV or CVC) is incorrect."
            )
        case "insufficient_funds":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INSUFFICIENT_FUNDS",
                comment: "Apple Pay donation error for decline failures where the card has insufficient funds."
            )
        case "invalid_expiry_month":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_EXPIRY_MONTH",
                comment: "Apple Pay donation error for decline failures where the expiration month on the payment method is incorrect."
            )
        case "invalid_expiry_year":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_EXPIRY_YEAR",
                comment: "Apple Pay donation error for decline failures where the expiration year on the payment method is incorrect."
            )
        case "invalid_number":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_NUMBER",
                comment: "Apple Pay donation error for decline failures where the card number is incorrect."
            )
        case "issuer_not_available", "processing_error", "reenter_transaction":
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_ISSUER_NOT_AVAILABLE",
                comment: "Apple Pay donation error for \"issuer not available\" decline failures. The user should try again or contact their card/bank."
            )
        default:
            return OWSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_OTHER",
                comment: "Apple Pay donation error for unspecified decline failures."
            )
        }
    }

    private static func localizedDonationFailureForCreditOrDebitCard(chargeErrorCode: String?) -> String {
        switch chargeErrorCode {
        case "approve_with_id":
            return OWSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_PAYMENT_CANNOT_BE_AUTHORIZED",
                comment: "Credit/debit card donation error for decline failures where the payment cannot be authorized."
            )
        case "expired_card":
            return OWSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_EXPIRED_CARD",
                comment: "Credit/debit card donation error for decline failures where the card has expired."
            )
        case "incorrect_number", "invalid_number":
            return OWSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_INCORRECT_CARD_NUMBER",
                comment: "Credit/debit card donation error for decline failures where the card number is incorrect."
            )
        case "incorrect_cvc", "invalid_cvc":
            return OWSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_INCORRECT_CARD_VERIFICATION_CODE",
                comment: "Credit/debit card donation error for decline failures where the card verification code (often called CVV or CVC) is incorrect."
            )
        case "invalid_expiry_month":
            return OWSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_INVALID_EXPIRY_MONTH",
                comment: "Credit/debit card donation error for decline failures where the expiration month on the payment method is incorrect."
            )
        case "invalid_expiry_year":
            return OWSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_INVALID_EXPIRY_YEAR",
                comment: "Credit/debit card donation error for decline failures where the expiration year on the payment method is incorrect."
            )
        default:
            return OWSLocalizedString(
                "CREDIT_OR_DEBIT_CARD_DONATION_ERROR_OTHER",
                comment: "Credit/debit card donation error for unspecified decline failures."
            )
        }
    }

    private static func localizedDonationFailureForSEPA(chargeErrorCode: String?) -> ErrorSheetDetails {
        let message: String
        let actions: ErrorSheetActions
        switch chargeErrorCode {
        case "insufficient_funds":
            message = OWSLocalizedString(
                "SEPA_DONATION_ERROR_INSUFFICIENT_FUNDS",
                comment: "SEPA bank account donation error for insufficient funds."
            )
            actions = .learnMore(link: SupportConstants.badgeExpirationLearnMoreURL)
        case "debit_not_authorized":
            message = OWSLocalizedString(
                "SEPA_DONATION_ERROR_PAYMENT_NOT_AUTHORIZED",
                comment: "SEPA bank account donation error for the payment not being authorizing by the account holder."
            )
            actions = .learnMore(link: SupportConstants.badgeExpirationLearnMoreURL)
        case "account_closed", "bank_account_restricted", "recipient_deceased":
            message = OWSLocalizedString(
                "SEPA_DONATION_ERROR_NOT_PROCESSED",
                comment: "SEPA bank account donation error for the account details not being able to be processed."
            )
            actions = .learnMore(link: SupportConstants.badgeExpirationLearnMoreURL)
        case "debit_authorization_not_match":
            message = OWSLocalizedString(
                "SEPA_DONATION_ERROR_NOT_AUTHORIZED",
                comment: "SEPA bank account donation error for missing or incorrect mandate information."
            )
            actions = .learnMore(link: SupportConstants.badgeExpirationLearnMoreURL)
        case "debit_disputed":
            fallthrough
        case "branch_does_not_exist", "incorrect_account_holder_name", "invalid_account_number", "generic_could_not_process", "refer_to_customer":
            fallthrough
        default:
            message = OWSLocalizedString(
                "SEPA_DONATION_ERROR_OTHER",
                comment: "SEPA bank account donation error for unspecified decline failures."
            )
            actions = .dismiss
        }

        return (message, actions)
    }
}
