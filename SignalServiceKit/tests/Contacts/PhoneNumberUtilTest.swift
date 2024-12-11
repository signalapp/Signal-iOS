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
        self.phoneNumberUtilRef = PhoneNumberUtil()
    }

    func test_callingCodeFromCountryCode() {
        XCTAssertEqual("+1", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "US"))
        XCTAssertEqual("+44", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "GB"))
        XCTAssertEqual("+598", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "UY"))
        XCTAssertEqual("+0", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "QG"))
        XCTAssertEqual("+0", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "EK"))
        XCTAssertEqual("+0", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "ZZZ"))
        XCTAssertEqual("+0", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: ""))
        XCTAssertEqual("+0", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "+"))
        XCTAssertEqual("+0", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "9"))
        XCTAssertEqual("+1", phoneNumberUtilRef.plusPrefixedCallingCode(fromCountryCode: "US "))
    }

    func test_examplePhoneNumberForCountryCode() {
        XCTAssertEqual("+12015550123", phoneNumberUtilRef.examplePhoneNumber(forCountryCode: "US"))
        XCTAssertEqual("+447400123456", phoneNumberUtilRef.examplePhoneNumber(forCountryCode: "GB"))
        XCTAssertEqual("+59894231234", phoneNumberUtilRef.examplePhoneNumber(forCountryCode: "UY"))
    }

    func test_getRegionCodeForCountryCode() {
        XCTAssertEqual("US", phoneNumberUtilRef.getRegionCodeForCallingCode(1))
        XCTAssertEqual("GB", phoneNumberUtilRef.getRegionCodeForCallingCode(44))
        XCTAssertEqual("UY", phoneNumberUtilRef.getRegionCodeForCallingCode(598))
        XCTAssertEqual("ZZ", phoneNumberUtilRef.getRegionCodeForCallingCode(0))
        XCTAssertEqual("ZZ", phoneNumberUtilRef.getRegionCodeForCallingCode(99999))
        XCTAssertEqual("ZZ", phoneNumberUtilRef.getRegionCodeForCallingCode(-1))
    }

    func test_getCallingCodeForRegion() {
        XCTAssertEqual(1, phoneNumberUtilRef.getCallingCode(forRegion: "US"))
        XCTAssertEqual(44, phoneNumberUtilRef.getCallingCode(forRegion: "GB"))
        XCTAssertEqual(598, phoneNumberUtilRef.getCallingCode(forRegion: "UY"))
        // Invalid regions.
        XCTAssertEqual(0, phoneNumberUtilRef.getCallingCode(forRegion: "UK"))
        XCTAssertEqual(1, phoneNumberUtilRef.getCallingCode(forRegion: "US "))
        XCTAssertEqual(0, phoneNumberUtilRef.getCallingCode(forRegion: " "))
        XCTAssertEqual(0, phoneNumberUtilRef.getCallingCode(forRegion: ""))
        XCTAssertEqual(0, phoneNumberUtilRef.getCallingCode(forRegion: "+1"))
        XCTAssertEqual(0, phoneNumberUtilRef.getCallingCode(forRegion: "ZZ"))
        XCTAssertEqual(0, phoneNumberUtilRef.getCallingCode(forRegion: "+"))
        XCTAssertEqual(0, phoneNumberUtilRef.getCallingCode(forRegion: "ZQ"))
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
