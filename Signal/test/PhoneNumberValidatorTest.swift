//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Signal

class PhoneNumberValidatorTest: SignalBaseTest {

    func assertValid(e164: String, file: StaticString = #file, line: UInt = #line) {
        let validator = PhoneNumberValidator()
        guard let phoneNumber = PhoneNumber(fromE164: e164) else {
            XCTFail("unparsable phone number", file: file, line: line)
            return
        }
        let isValid = validator.isValidForRegistration(phoneNumber: phoneNumber)
        XCTAssertTrue(isValid, file: file, line: line)
    }

    func assertInvalid(e164: String, file: StaticString = #file, line: UInt = #line) {
        let validator = PhoneNumberValidator()
        guard let phoneNumber = PhoneNumber(fromUserSpecifiedText: e164) else {
            // number wasn't even parsable
            return
        }
        let isValid = validator.isValidForRegistration(phoneNumber: phoneNumber)
        XCTAssertFalse(isValid, file: file, line: line)
    }

    func testUnitedStates() {
        // valid us number
        assertValid(e164: "+13235551234")

        // too short
        assertInvalid(e164: "+1323555123")

        // too long
        assertInvalid(e164: "+132355512345")

        // not a US phone number
        assertValid(e164: "+3235551234")
    }

    func testBrazil() {
        // valid mobile
        assertValid(e164: "+5532912345678")

        // valid landline
        assertValid(e164: "+553212345678")

        // mobile length, but with out the leading '9'
        assertInvalid(e164: "+5532812345678")

        // too short
        assertInvalid(e164: "+5532812345678")

        // too long landline
        assertInvalid(e164: "+5532123456789")
        assertInvalid(e164: "+55321234567890")

        // too long mobile
        assertInvalid(e164: "+55329123456789")
        assertInvalid(e164: "+553291234567890")
    }
}
