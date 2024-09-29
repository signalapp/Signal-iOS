//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
public import SignalServiceKit

public enum ValidatedCallingCode: UInt {
    case unitedStates = 1
    case brazil = 55
}

public class PhoneNumberValidator: NSObject {

    public func isValidForRegistration(phoneNumber: PhoneNumber) -> Bool {
        guard let callingCode = phoneNumber.getCallingCode() else {
            return false
        }

        guard let validatedCallingCode = ValidatedCallingCode(rawValue: callingCode.uintValue) else {
            // no extra validation for this country
            return true
        }

        switch validatedCallingCode {
        case .brazil:
            return isValidForBrazilRegistration(phoneNumber: phoneNumber)
        case .unitedStates:
            return isValidForUnitedStatesRegistration(phoneNumber: phoneNumber)
        }
    }

    private let validBrazilPhoneNumberRegex = try! NSRegularExpression(pattern: "^\\+55\\d{2}9?\\d{8}$", options: [])
    private func isValidForBrazilRegistration(phoneNumber: PhoneNumber) -> Bool {
        validBrazilPhoneNumberRegex.hasMatch(input: phoneNumber.e164)
    }

    private let validUnitedStatesPhoneNumberRegex = try! NSRegularExpression(pattern: "^\\+1\\d{10}$", options: [])
    private func isValidForUnitedStatesRegistration(phoneNumber: PhoneNumber) -> Bool {
        validUnitedStatesPhoneNumberRegex.hasMatch(input: phoneNumber.e164)
    }
}
