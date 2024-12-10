//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public struct RegistrationCountryState: Equatable {
    // e.g. France
    public let countryName: String
    // e.g. +33
    public let plusPrefixedCallingCode: String
    // e.g. FR
    public let countryCode: String

    public init(countryName: String, plusPrefixedCallingCode: String, countryCode: String) {
        self.countryName = countryName
        self.plusPrefixedCallingCode = plusPrefixedCallingCode
        self.countryCode = countryCode
    }

    public static var defaultValue: RegistrationCountryState {
        AssertIsOnMainThread()

        let countryCode: String = PhoneNumberUtil.defaultCountryCode()
        let callingCodeNumber = SSKEnvironment.shared.phoneNumberUtilRef.getCallingCode(forRegion: countryCode)
        let plusPrefixedCallingCode = "\(PhoneNumber.countryCodePrefix)\(callingCodeNumber)"
        let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode)

        return RegistrationCountryState(countryName: countryName, plusPrefixedCallingCode: plusPrefixedCallingCode, countryCode: countryCode)
    }

    // MARK: -

    public static func countryState(forE164 e164: String) -> RegistrationCountryState? {
        for countryState in allCountryStates {
            if e164.hasPrefix(countryState.plusPrefixedCallingCode) {
                return countryState
            }
        }
        return nil
    }

    public static var allCountryStates: [RegistrationCountryState] {
        RegistrationCountryState.buildCountryStates(searchText: nil)
    }

    public static func buildCountryStates(searchText: String?) -> [RegistrationCountryState] {
        let searchText = searchText?.strippedOrNil
        let countryCodes: [String] = SSKEnvironment.shared.phoneNumberUtilRef.countryCodes(forSearchTerm: searchText)
        return RegistrationCountryState.buildCountryStates(countryCodes: countryCodes)
    }

    public static func buildCountryStates(countryCodes: [String]) -> [RegistrationCountryState] {
        return countryCodes.compactMap { (countryCode: String) -> RegistrationCountryState? in
            guard let countryCode = countryCode.strippedOrNil else {
                owsFailDebug("Invalid countryCode.")
                return nil
            }
            guard let plusPrefixedCallingCode = SSKEnvironment.shared.phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: countryCode) else {
                owsFailDebug("Invalid callingCode.")
                return nil
            }
            guard let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode).strippedOrNil else {
                owsFailDebug("Invalid countryName.")
                return nil
            }
            guard plusPrefixedCallingCode != "+0" else {
                owsFailDebug("Invalid callingCode.")
                return nil
            }

            return RegistrationCountryState(
                countryName: countryName,
                plusPrefixedCallingCode: plusPrefixedCallingCode,
                countryCode: countryCode
            )
        }
    }
}

// MARK: -

public struct RegistrationPhoneNumber {
    public let countryState: RegistrationCountryState
    public let nationalNumber: String
    public let e164: E164?

    public init(countryState: RegistrationCountryState, nationalNumber: String) {
        self.countryState = countryState
        self.nationalNumber = nationalNumber
        self.e164 = E164("\(countryState.plusPrefixedCallingCode)\(nationalNumber)")
    }
}

public class RegistrationPhoneNumberParser {
    private let phoneNumberUtil: PhoneNumberUtil

    public init(phoneNumberUtil: PhoneNumberUtil) {
        self.phoneNumberUtil = phoneNumberUtil
    }

    public func parseE164(_ phoneNumber: E164) -> RegistrationPhoneNumber? {
        guard
            let countryState = RegistrationCountryState.countryState(forE164: phoneNumber.stringValue),
            let phoneNumber = phoneNumberUtil.parseE164(phoneNumber)
        else {
            return nil
        }
        let nationalNumber = phoneNumberUtil.nationalNumber(for: phoneNumber)
        return RegistrationPhoneNumber(countryState: countryState, nationalNumber: nationalNumber)
    }
}
