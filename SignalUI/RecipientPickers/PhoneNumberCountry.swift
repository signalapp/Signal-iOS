//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public struct PhoneNumberCountry: Equatable {
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

    public static var defaultValue: PhoneNumberCountry {
        AssertIsOnMainThread()

        let countryCode: String = PhoneNumberUtil.defaultCountryCode()
        let callingCodeNumber = SSKEnvironment.shared.phoneNumberUtilRef.getCallingCode(forRegion: countryCode)
        let plusPrefixedCallingCode = "\(PhoneNumber.countryCodePrefix)\(callingCodeNumber)"
        let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode)

        return PhoneNumberCountry(countryName: countryName, plusPrefixedCallingCode: plusPrefixedCallingCode, countryCode: countryCode)
    }

    // MARK: -

    public static func buildCountries(searchText: String?) -> [PhoneNumberCountry] {
        let searchText = searchText?.strippedOrNil
        let countryCodes: [String] = SSKEnvironment.shared.phoneNumberUtilRef.countryCodes(forSearchTerm: searchText)
        return PhoneNumberCountry.buildCountries(forCountryCodes: countryCodes)
    }

    private static func buildCountries(forCountryCodes countryCodes: [String]) -> [PhoneNumberCountry] {
        return countryCodes.compactMap { (countryCode: String) -> PhoneNumberCountry? in
            guard let countryCode = countryCode.strippedOrNil else {
                owsFailDebug("Invalid countryCode.")
                return nil
            }
            guard let plusPrefixedCallingCode = SSKEnvironment.shared.phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: countryCode) else {
                owsFailDebug("Invalid callingCode.")
                return nil
            }
            return buildCountry(countryCode: countryCode, plusPrefixedCallingCode: plusPrefixedCallingCode)
        }
    }

    public static func buildCountry(forCallingCode callingCode: Int) -> PhoneNumberCountry? {
        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef

        guard let countryCode = phoneNumberUtil.getFilteredRegionCodeForCallingCode(callingCode) else {
            owsFailDebug("Invalid callingCode.")
            return nil
        }

        return buildCountry(countryCode: countryCode, plusPrefixedCallingCode: "+\(callingCode)")
    }

    private static func buildCountry(countryCode: String, plusPrefixedCallingCode: String) -> PhoneNumberCountry? {
        guard let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode).strippedOrNil else {
            owsFailDebug("Invalid countryName.")
            return nil
        }
        guard plusPrefixedCallingCode != "+0" else {
            owsFailDebug("Invalid callingCode.")
            return nil
        }
        return PhoneNumberCountry(
            countryName: countryName,
            plusPrefixedCallingCode: plusPrefixedCallingCode,
            countryCode: countryCode
        )
    }
}
