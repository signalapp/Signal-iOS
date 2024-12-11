//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class PhoneNumberTest: XCTestCase {
    private var phoneNumberUtilRef: PhoneNumberUtil!

    override func setUp() {
        super.setUp()
        phoneNumberUtilRef = PhoneNumberUtil()
    }

    func testInitWithE164() {
        let shouldBeNil: [String] = ["", "+", "1", "19025550123", "+190255501238"]
        for input in shouldBeNil {
            XCTAssertNil(phoneNumberUtilRef.parseE164(input), input)
        }

        let shouldNotBeNil: [String] = ["+19025550123", "+33170393800"]
        for input in shouldNotBeNil {
            XCTAssertEqual(phoneNumberUtilRef.parseE164(input)?.e164, input, input)
        }
    }

    func testTryParsePhoneNumberTextOnly() {
        let testCases: [(inputValue: String, expectedValue: String?)] = [
            // Phone numbers with explicit region codes
            ("+1 (902) 555-0123", "+19025550123"),
            ("1 (902) 555-0123", "+19025550123"),
            ("1-902-555-0123", "+19025550123"),
            ("1 902 555 0123", "+19025550123"),
            ("1.902.555.0123", "+19025550123"),
            ("+33 1 70 39 38 00", "+33170393800"),
            // Phone numbers missing a calling code. Assumes local region
            ("9025550123", "+19025550123"),
            ("902-555-0123", "+19025550123"),
            ("902.555.0123", "+19025550123"),
            ("902 555 0123", "+19025550123"),
            ("(902) 555-0123", "+19025550123"),
            // Phone numbers outside your region without a plus.
            // You must include a plus when dialing outside of your locale.
            // This might not be desired, but documents existing behavior.
            ("33 1 70 39 38 00", nil),
            // Phone numbers with a calling code but without a plus
            ("19025550123", "+19025550123"),
            // Empty input
            ("", nil),
        ]
        for (inputValue, expectedValue) in testCases {
            let actualValue = phoneNumberUtilRef.parsePhoneNumber(userSpecifiedText: inputValue)?.e164
            XCTAssertEqual(actualValue, expectedValue, inputValue)
        }
    }

    func testNationalNumber() throws {
        let testCases: [(inputValue: String, expectedValue: String)] = [
            ("+19025550123", "9025550123"),
            ("+447700900123", "7700900123"),
            ("+33639981234", "639981234"),
        ]

        for testCase in testCases {
            let phoneNumber = try XCTUnwrap(phoneNumberUtilRef.parseE164(testCase.inputValue))
            let actualValue = phoneNumberUtilRef.nationalNumber(for: phoneNumber)
            XCTAssertEqual(actualValue, testCase.expectedValue)
        }
    }

    func testTryParsePhoneNumbersFromUserSpecifiedText_SimpleUSA() {
        let expectedValue = "+13235551234"
        let inputValues = [
            "323 555 1234",
            "323-555-1234",
            "323.555.1234",
            "1-323-555-1234",
            "+13235551234",
        ]
        for inputValue in inputValues {
            let phoneNumbers = phoneNumberUtilRef.parsePhoneNumbers(userSpecifiedText: inputValue, localPhoneNumber: "+13213214321")
            XCTAssertEqual(phoneNumbers.first?.e164, expectedValue, inputValue)
        }
    }

    func testMissingAreaCode_USA() {
        let localNumber = "+13233214321"
        let testCases: [(inputValue: String, expectedValue: String, isExpected: Bool)] = [
            // Add area code to numbers that look like "local" numbers
            ("555-1234", "+13235551234", true),
            ("5551234", "+13235551234", true),
            ("555 1234", "+13235551234", true),
            // Discard numbers which libPhoneNumber considers "impossible", even if they have a leading "+"
            ("+5551234", "+5551234", false),
            // Don't infer area code when number already has one
            ("570 555 1234", "+15705551234", true),
            // Don't touch numbers that are already in e164
            ("+33170393800", "+33170393800", true),
        ]
        for testCase in testCases {
            let phoneNumbers = phoneNumberUtilRef.parsePhoneNumbers(
                userSpecifiedText: testCase.inputValue,
                localPhoneNumber: localNumber
            )
            XCTAssertEqual(
                phoneNumbers.contains(where: { $0.e164 == testCase.expectedValue }),
                testCase.isExpected,
                testCase.inputValue
            )
        }
    }

    func testMissingAreaCode_Brazil() {
        let localNumber = "+5521912345678"
        let testCases: [(inputValue: String, expectedValue: String, isExpected: Bool)] = [
            // Add area code to land-line numbers that look like "local" numbers
            ("87654321", "+552187654321", true),
            ("8765-4321", "+552187654321", true),
            ("8765 4321", "+552187654321", true),
            // Add area code to mobile numbers that look like "local" numbers
            ("987654321", "+5521987654321", true),
            ("9 8765-4321", "+5521987654321", true),
            ("9 8765 4321", "+5521987654321", true),
            // Don't touch land-line numbers that already have an area code
            ("22 8765 4321", "+552287654321", true),
            // Don't touch mobile numbers that already have an area code
            ("22 9 8765 4321", "+5522987654321", true),
            // Don't touch numbers that are already in e164
            ("+33170393800", "+33170393800", true),
        ]
        for testCase in testCases {
            let phoneNumbers = phoneNumberUtilRef.parsePhoneNumbers(
                userSpecifiedText: testCase.inputValue,
                localPhoneNumber: localNumber
            )
            XCTAssertEqual(
                phoneNumbers.contains(where: { $0.e164 == testCase.expectedValue }),
                testCase.isExpected,
                testCase.inputValue
            )
        }
    }
}
