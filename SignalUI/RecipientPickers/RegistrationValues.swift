//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public struct RegistrationPhoneNumber {
    public let country: PhoneNumberCountry
    public let nationalNumber: String
    public let e164: E164?

    public init(country: PhoneNumberCountry, nationalNumber: String) {
        self.country = country
        self.nationalNumber = nationalNumber
        self.e164 = E164("\(country.plusPrefixedCallingCode)\(nationalNumber)")
    }
}

public class RegistrationPhoneNumberParser {
    private let phoneNumberUtil: PhoneNumberUtil

    public init(phoneNumberUtil: PhoneNumberUtil) {
        self.phoneNumberUtil = phoneNumberUtil
    }

    public func parseE164(_ phoneNumber: E164) -> RegistrationPhoneNumber? {
        guard
            let country = PhoneNumberCountry.country(forE164: phoneNumber.stringValue),
            let phoneNumber = phoneNumberUtil.parseE164(phoneNumber)
        else {
            return nil
        }
        let nationalNumber = phoneNumberUtil.nationalNumber(for: phoneNumber)
        return RegistrationPhoneNumber(country: country, nationalNumber: nationalNumber)
    }
}
