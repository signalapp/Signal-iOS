//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class PhoneNumberUtilTestSwift: XCTestCase {
    private var phoneNumberUtilRef: PhoneNumberUtil!

    override func setUp() {
        super.setUp()
        self.phoneNumberUtilRef = PhoneNumberUtil(swiftValues: PhoneNumberUtilSwiftValues())
    }

    func test_probableCountryCode() {
        XCTAssertEqual(phoneNumberUtilRef.probableCountryCode(forCallingCode: "+1"), "US")
        XCTAssertEqual(phoneNumberUtilRef.probableCountryCode(forCallingCode: "+44"), "GB")
        XCTAssertEqual(phoneNumberUtilRef.probableCountryCode(forCallingCode: "+0"), "")
    }

    func test_callingCodeFromCountryCode() {
        XCTAssertEqual("+1", phoneNumberUtilRef.callingCode(fromCountryCode: "US"))
        XCTAssertEqual("+44", phoneNumberUtilRef.callingCode(fromCountryCode: "GB"))
        XCTAssertEqual("+598", phoneNumberUtilRef.callingCode(fromCountryCode: "UY"))
        XCTAssertEqual("+0", phoneNumberUtilRef.callingCode(fromCountryCode: "QG"))
        XCTAssertEqual("+0", phoneNumberUtilRef.callingCode(fromCountryCode: "EK"))
        XCTAssertEqual("+0", phoneNumberUtilRef.callingCode(fromCountryCode: "ZZZ"))
        XCTAssertEqual("+0", phoneNumberUtilRef.callingCode(fromCountryCode: ""))
        XCTAssertEqual("+0", phoneNumberUtilRef.callingCode(fromCountryCode: "+"))
        XCTAssertEqual("+0", phoneNumberUtilRef.callingCode(fromCountryCode: "9"))
        XCTAssertEqual("+1", phoneNumberUtilRef.callingCode(fromCountryCode: "US "))
    }

    func test_countryCodesFromCallingCode() {
        // Order matters here.
        XCTAssertEqual(["US", "CA", "DO", "PR", "JM", "TT", "BS", "BB", "LC", "GU", "VI", "GD", "VC", "AG", "DM", "BM", "AS", "MP", "KN", "KY", "SX", "VG", "TC", "AI", "MS", "UM"], phoneNumberUtilRef.countryCodes(fromCallingCode: "+1"))
        XCTAssertEqual(["GB", "JE", "IM", "GG"], phoneNumberUtilRef.countryCodes(fromCallingCode: "+44"))
        XCTAssertEqual(["UY"], phoneNumberUtilRef.countryCodes(fromCallingCode: "+598"))
        XCTAssertEqual([], phoneNumberUtilRef.countryCodes(fromCallingCode: "+7945"))
        XCTAssertEqual([], phoneNumberUtilRef.countryCodes(fromCallingCode: "+"))
        XCTAssertEqual([], phoneNumberUtilRef.countryCodes(fromCallingCode: ""))
        XCTAssertEqual([], phoneNumberUtilRef.countryCodes(fromCallingCode: " "))
        XCTAssertEqual([], phoneNumberUtilRef.countryCodes(fromCallingCode: "a"))
        XCTAssertEqual([], phoneNumberUtilRef.countryCodes(fromCallingCode: "++598"))
        XCTAssertEqual([], phoneNumberUtilRef.countryCodes(fromCallingCode: "+1 "))
        XCTAssertEqual([], phoneNumberUtilRef.countryCodes(fromCallingCode: " +1"))
    }

    func test_parse() {
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "US").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "GB").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "UY").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtilRef.parse("+441752395464", defaultRegion: "US").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtilRef.parse("+441752395464", defaultRegion: "GB").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtilRef.parse("+441752395464", defaultRegion: "UY").countryCode)
        // Invalid regions.
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "UK").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtilRef.parse("+441752395464", defaultRegion: "UK").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "ZQ").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "99").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "+").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: " ").countryCode)
        // Invalid phone numbers.
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("+1333444555", defaultRegion: "UY").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtilRef.parse("+44175239546", defaultRegion: "UY").countryCode)
        XCTAssertEqual(NSNumber(value: 44), try! phoneNumberUtilRef.parse("+441752395468 ", defaultRegion: "UY").countryCode)
        XCTAssertEqual(NSNumber(value: 1), try! phoneNumberUtilRef.parse("++13334445555 ", defaultRegion: "UY").countryCode)

        do {
            _ = try phoneNumberUtilRef.parse("+9764", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtilRef.parse("", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtilRef.parse(" ", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtilRef.parse("a", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtilRef.parse("+", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtilRef.parse("9876543210987654321098765432109876543210", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
        do {
            _ = try phoneNumberUtilRef.parse("+9876543210987654321098765432109876543210", defaultRegion: "US")
            XCTFail("Missing expected error.")
        } catch {
            // Error is expected.
        }
    }

    func test_format() {
        let phoneNumber1 = try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "US")
        let phoneNumber2 = try! phoneNumberUtilRef.parse("+441752395464", defaultRegion: "US")

        XCTAssertEqual("+13334445555", try! phoneNumberUtilRef.format(phoneNumber1, numberFormat: .E164))
        XCTAssertEqual("(333) 444-5555", try! phoneNumberUtilRef.format(phoneNumber1, numberFormat: .NATIONAL))
        XCTAssertEqual("+1 333-444-5555", try! phoneNumberUtilRef.format(phoneNumber1, numberFormat: .INTERNATIONAL))
        XCTAssertEqual("tel:+1-333-444-5555", try! phoneNumberUtilRef.format(phoneNumber1, numberFormat: .RFC3966))

        XCTAssertEqual("+441752395464", try! phoneNumberUtilRef.format(phoneNumber2, numberFormat: .E164))
        XCTAssertEqual("01752 395464", try! phoneNumberUtilRef.format(phoneNumber2, numberFormat: .NATIONAL))
        XCTAssertEqual("+44 1752 395464", try! phoneNumberUtilRef.format(phoneNumber2, numberFormat: .INTERNATIONAL))
        XCTAssertEqual("tel:+44-1752-395464", try! phoneNumberUtilRef.format(phoneNumber2, numberFormat: .RFC3966))
    }

    func test_examplePhoneNumberForCountryCode() {
        XCTAssertEqual("+12015550123", phoneNumberUtilRef.examplePhoneNumber(forCountryCode: "US"))
        XCTAssertEqual("+447400123456", phoneNumberUtilRef.examplePhoneNumber(forCountryCode: "GB"))
        XCTAssertEqual("+59894231234", phoneNumberUtilRef.examplePhoneNumber(forCountryCode: "UY"))
    }

    func test_isPossibleNumber() {
        let phoneNumber1 = try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "US")
        let phoneNumber2 = try! phoneNumberUtilRef.parse("+441752395464", defaultRegion: "US")
        // Invalid numbers.
        let phoneNumber3 = try! phoneNumberUtilRef.parse("+44175239546", defaultRegion: "US")
        let phoneNumber4 = try! phoneNumberUtilRef.parse("44", defaultRegion: "US")

        XCTAssertEqual(true, phoneNumberUtilRef.isPossibleNumber(phoneNumber1))
        XCTAssertEqual(true, phoneNumberUtilRef.isPossibleNumber(phoneNumber2))
        XCTAssertEqual(true, phoneNumberUtilRef.isPossibleNumber(phoneNumber3))
        XCTAssertEqual(false, phoneNumberUtilRef.isPossibleNumber(phoneNumber4))
    }

    func test_isValidNumber() {
        let phoneNumber1 = try! phoneNumberUtilRef.parse("+12125556789", defaultRegion: "US")
        let phoneNumber2 = try! phoneNumberUtilRef.parse("+441752395464", defaultRegion: "US")
        let phoneNumber3 = try! phoneNumberUtilRef.parse("+12125556789", defaultRegion: "GB")
        let phoneNumber4 = try! phoneNumberUtilRef.parse("+441752395464", defaultRegion: "GB")
        // Invalid numbers.
        let phoneNumber5 = try! phoneNumberUtilRef.parse("+44175239546", defaultRegion: "US")
        let phoneNumber6 = try! phoneNumberUtilRef.parse("44", defaultRegion: "US")
        let phoneNumber7 = try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "US")
        let phoneNumber8 = try! phoneNumberUtilRef.parse("+44175239546", defaultRegion: "GB")
        let phoneNumber9 = try! phoneNumberUtilRef.parse("44", defaultRegion: "GB")
        let phoneNumber10 = try! phoneNumberUtilRef.parse("+13334445555", defaultRegion: "GB")

        XCTAssertEqual(true, phoneNumberUtilRef.isValidNumber(phoneNumber1))
        XCTAssertEqual(true, phoneNumberUtilRef.isValidNumber(phoneNumber2))
        XCTAssertEqual(true, phoneNumberUtilRef.isValidNumber(phoneNumber3))
        XCTAssertEqual(true, phoneNumberUtilRef.isValidNumber(phoneNumber4))
        XCTAssertEqual(false, phoneNumberUtilRef.isValidNumber(phoneNumber5))
        XCTAssertEqual(false, phoneNumberUtilRef.isValidNumber(phoneNumber6))
        XCTAssertEqual(false, phoneNumberUtilRef.isValidNumber(phoneNumber7))
        XCTAssertEqual(false, phoneNumberUtilRef.isValidNumber(phoneNumber8))
        XCTAssertEqual(false, phoneNumberUtilRef.isValidNumber(phoneNumber9))
        XCTAssertEqual(false, phoneNumberUtilRef.isValidNumber(phoneNumber10))
    }

    func test_getRegionCodeForCountryCode() {
        XCTAssertEqual("US", phoneNumberUtilRef.getRegionCodeForCountryCode(NSNumber(value: 1)))
        XCTAssertEqual("GB", phoneNumberUtilRef.getRegionCodeForCountryCode(NSNumber(value: 44)))
        XCTAssertEqual("UY", phoneNumberUtilRef.getRegionCodeForCountryCode(NSNumber(value: 598)))
        XCTAssertEqual("ZZ", phoneNumberUtilRef.getRegionCodeForCountryCode(NSNumber(value: 0)))
        XCTAssertEqual("ZZ", phoneNumberUtilRef.getRegionCodeForCountryCode(NSNumber(value: 99999)))
        XCTAssertEqual("ZZ", phoneNumberUtilRef.getRegionCodeForCountryCode(NSNumber(value: -1)))
    }

    func test_getCallingCodeForRegion() {
        XCTAssertEqual(NSNumber(value: 1), phoneNumberUtilRef.getCallingCode(forRegion: "US"))
        XCTAssertEqual(NSNumber(value: 44), phoneNumberUtilRef.getCallingCode(forRegion: "GB"))
        XCTAssertEqual(NSNumber(value: 598), phoneNumberUtilRef.getCallingCode(forRegion: "UY"))
        // Invalid regions.
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtilRef.getCallingCode(forRegion: "UK"))
        XCTAssertEqual(NSNumber(value: 1), phoneNumberUtilRef.getCallingCode(forRegion: "US "))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtilRef.getCallingCode(forRegion: " "))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtilRef.getCallingCode(forRegion: ""))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtilRef.getCallingCode(forRegion: "+1"))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtilRef.getCallingCode(forRegion: "ZZ"))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtilRef.getCallingCode(forRegion: "+"))
        XCTAssertEqual(NSNumber(value: 0), phoneNumberUtilRef.getCallingCode(forRegion: "ZQ"))
    }

    func testCountryCodesForSearchTerm() {
        // Empty search.
        XCTAssertGreaterThan(phoneNumberUtilRef.countryCodes(forSearchTerm: nil).count, 30)
        XCTAssertGreaterThan(phoneNumberUtilRef.countryCodes(forSearchTerm: "").count, 30)
        XCTAssertGreaterThan(phoneNumberUtilRef.countryCodes(forSearchTerm: " ").count, 30)

        // Searches with no results.
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: " . ").count, 0)
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: " XXXXX ").count, 0)
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: " ! ").count, 0)

        // Search by country code.
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: "GB"), ["GB"])
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: "gb"), ["GB"])
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: "GB "), ["GB"])
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: " GB"), ["GB"])
        XCTAssert(phoneNumberUtilRef.countryCodes(forSearchTerm: " G").contains("GB"))
        XCTAssertFalse(phoneNumberUtilRef.countryCodes(forSearchTerm: " B").contains("GB"))

        // Search by country name.
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: "united kingdom"), ["GB"])
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: " UNITED KINGDOM "), ["GB"])
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: " UNITED KING "), ["GB"])
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: " UNI KING "), ["GB"])
        XCTAssertEqual(phoneNumberUtilRef.countryCodes(forSearchTerm: " u k "), ["GB"])
        XCTAssert(phoneNumberUtilRef.countryCodes(forSearchTerm: " u").contains("GB"))
        XCTAssert(phoneNumberUtilRef.countryCodes(forSearchTerm: " k").contains("GB"))
        XCTAssertFalse(phoneNumberUtilRef.countryCodes(forSearchTerm: " m").contains("GB"))

        // Search by calling code.
        XCTAssert(phoneNumberUtilRef.countryCodes(forSearchTerm: " +44 ").contains("GB"))
        XCTAssert(phoneNumberUtilRef.countryCodes(forSearchTerm: " 44 ").contains("GB"))
        XCTAssert(phoneNumberUtilRef.countryCodes(forSearchTerm: " +4 ").contains("GB"))
        XCTAssert(phoneNumberUtilRef.countryCodes(forSearchTerm: " 4 ").contains("GB"))
        XCTAssertFalse(phoneNumberUtilRef.countryCodes(forSearchTerm: " +123 ").contains("GB"))
        XCTAssertFalse(phoneNumberUtilRef.countryCodes(forSearchTerm: " +444 ").contains("GB"))
    }

    func testTranslateCursorPosition() {
        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "", to: "", stickingRightward: true))

        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "", to: "", stickingRightward: true))
        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "12", to: "1", stickingRightward: true))
        XCTAssertEqual(1, PhoneNumberUtil.translateCursorPosition(1, from: "12", to: "1", stickingRightward: true))
        XCTAssertEqual(1, PhoneNumberUtil.translateCursorPosition(2, from: "12", to: "1", stickingRightward: true))

        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "1", to: "12", stickingRightward: false))
        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "1", to: "12", stickingRightward: true))
        XCTAssertEqual(1, PhoneNumberUtil.translateCursorPosition(1, from: "1", to: "12", stickingRightward: false))
        XCTAssertEqual(2, PhoneNumberUtil.translateCursorPosition(1, from: "1", to: "12", stickingRightward: true))

        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "12", to: "132", stickingRightward: false))
        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "12", to: "132", stickingRightward: true))
        XCTAssertEqual(1, PhoneNumberUtil.translateCursorPosition(1, from: "12", to: "132", stickingRightward: false))
        XCTAssertEqual(2, PhoneNumberUtil.translateCursorPosition(1, from: "12", to: "132", stickingRightward: true))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(2, from: "12", to: "132", stickingRightward: false))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(2, from: "12", to: "132", stickingRightward: true))

        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(1, PhoneNumberUtil.translateCursorPosition(1, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(2, PhoneNumberUtil.translateCursorPosition(2, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(3, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(4, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(5, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(6, PhoneNumberUtil.translateCursorPosition(6, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(7, PhoneNumberUtil.translateCursorPosition(7, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(8, PhoneNumberUtil.translateCursorPosition(8, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))
        XCTAssertEqual(8, PhoneNumberUtil.translateCursorPosition(9, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: true))

        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(1, PhoneNumberUtil.translateCursorPosition(1, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(2, PhoneNumberUtil.translateCursorPosition(2, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(3, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(4, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(5, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(4, PhoneNumberUtil.translateCursorPosition(6, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(7, PhoneNumberUtil.translateCursorPosition(7, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(8, PhoneNumberUtil.translateCursorPosition(8, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))
        XCTAssertEqual(8, PhoneNumberUtil.translateCursorPosition(9, from: "(55) 123-4567", to: "(551) 234-567", stickingRightward: false))

        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: true))
        XCTAssertEqual(1, PhoneNumberUtil.translateCursorPosition(1, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: true))
        XCTAssertEqual(2, PhoneNumberUtil.translateCursorPosition(2, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: true))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(3, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: true))
        XCTAssertEqual(6, PhoneNumberUtil.translateCursorPosition(4, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: true))
        XCTAssertEqual(7, PhoneNumberUtil.translateCursorPosition(5, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: true))

        XCTAssertEqual(0, PhoneNumberUtil.translateCursorPosition(0, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: false))
        XCTAssertEqual(1, PhoneNumberUtil.translateCursorPosition(1, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: false))
        XCTAssertEqual(2, PhoneNumberUtil.translateCursorPosition(2, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: false))
        XCTAssertEqual(3, PhoneNumberUtil.translateCursorPosition(3, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: false))
        XCTAssertEqual(4, PhoneNumberUtil.translateCursorPosition(4, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: false))
        XCTAssertEqual(7, PhoneNumberUtil.translateCursorPosition(5, from: "(5551) 234-567", to: "(555) 123-4567", stickingRightward: false))
    }

    func testCountryNameFromCountryCode() {
        XCTAssertEqual(PhoneNumberUtil.countryName(fromCountryCode: "US"), "United States")
        XCTAssertEqual(PhoneNumberUtil.countryName(fromCountryCode: "GB"), "United Kingdom")
        XCTAssertEqual(PhoneNumberUtil.countryName(fromCountryCode: "EK"), "Unknown")
        XCTAssertEqual(PhoneNumberUtil.countryName(fromCountryCode: "ZZZ"), "Unknown")
        XCTAssertNotEqual(PhoneNumberUtil.countryName(fromCountryCode: ""), "")
    }
}
