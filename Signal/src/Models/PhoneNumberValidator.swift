//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public enum ValidatedPhoneCountryCodes: UInt {
    case unitedStates = 1
    case brazil = 55
}

public class PhoneNumberValidator: NSObject {

    public func isValidForRegistration(phoneNumber: PhoneNumber) -> Bool {
        guard let countryCode = phoneNumber.getCountryCode() else {
            return false
        }

        guard let validatedCountryCode = ValidatedPhoneCountryCodes(rawValue: countryCode.uintValue) else {
            // no extra validation for this country
            return true
        }

        switch validatedCountryCode {
        case .brazil:
            return isValidForBrazilRegistration(phoneNumber: phoneNumber)
        case .unitedStates:
            return isValidForUnitedStatesRegistration(phoneNumber: phoneNumber)
        }
    }

    let validBrazilPhoneNumberRegex = try! NSRegularExpression(pattern: "^\\+55\\d{2}9?\\d{8}$", options: [])
    private func isValidForBrazilRegistration(phoneNumber: PhoneNumber) -> Bool {
        let e164 = phoneNumber.toE164()
        return validBrazilPhoneNumberRegex.hasMatch(input: e164)
    }

    let validUnitedStatesPhoneNumberRegex = try! NSRegularExpression(pattern: "^\\+1\\d{10}$", options: [])
    private func isValidForUnitedStatesRegistration(phoneNumber: PhoneNumber) -> Bool {
        let e164 = phoneNumber.toE164()
        return validUnitedStatesPhoneNumberRegex.hasMatch(input: e164)
    }
}
