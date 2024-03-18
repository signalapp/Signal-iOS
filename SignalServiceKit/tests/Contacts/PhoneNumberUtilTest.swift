//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class PhoneNumberUtilTestSwift: SSKBaseTestSwift {
    func test_probableCountryCode() {
        XCTAssertEqual(phoneNumberUtil.probableCountryCode(forCallingCode: "+1"), "US")
        XCTAssertEqual(phoneNumberUtil.probableCountryCode(forCallingCode: "+44"), "GB")
        XCTAssertEqual(phoneNumberUtil.probableCountryCode(forCallingCode: "+0"), "")
    }

    func test_callingCodeFromCountryCode() {
        XCTAssertEqual("+1", phoneNumberUtil.callingCode(fromCountryCode: "US"))
        XCTAssertEqual("+44", phoneNumberUtil.callingCode(fromCountryCode: "GB"))
        XCTAssertEqual("+598", phoneNumberUtil.callingCode(fromCountryCode: "UY"))
        XCTAssertEqual("+0", phoneNumberUtil.callingCode(fromCountryCode: "QG"))
        XCTAssertEqual("+0", phoneNumberUtil.callingCode(fromCountryCode: "EK"))
        XCTAssertEqual("+0", phoneNumberUtil.callingCode(fromCountryCode: "ZZZ"))
        XCTAssertEqual("+0", phoneNumberUtil.callingCode(fromCountryCode: ""))
        XCTAssertEqual("+0", phoneNumberUtil.callingCode(fromCountryCode: "+"))
        XCTAssertEqual("+0", phoneNumberUtil.callingCode(fromCountryCode: "9"))
        XCTAssertEqual("+1", phoneNumberUtil.callingCode(fromCountryCode: "US "))
    }

    func test_countryCodesFromCallingCode() {
        // Order matters here.
        XCTAssertEqual(["US", "CA", "DO", "PR", "JM", "TT", "BS", "BB", "LC", "GU", "VI", "GD", "VC", "AG", "DM", "BM", "AS", "MP", "KN", "KY", "SX", "VG", "TC", "AI", "MS", "UM"], phoneNumberUtil.countryCodes(fromCallingCode: "+1"))
        XCTAssertEqual(["GB", "JE", "IM", "GG"], phoneNumberUtil.countryCodes(fromCallingCode: "+44"))
        XCTAssertEqual(["UY"], phoneNumberUtil.countryCodes(fromCallingCode: "+598"))
        XCTAssertEqual([], phoneNumberUtil.countryCodes(fromCallingCode: "+7945"))
        XCTAssertEqual([], phoneNumberUtil.countryCodes(fromCallingCode: "+"))
        XCTAssertEqual([], phoneNumberUtil.countryCodes(fromCallingCode: ""))
        XCTAssertEqual([], phoneNumberUtil.countryCodes(fromCallingCode: " "))
        XCTAssertEqual([], phoneNumberUtil.countryCodes(fromCallingCode: "a"))
        XCTAssertEqual([], phoneNumberUtil.countryCodes(fromCallingCode: "++598"))
        XCTAssertEqual([], phoneNumberUtil.countryCodes(fromCallingCode: "+1 "))
        XCTAssertEqual([], phoneNumberUtil.countryCodes(fromCallingCode: " +1"))
    }

    func test_parse() {
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: "US").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: "GB").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: "UY").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtil.parse("+441752395464", defaultRegion: "US").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtil.parse("+441752395464", defaultRegion: "GB").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtil.parse("+441752395464", defaultRegion: "UY").countryCode)
        // Invalid regions.
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: "UK").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtil.parse("+441752395464", defaultRegion: "UK").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: "ZQ").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: "").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: "99").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: "+").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+13334445555", defaultRegion: " ").countryCode)
        // Invalid phone numbers.
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("+1333444555", defaultRegion: "UY").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtil.parse("+44175239546", defaultRegion: "UY").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtil.parse("+441752395468 ", defaultRegion: "UY").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtil.parse("++13334445555 ", defaultRegion: "UY").countryCode)

        do {
            _ = try phoneNumberUtil.parse("+9764", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtil.parse("", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtil.parse(" ", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtil.parse("a", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtil.parse("+", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtil.parse("9876543210987654321098765432109876543210", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtil.parse("+9876543210987654321098765432109876543210", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
    }

    func test_format() {
        let phoneNumber1 = try! phoneNumberUtil.parse("+13334445555", defaultRegion: "US")
        let phoneNumber2 = try! phoneNumberUtil.parse("+441752395464", defaultRegion: "US")

        XCTAssertEqual("+13334445555", try! phoneNumberUtil.format(phoneNumber1, numberFormat: .E164))
        XCTAssertEqual("(333) 444-5555", try! phoneNumberUtil.format(phoneNumber1, numberFormat: .NATIONAL))
        XCTAssertEqual("+1 333-444-5555", try! phoneNumberUtil.format(phoneNumber1, numberFormat: .INTERNATIONAL))
        XCTAssertEqual("tel:+1-333-444-5555", try! phoneNumberUtil.format(phoneNumber1, numberFormat: .RFC3966))

        XCTAssertEqual("+441752395464", try! phoneNumberUtil.format(phoneNumber2, numberFormat: .E164))
        XCTAssertEqual("01752 395464", try! phoneNumberUtil.format(phoneNumber2, numberFormat: .NATIONAL))
        XCTAssertEqual("+44 1752 395464", try! phoneNumberUtil.format(phoneNumber2, numberFormat: .INTERNATIONAL))
        XCTAssertEqual("tel:+44-1752-395464", try! phoneNumberUtil.format(phoneNumber2, numberFormat: .RFC3966))
    }

    func test_examplePhoneNumberForCountryCode() {
        XCTAssertEqual("+12015550123", phoneNumberUtil.examplePhoneNumber(forCountryCode: "US"))
        XCTAssertEqual("+447400123456", phoneNumberUtil.examplePhoneNumber(forCountryCode: "GB"))
        XCTAssertEqual("+59894231234", phoneNumberUtil.examplePhoneNumber(forCountryCode: "UY"))
    }

    func test_isPossibleNumber() {
        let phoneNumber1 = try! phoneNumberUtil.parse("+13334445555", defaultRegion: "US")
        let phoneNumber2 = try! phoneNumberUtil.parse("+441752395464", defaultRegion: "US")
        // Invalid numbers.
        let phoneNumber3 = try! phoneNumberUtil.parse("+44175239546", defaultRegion: "US")
        let phoneNumber4 = try! phoneNumberUtil.parse("44", defaultRegion: "US")

        XCTAssertEqual(true, phoneNumberUtil.isPossibleNumber(phoneNumber1))
        XCTAssertEqual(true, phoneNumberUtil.isPossibleNumber(phoneNumber2))
        XCTAssertEqual(true, phoneNumberUtil.isPossibleNumber(phoneNumber3))
        XCTAssertEqual(false, phoneNumberUtil.isPossibleNumber(phoneNumber4))
    }

    func test_isValidNumber() {
        let phoneNumber1 = try! phoneNumberUtil.parse("+12125556789", defaultRegion: "US")
        let phoneNumber2 = try! phoneNumberUtil.parse("+441752395464", defaultRegion: "US")
        let phoneNumber3 = try! phoneNumberUtil.parse("+12125556789", defaultRegion: "GB")
        let phoneNumber4 = try! phoneNumberUtil.parse("+441752395464", defaultRegion: "GB")
        // Invalid numbers.
        let phoneNumber5 = try! phoneNumberUtil.parse("+44175239546", defaultRegion: "US")
        let phoneNumber6 = try! phoneNumberUtil.parse("44", defaultRegion: "US")
        let phoneNumber7 = try! phoneNumberUtil.parse("+13334445555", defaultRegion: "US")
        let phoneNumber8 = try! phoneNumberUtil.parse("+44175239546", defaultRegion: "GB")
        let phoneNumber9 = try! phoneNumberUtil.parse("44", defaultRegion: "GB")
        let phoneNumber10 = try! phoneNumberUtil.parse("+13334445555", defaultRegion: "GB")

        XCTAssertEqual(true, phoneNumberUtil.isValidNumber(phoneNumber1))
        XCTAssertEqual(true, phoneNumberUtil.isValidNumber(phoneNumber2))
        XCTAssertEqual(true, phoneNumberUtil.isValidNumber(phoneNumber3))
        XCTAssertEqual(true, phoneNumberUtil.isValidNumber(phoneNumber4))
        XCTAssertEqual(false, phoneNumberUtil.isValidNumber(phoneNumber5))
        XCTAssertEqual(false, phoneNumberUtil.isValidNumber(phoneNumber6))
        XCTAssertEqual(false, phoneNumberUtil.isValidNumber(phoneNumber7))
        XCTAssertEqual(false, phoneNumberUtil.isValidNumber(phoneNumber8))
        XCTAssertEqual(false, phoneNumberUtil.isValidNumber(phoneNumber9))
        XCTAssertEqual(false, phoneNumberUtil.isValidNumber(phoneNumber10))
    }

    func test_getRegionCodeForCountryCode() {
        XCTAssertEqual("US", phoneNumberUtil.getRegionCodeForCountryCode(NSNumber(value: 1)))
        XCTAssertEqual("GB", phoneNumberUtil.getRegionCodeForCountryCode(NSNumber(value: 44)))
        XCTAssertEqual("UY", phoneNumberUtil.getRegionCodeForCountryCode(NSNumber(value: 598)))
        XCTAssertEqual("ZZ", phoneNumberUtil.getRegionCodeForCountryCode(NSNumber(value: 0)))
        XCTAssertEqual("ZZ", phoneNumberUtil.getRegionCodeForCountryCode(NSNumber(value: 99999)))
        XCTAssertEqual("ZZ", phoneNumberUtil.getRegionCodeForCountryCode(NSNumber(value: -1)))
    }

    func test_getCountryCodeForRegion() {
        XCTAssertEqual(NSNumber(value: 1), phoneNumberUtil.getCountryCode(forRegion: "US"))
        XCTAssertEqual(NSNumber(value: 44), phoneNumberUtil.getCountryCode(forRegion: "GB"))
        XCTAssertEqual(NSNumber(value: 598), phoneNumberUtil.getCountryCode(forRegion: "UY"))
        // Invalid regions.
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtil.getCountryCode(forRegion: "UK"))
        XCTAssertEqual(NSNumber(value: 1), phoneNumberUtil.getCountryCode(forRegion: "US "))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtil.getCountryCode(forRegion: " "))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtil.getCountryCode(forRegion: ""))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtil.getCountryCode(forRegion: "+1"))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtil.getCountryCode(forRegion: "ZZ"))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtil.getCountryCode(forRegion: "+"))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtil.getCountryCode(forRegion: "ZQ"))
    }

    func testCountryCodesForSearchTerm() {
        // Empty search.
        XCTAssertGreaterThan(phoneNumberUtil.countryCodes(forSearchTerm: nil).count, 30)
        XCTAssertGreaterThan(phoneNumberUtil.countryCodes(forSearchTerm: "").count, 30)
        XCTAssertGreaterThan(phoneNumberUtil.countryCodes(forSearchTerm: " ").count, 30)

        // Searches with no results.
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: " . ").count, 0)
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: " XXXXX ").count, 0)
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: " ! ").count, 0)

        // Search by country code.
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: "GB"), ["GB"])
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: "gb"), ["GB"])
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: "GB "), ["GB"])
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: " GB"), ["GB"])
        XCTAssert(phoneNumberUtil.countryCodes(forSearchTerm: " G").contains("GB"))
        XCTAssertFalse(phoneNumberUtil.countryCodes(forSearchTerm: " B").contains("GB"))

        // Search by country name.
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: "united kingdom"), ["GB"])
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: " UNITED KINGDOM "), ["GB"])
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: " UNITED KING "), ["GB"])
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: " UNI KING "), ["GB"])
        XCTAssertEqual(phoneNumberUtil.countryCodes(forSearchTerm: " u k "), ["GB"])
        XCTAssert(phoneNumberUtil.countryCodes(forSearchTerm: " u").contains("GB"))
        XCTAssert(phoneNumberUtil.countryCodes(forSearchTerm: " k").contains("GB"))
        XCTAssertFalse(phoneNumberUtil.countryCodes(forSearchTerm: " m").contains("GB"))

        // Search by calling code.
        XCTAssert(phoneNumberUtil.countryCodes(forSearchTerm: " +44 ").contains("GB"))
        XCTAssert(phoneNumberUtil.countryCodes(forSearchTerm: " 44 ").contains("GB"))
        XCTAssert(phoneNumberUtil.countryCodes(forSearchTerm: " +4 ").contains("GB"))
        XCTAssert(phoneNumberUtil.countryCodes(forSearchTerm: " 4 ").contains("GB"))
        XCTAssertFalse(phoneNumberUtil.countryCodes(forSearchTerm: " +123 ").contains("GB"))
        XCTAssertFalse(phoneNumberUtil.countryCodes(forSearchTerm: " +444 ").contains("GB"))
    }
}
