//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonationPaymentDetailsViewController {
    enum InvalidFormField: Hashable {
        // Credit card
        case cardNumber
        case expirationDate
        case cvv
        // SEPA
        case iban(SEPABankAccounts.IBANInvalidity)
    }

    enum FormState: Equatable {
        enum ValidForm: Equatable {
            case card(Stripe.PaymentMethod.CreditOrDebitCard)
            case sepa(mandate: Stripe.PaymentMethod.Mandate, account: Stripe.PaymentMethod.SEPA)
            case ideal(mandate: Stripe.PaymentMethod.Mandate, account: Stripe.PaymentMethod.IDEAL)

            var stripePaymentMethod: Stripe.PaymentMethod {
                switch self {
                case let .card(card):
                    return .creditOrDebitCard(creditOrDebitCard: card)
                case let .sepa(mandate: mandate, account: sepaAccount):
                    return .bankTransferSEPA(mandate: mandate, account: sepaAccount)
                case let .ideal(mandate: mandate, account: idealAccount):
                    return .bankTransferIDEAL(mandate: mandate, account: idealAccount)
                }
            }

            var donationPaymentMethod: DonationPaymentMethod {
                switch self {
                case .card: return .creditOrDebitCard
                case .sepa: return .sepa
                case .ideal: return .ideal
                }
            }
        }

        /// At least one of the form's fields are invalid.
        case invalid(invalidFields: Set<InvalidFormField>)

        /// The form is potentially valid, but not ready to submit yet.
        case potentiallyValid

        /// The form is fully valid and ready to submit.
        case fullyValid(ValidForm)
    }

    // MARK: Card

    static func formState(
        cardNumber rawNumber: String,
        isCardNumberFieldFocused: Bool,
        expirationDate rawExpirationDate: String,
        cvv rawCvv: String
    ) -> FormState {
        var invalidFields = Set<InvalidFormField>()
        var hasPotentiallyValidFields = false

        let numberForValidation = rawNumber.removeCharacters(characterSet: .whitespaces)
        let numberValidity = CreditAndDebitCards.validity(
            ofNumber: numberForValidation,
            isNumberFieldFocused: isCardNumberFieldFocused
        )
        switch numberValidity {
        case .invalid: invalidFields.insert(.cardNumber)
        case .potentiallyValid: hasPotentiallyValidFields = true
        case .fullyValid: break
        }

        let expirationMonth: String
        let expirationTwoDigitYear: String
        let expirationValidity: CreditAndDebitCards.Validity
        let expirationDate = rawExpirationDate.removeCharacters(characterSet: .whitespaces)
        let expirationComponents = expirationDate.components(separatedBy: "/")
        let calendar = Calendar(identifier: .iso8601)
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        switch expirationComponents.count {
        case 1:
            if let parsedMonth = parseAsExpirationMonth(slashlessString: expirationDate) {
                expirationMonth = parsedMonth
                expirationTwoDigitYear = String(expirationDate.suffix(from: expirationMonth.endIndex))
                expirationValidity = CreditAndDebitCards.validity(
                    ofExpirationMonth: expirationMonth,
                    andYear: expirationTwoDigitYear,
                    currentMonth: currentMonth,
                    currentYear: currentYear
                )
            } else {
                expirationMonth = ""
                expirationTwoDigitYear = ""
                expirationValidity = .invalid(())
            }
        case 2:
            expirationMonth = expirationComponents[0]
            expirationTwoDigitYear = expirationComponents[1]
            expirationValidity = CreditAndDebitCards.validity(
                ofExpirationMonth: expirationMonth,
                andYear: expirationTwoDigitYear,
                currentMonth: currentMonth,
                currentYear: currentYear
            )
        default:
            expirationMonth = ""
            expirationTwoDigitYear = ""
            expirationValidity = .invalid(())
        }
        switch expirationValidity {
        case .invalid: invalidFields.insert(.expirationDate)
        case .potentiallyValid: hasPotentiallyValidFields = true
        case .fullyValid: break
        }

        let cvv = rawCvv.trimmingCharacters(in: .whitespaces)
        let cvvValidity = CreditAndDebitCards.validity(
            ofCvv: cvv,
            cardType: CreditAndDebitCards.cardType(ofNumber: numberForValidation)
        )
        switch cvvValidity {
        case .invalid: invalidFields.insert(.cvv)
        case .potentiallyValid: hasPotentiallyValidFields = true
        case .fullyValid: break
        }

        guard invalidFields.isEmpty else {
            return .invalid(invalidFields: invalidFields)
        }

        if hasPotentiallyValidFields {
            return .potentiallyValid
        }

        return .fullyValid(.card(Stripe.PaymentMethod.CreditOrDebitCard(
            cardNumber: numberForValidation,
            expirationMonth: {
                guard let result = UInt8(String(expirationMonth)) else {
                    owsFail("Couldn't convert exp. month to int, even though it should be valid")
                }
                return result
            }(),
            expirationTwoDigitYear: {
                guard let result = UInt8(String(expirationTwoDigitYear)) else {
                    owsFail("Couldn't convert exp. year to int, even though it should be valid")
                }
                return result
            }(),
            cvv: cvv
        )))
    }

    private static func parseAsExpirationMonth(slashlessString str: String) -> String? {
        switch str.count {
        case 0, 1:
            // The empty string should be untouched.
            // One-digits should be assumed to be months. Examples: 1, 9
            return str
        case 2:
            // If a valid month, assume that. Examples: 01, 09, 12.
            // Otherwise, assume later digits are years. Examples: 13, 98
            return str.isValidMonth ? str : String(str.prefix(1))
        case 3:
            // This is the tricky case.
            //
            // Some are unambiguously 1-digit months. Examples: 135 → 1/35, 987 → 9/87
            //
            // Some are unambigiously 2-digit months. Examples: 012 → 01/2
            //
            // Some are ambiguous. What should happen for 123?
            //
            // - If we choose what the user intended, we're good. For example,
            //   if the user types 123 and meant 1/23.
            // - If we choose 1/23 and the user meant 12/34, the field will
            //   briefly appear invalid as they type, but will resolve after
            //   they type another digit.
            // - If we choose 12/3 and the user meant 1/23, the field will be
            //   potentially valid and the user will not be able to submit.
            //
            // We choose the second option (123 → 12/34) because the brief
            // invalid state is okay, especially because we will format the
            // input which should make this case unlikely.
            //
            // Alternatively, we could change validation based on whether the
            // expiration date field is focused.
            return String(str.prefix(str.first == "0" ? 2 : 1))
        case 4:
            return String(str.prefix(2))
        default:
            return nil
        }
    }

    // MARK: SEPA

    static func formState(
        mandate: Stripe.PaymentMethod.Mandate,
        iban: String,
        isIBANFieldFocused: Bool,
        name: String,
        email: String,
        isEmailFieldFocused: Bool
    ) -> FormState {
        var invalidFields = Set<InvalidFormField>()
        var hasPotentiallyValidFields = false

        let ibanValidity = SEPABankAccounts.validity(
            of: iban.removeCharacters(characterSet: .whitespaces),
            isFieldFocused: isIBANFieldFocused
        )
        switch ibanValidity {
        case .potentiallyValid:
            hasPotentiallyValidFields = true
        case .fullyValid:
            break
        case .invalid(let invalidity):
            invalidFields.insert(.iban(invalidity))
        }

        if name.count <= 2 {
            hasPotentiallyValidFields = true
        }
        if email.isEmpty {
            hasPotentiallyValidFields = true
        }

        if !invalidFields.isEmpty {
            return .invalid(invalidFields: invalidFields)
        }

        if hasPotentiallyValidFields {
            return .potentiallyValid
        }

        // All `Mandate` instances represent an acceptance, so we don't
        // actually need to check anything specific on it

        return .fullyValid(.sepa(
            mandate: mandate,
            account: .init(
                name: name,
                iban: iban,
                email: email
            )
        ))
    }

    static func formState(
        mandate: Stripe.PaymentMethod.Mandate,
        iDEALBank: Stripe.PaymentMethod.IDEALBank?,
        name: String,
        email: String,
        isEmailFieldFocused: Bool
    ) -> FormState {
        if name.count <= 2 || email.isEmpty {
            return .potentiallyValid
        }
        guard let iDEALBank else {
            return .potentiallyValid
        }
        return .fullyValid(.ideal(
            mandate: mandate,
            account: .init(
                name: name,
                email: email,
                iDEALBank: iDEALBank
            )
        ))
    }
}

fileprivate extension String {
    /// Is this 2-character string a valid month?
    ///
    /// Not meant for general use.
    var isValidMonth: Bool {
        guard let asInt = UInt8(self) else { return false }
        return asInt >= 1 && asInt <= 12
    }
}
