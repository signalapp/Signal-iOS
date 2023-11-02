//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - Payment method field validity

/// The validity of a particular field.
enum PaymentMethodFieldValidity<Invalidity> {
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
    case invalid(Invalidity)
}

// MARK: - Credit and debit cards

extension PaymentMethodFieldValidity where Invalidity == Void {
    fileprivate func combine(with other: Self) -> Self {
        switch (self, other) {
        case (.invalid, _), (_, .invalid):
            return .invalid(())
        case (.potentiallyValid, _), (_, .potentiallyValid):
            return .potentiallyValid
        default:
            return .fullyValid
        }
    }
}

enum CreditAndDebitCards {

    typealias Validity = PaymentMethodFieldValidity<Void>

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

    // MARK: Card number

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
            return .invalid(())
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

        return .invalid(())
    }

    // MARK: Expiration

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
        case .invalid: return .invalid(())
        case .potentiallyValid: return .potentiallyValid
        default: break
        }

        guard
            let monthInt = Int(month),
            let yearTwoDigits = Int(year)
        else {
            return .invalid(())
        }
        let century = currentYear / 100 * 100
        var yearInt = century + yearTwoDigits
        if yearInt < currentYear {
            yearInt += 100
        }

        if yearInt == currentYear {
            return monthInt < currentMonth ? .invalid(()) : .fullyValid
        }

        if yearInt > currentYear + 20 {
            return .invalid(())
        }

        return .fullyValid
    }

    private static func validity(ofExpirationMonth monthString: String) -> Validity {
        guard monthString.count <= 2, monthString.isAsciiDigitsOnly, monthString != "00" else {
            return .invalid(())
        }
        if monthString.isEmpty || monthString == "0" {
            return .potentiallyValid
        }
        guard let monthInt = UInt8(monthString), monthInt >= 1, monthInt <= 12 else {
            return .invalid(())
        }
        return .fullyValid
    }

    private static func validity(ofExpirationYear yearString: String) -> Validity {
        guard yearString.count <= 2, yearString.isAsciiDigitsOnly else {
            return .invalid(())
        }
        if yearString.count < 2 {
            return .potentiallyValid
        }
        return .fullyValid
    }

    // MARK: CVV

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
            return .invalid(())
        }

        if cvv.count < validLength {
            return .potentiallyValid
        }

        return .fullyValid
    }
}

// MARK: Luhn Validation

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

// MARK: - SEPA bank accounts

enum SEPABankAccounts {

    // MARK: IBAN

    typealias IBANValidity = PaymentMethodFieldValidity<Self.IBANInvalidity>

    enum IBANInvalidity: Hashable {
        case tooShort
        case tooLong
        case invalidCountry
        case invalidCharacters
        case invalidCheck
    }

    static func validity(of iban: String, isFieldFocused: Bool) -> IBANValidity {
        // Check for invalid characters
        guard iban.isAsciiAlphanumericsOnly else {
            return .invalid(.invalidCharacters)
        }

        // Don't show an error message if the user hasn't input anything yet
        if iban.isEmpty {
            return .potentiallyValid
        }

        func potentiallyInvalid(
            _ invalidity: IBANInvalidity,
            isPotentiallyValid: Bool
        ) -> IBANValidity {
            if isPotentiallyValid {
                return .potentiallyValid
            }
            return .invalid(invalidity)
        }

        // Check the country
        guard iban.count >= 2 else {
            return potentiallyInvalid(.tooShort, isPotentiallyValid: isFieldFocused)
        }

        let countryCode = String(iban.prefix(2))
        guard let expectedLength = expectedIBANLengthByCountryCode[countryCode] else {
            return .invalid(.invalidCountry)
        }

        // Check length
        if iban.count < expectedLength {
            return potentiallyInvalid(.tooShort, isPotentiallyValid: isFieldFocused)
        }

        if iban.count > expectedLength {
            // Too long can be displayed immediately
            return .invalid(.tooLong)
        }

        // Validation check
        guard doesIBANPassValidationCheck(iban) else {
            return .invalid(.invalidCheck)
        }

        // Everything passed
        return .fullyValid
    }

    /// Checks if an IBAN string might be valid.
    ///
    /// Input should be alaphanumerics only with no whitespace.
    /// Any unexpected characters will cause a `false` return.
    ///
    /// The following methed is used:
    ///
    /// 1. Move the four initial characters to the end of the string
    /// 1. Replace each letter in the string with two digits, thereby expanding the string, where A = 10, B = 11, ..., Z = 35
    /// 1. Interpret the string as a decimal integer and compute the remainder of that number on division by 97
    ///
    /// See [Validating the IBAN][0] on Wikipedia.
    ///
    /// [0]:https://en.wikipedia.org/wiki/International_Bank_Account_Number#Validating_the_IBAN
    ///
    /// - Parameter iban: A string containing an international bank account number.
    /// - Returns: `true` if the IBAN might be valid.
    /// `false` if it does not pass a validation check.
    static func doesIBANPassValidationCheck(_ iban: String) -> Bool {
        let rearrangedIBAN = iban.dropFirst(4) + iban.prefix(4)
        let numericIBAN = rearrangedIBAN.uppercased().compactMap { character in
            // Base 36 means A = 10, B = 11, ..., Z = 36, exactly how IBAN expects
            Int(String(character), radix: 36)
        }

        guard numericIBAN.count == iban.count else {
            // Invalid characters couldn't be converted to numbers
            return false
        }

        // The numeric representation is too large to fit into a UInt64 (it would
        // need at least a UInt219), so perform the mod piecewise.
        let mod97 = numericIBAN.reduce(0) { previousMod, number in
            // The base-36 numbers can only be one or two digits. Offset them
            // appropriately so the new number can be effectively concatenated
            // to the end of the previous mod
            let offsetFactor = number < 10 ? 10 : 100
            return (previousMod * offsetFactor + number) % 97
        }

        return mod97 == 1
    }

    // MARK: Supported countries

    /// The expected length of an IBAN by a SEPA-participating country's two-character ISO country code.
    ///
    /// List of SEPA-participating countries from [Stripe docs][0].
    ///
    /// Expected IBAN lengths from [Wikipedia][1].
    ///
    /// [0]:https://stripe.com/resources/more/sepa-country-list#which-countries-are-in-the-sepa-zone
    /// [1]:https://en.wikipedia.org/wiki/International_Bank_Account_Number#IBAN_formats_by_country
    static let expectedIBANLengthByCountryCode: [String: Int] = [
        // EU members
        "AT": 20, // Austria
        "BE": 16, // Belgium
        "BG": 22, // Bulgaria
        "HR": 21, // Croatia
        "CY": 28, // Cyprus
        "CZ": 24, // Czech Republic
        "DK": 18, // Denmark
        "EE": 20, // Estonia
        "FI": 18, // Finland
        "FR": 27, // France
        "DE": 22, // Germany
        "GR": 27, // Greece
        "HU": 28, // Hungary
        "IE": 22, // Ireland
        "IT": 27, // Italy
        "LV": 21, // Latvia
        "LT": 20, // Lithuania
        "LU": 20, // Luxembourg
        "MT": 31, // Malta
        // Use iDEAL instead of SEPA for Netherlands
        "PL": 28, // Poland
        "PT": 25, // Portugal
        "RO": 24, // Romania
        "SK": 24, // Slovakia
        "SI": 19, // Slovenia
        "ES": 24, // Spain
        "SE": 24, // Sweden
        // Others
        "CH": 21, // Switzerland
        "GB": 22, // United Kingdom
        "SM": 27, // San Marino
        "VA": 22, // Vatican City
        "AD": 24, // Andorra
        "MC": 27, // Monaco
        // EEA members
        "IS": 26, // Iceland
        "NO": 15, // Norway
        "LI": 21, // Liechtenstein
    ]
}
