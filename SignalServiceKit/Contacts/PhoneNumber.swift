//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import libPhoneNumber_iOS

/// PhoneNumber is used to deal with the nitty details of parsing/canonicalizing phone numbers.
public struct PhoneNumber {

    public static let countryCodePrefix = "+"

    public let nbPhoneNumber: NBPhoneNumber
    public let e164: String

    init(nbPhoneNumber: NBPhoneNumber, e164: String) {
        owsAssertDebug(!e164.isEmpty)

        self.nbPhoneNumber = nbPhoneNumber
        self.e164 = e164
    }

    public func getCallingCode() -> Int? {
        // Note that NBPhoneNumber uses "countryCode" to refer to what we call a
        // "callingCode" (e.g., the "44" in "+44123123"). Elsewhere, we use use
        // "country code" (and sometimes "region code") to refer to a country's
        // 2-letter code (e.g., "US").
        return nbPhoneNumber.countryCode?.intValue
    }

    public static func bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(_ input: String) -> String {
        bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(input, regionCode: PhoneNumberUtil.defaultCountryCode())
    }

    public static func bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(_ input: String, plusPrefixedCallingCode: String) -> String {
        bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(input, regionCode: regionCode(from: plusPrefixedCallingCode))
    }

    private static func bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(_ input: String, regionCode: String) -> String {
        let formatter: NBAsYouTypeFormatter = NBAsYouTypeFormatter(
            regionCode: regionCode,
            metadataHelper: SSKEnvironment.shared.phoneNumberUtilRef.nbMetadataHelper
        )
        var result = input
        // Note that the objc code this was converted from would've performed this in UTF-16 code units.
        // We assume NBAsYouTypeFormatter can handle Character types given the API takes String.
        for character in input {
            result = formatter.inputDigit(String(character))
        }
        return result
    }

    public static func bestEffortLocalizedPhoneNumber(e164: String) -> String {
        guard e164.hasPrefix(countryCodePrefix) else {
            return e164
        }

        guard let parsedPhoneNumber = SSKEnvironment.shared.phoneNumberUtilRef.parseE164(e164) else {
            Logger.warn("could not parse phone number")
            return e164
        }
        guard parsedPhoneNumber.getCallingCode() != nil else {
            Logger.warn("parsed phone number has no calling code")
            return e164
        }
        return bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(e164)
    }

    private static func regionCode(from plusPrefixedCallingCode: String) -> String {
        // Int(String) could be used here except it doesn't skip whitespace and so would be a change
        // from the objc NSString.integerValue behavior...
        let callingCode = (plusPrefixedCallingCode.dropFirst() as NSString).integerValue
        return SSKEnvironment.shared.phoneNumberUtilRef.getRegionCodeForCallingCode(callingCode)
    }
}
