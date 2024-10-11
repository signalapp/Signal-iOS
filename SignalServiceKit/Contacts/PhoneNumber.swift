//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import libPhoneNumber_iOS

private let rpDefaultsKeyPhoneNumberString = "RPDefaultsKeyPhoneNumberString"
private let rpDefaultsKeyPhoneNumberCanonical = "RPDefaultsKeyPhoneNumberCanonical"

/// PhoneNumber is used to deal with the nitty details of parsing/canonicalizing phone numbers.
@objc(PhoneNumber)
public class PhoneNumber: NSObject, NSCoding, Comparable {

    public static let countryCodePrefix = "+"

    public let nbPhoneNumber: NBPhoneNumber
    public let e164: String
    public override var description: String { e164 }

    init(nbPhoneNumber: NBPhoneNumber, e164: String) {
        owsAssertDebug(!e164.isEmpty)

        self.nbPhoneNumber = nbPhoneNumber
        self.e164 = e164
    }

    public required init?(coder: NSCoder) {
        guard
            let nbPhoneNumber = coder.decodeObject(of: NBPhoneNumber.self, forKey: rpDefaultsKeyPhoneNumberString),
            let e164 = coder.decodeObject(of: NSString.self, forKey: rpDefaultsKeyPhoneNumberCanonical)
        else {
            return nil
        }
        self.nbPhoneNumber = nbPhoneNumber
        self.e164 = e164 as String
    }

    public func encode(with coder: NSCoder) {
        coder.encode(nbPhoneNumber, forKey: rpDefaultsKeyPhoneNumberString)
        coder.encode(e164, forKey: rpDefaultsKeyPhoneNumberCanonical)
    }

    public func getCallingCode() -> NSNumber? {
        nbPhoneNumber.countryCode
    }

    public func isValid() -> Bool {
        SSKEnvironment.shared.phoneNumberUtilRef.isValidNumber(nbPhoneNumber)
    }

    public func compare(_ other: PhoneNumber) -> ComparisonResult {
        e164.compare(other.e164)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherPhoneNumber = object as? PhoneNumber else {
            return false
        }
        return e164 == otherPhoneNumber.e164
    }

    public override var hash: Int { e164.hash }

    public static func < (_ lhs: PhoneNumber, _ rhs: PhoneNumber) -> Bool {
        lhs.compare(rhs) == .orderedAscending
    }

    public static func bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(_ input: String) -> String {
        bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(input, regionCode: PhoneNumberUtil.defaultCountryCode())
    }

    public static func bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(_ input: String, countryCodeString: String) -> String {
        bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(input, regionCode: regionCode(from: countryCodeString))
    }

    private static func bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(_ input: String, regionCode: String) -> String {
        guard let formatter = NBAsYouTypeFormatter(regionCode: regionCode) else {
            owsFail("failed to create NBAsYouTypeFormatter for region code \(regionCode)")
        }
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
        guard let callingCode = parsedPhoneNumber.getCallingCode() else {
            Logger.warn("parsed phone number has no calling code")
            return e164
        }
        return bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(e164, regionCode: String(callingCode.intValue))
    }

    private static func regionCode(from countryCodeString: String) -> String {
        // Int(String) could be used here except it doesn't skip whitespace and so would be a change
        // from the objc NSString.integerValue behavior...
        let countryCallingCode = (countryCodeString.dropFirst() as NSString).integerValue
        return SSKEnvironment.shared.phoneNumberUtilRef.getRegionCodeForCountryCode(NSNumber(value: countryCallingCode))
    }
}
