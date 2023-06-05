//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

enum CreditAndDebitCards {
    /// The type of the credit card as useful for Signal's purposes.
    enum CardType {
        case americanExpress
        case unionPay
        case other

        var cvvCount: Int {
            switch self {
            case .americanExpress: return 4
            case .unionPay, .other: return 3
            }
        }
    }

    /// The validity of a particular field.
    enum Validity {
        /// The data could be submitted if the user added some more data, but
        /// not yet. For example, "42" is a potentially valid card number.
        case potentiallyValid

        /// The data can be submitted with no modifications. Implies potential
        /// validity. For example, "4242424242424242" is a fully valid card
        /// number. The user should be allowed to submit fully valid data.
        case fullyValid

        /// The data cannot be submitted without deleting something. For
        /// example, "42XX" is an invalid card number, and the user needs to
        /// delete something to make it okay again. An error should be shown.
        case invalid

        fileprivate func combine(with other: Validity) -> Validity {
            switch (self, other) {
            case (.invalid, _), (_, .invalid):
                return .invalid
            case (.potentiallyValid, _), (_, .potentiallyValid):
                return .potentiallyValid
            default:
                return .fullyValid
            }
        }
    }

    /// Determine the card type from a card number.
    ///
    /// Only returns a few types that are useful for our purposes. Not meant
    /// for general use.
    ///
    /// - Parameter ofNumber: The card number entered by the user. May be
    ///   incomplete or invalid.
    /// - Returns: The determined card type. Again, only returns types that are
    ///   useful for Signal's purposes.
    static func cardType(ofNumber number: String) -> CardType {
        if number.starts(with: "34") || number.starts(with: "37") {
            return .americanExpress
        } else if number.starts(with: "62") || number.starts(with: "81") {
            return .unionPay
        } else {
            return .other
        }
    }

    /// Determine the validity of a card number.
    ///
    /// Card numbers are fully valid when all of these conditions are met:
    ///
    /// - All characters are digits
    /// - They are between 12 digits and 19 digits (inclusive) in length
    /// - At least one of the following is true:
    ///   - It is a UnionPay card
    ///   - The card passes a Luhn check
    ///
    /// Card numbers are potentially valid when all of these conditions are met:
    /// - They are not fully valid (see above)
    /// - All characters are digits
    /// - They are 19 or fewer digits in length
    /// - At least one of the following is true:
    ///   - They are fewer than 12 digits in length
    ///   - The user has focused the text input
    ///
    /// If a card number is neither kind of valid, then it is invalid.
    ///
    /// We need to know the focus state because it helps us determine whether
    /// the user is still typing while they're in the valid length range
    /// (12–19). For example, let's say I've entered "4242424242424" (13
    /// digits), which is Luhn-invalid. If I'm still typing, it's potentially
    /// valid—I might type another "2" and finish off my card number, making it
    /// Luhn-valid. If I'm done typing, it's invalid, because it's Luhn-invalid.
    /// We don't want to show errors while you're typing.
    ///
    /// - Parameter ofNumber: The card number as entered by the user. Should
    ///   only contain digits.
    /// - Parameter isNumberFieldFocused: Whether the user has focused the
    ///   number field.
    /// - Returns: The validity of the card number.
    static func validity(ofNumber number: String, isNumberFieldFocused: Bool) -> Validity {
        guard number.count <= 19, number.isAsciiDigitsOnly else {
            return .invalid
        }

        if number.count < 12 {
            return .potentiallyValid
        }

        let isValid: Bool
        switch cardType(ofNumber: number) {
        case .unionPay:
            isValid = true
        case .americanExpress, .other:
            isValid = number.isLuhnValid
        }

        if isValid {
            return .fullyValid
        }

        if isNumberFieldFocused {
            return .potentiallyValid
        }

        return .invalid
    }

    /// Determine the validity of an expiration date.
    ///
    /// Expiration dates are fully valid if:
    ///
    /// - There are 1 or 2 digits for the month, and parsing that as an integer
    ///   is between 1 and 12
    /// - The 2-digit year is in the next 20 years
    /// - If the year is the current year, the month is greater than or equal to
    ///   the current month
    ///
    /// Expiration dates are partially valid if you're still typing.
    ///
    /// - Parameter ofExpirationMonth: The expiration month as entered by the
    ///   user. Should only contain digits.
    /// - Parameter andYear: The expiration year as entered by the user. Should
    ///   only contain digits.
    /// - Returns: The validity of the expiration date.
    static func validity(
        ofExpirationMonth month: String,
        andYear year: String,
        currentMonth: Int,
        currentYear: Int
    ) -> Validity {
        let monthValidity = validity(ofExpirationMonth: month)
        let yearValidity = validity(ofExpirationYear: year)

        switch monthValidity.combine(with: yearValidity) {
        case .invalid: return .invalid
        case .potentiallyValid: return .potentiallyValid
        default: break
        }

        guard
            let monthInt = Int(month),
            let yearTwoDigits = Int(year)
        else {
            return .invalid
        }
        let century = currentYear / 100 * 100
        var yearInt = century + yearTwoDigits
        if yearInt < currentYear {
            yearInt += 100
        }

        if yearInt == currentYear {
            return monthInt < currentMonth ? .invalid : .fullyValid
        }

        if yearInt > currentYear + 20 {
            return .invalid
        }

        return .fullyValid
    }

    private static func validity(ofExpirationMonth monthString: String) -> Validity {
        guard monthString.count <= 2, monthString.isAsciiDigitsOnly, monthString != "00" else {
            return .invalid
        }
        if monthString.isEmpty || monthString == "0" {
            return .potentiallyValid
        }
        guard let monthInt = UInt8(monthString), monthInt >= 1, monthInt <= 12 else {
            return .invalid
        }
        return .fullyValid
    }

    private static func validity(ofExpirationYear yearString: String) -> Validity {
        guard yearString.count <= 2, yearString.isAsciiDigitsOnly else {
            return .invalid
        }
        if yearString.count < 2 {
            return .potentiallyValid
        }
        return .fullyValid
    }

    /// Determine the validity of a card verification code.
    ///
    /// CVVs are usually 3 digits long, but are 4 digits for American Express
    /// cards.
    ///
    /// - Parameter ofCvv: The card verification code as entered by the user.
    ///   Should only contain digits.
    /// - Parameter cardType: The card type as determined elsewhere.
    /// - Returns: The validity of the CVV.
    static func validity(ofCvv cvv: String, cardType: CardType) -> Validity {
        let validLength = cardType.cvvCount

        guard cvv.count <= validLength, cvv.isAsciiDigitsOnly else {
            return .invalid
        }

        if cvv.count < validLength {
            return .potentiallyValid
        }

        return .fullyValid
    }
}

fileprivate extension String {
    var isLuhnValid: Bool {
        var checksum = 0
        var shouldDouble = false
        for character in reversed() {
            guard var digit = Int(String(character)) else {
                owsFail("Unexpected non-digit character")
            }
            if shouldDouble {
                digit *= 2
            }
            shouldDouble = !shouldDouble
            if digit >= 10 {
                digit -= 9
            }
            checksum += digit
        }
        return (checksum % 10) == 0
    }
}
