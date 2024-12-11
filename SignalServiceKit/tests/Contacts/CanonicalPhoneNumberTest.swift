//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class CanonicalPhoneNumberTest: XCTestCase {
    func testBenin() {
        let oldFormat = CanonicalPhoneNumber(nonCanonicalPhoneNumber: E164("+22990011234")!)
        XCTAssertEqual(oldFormat.rawValue.stringValue, "+2290190011234")
        XCTAssertEqual(oldFormat.alternatePhoneNumbers().map(\.stringValue), ["+22990011234"])

        let newFormat = CanonicalPhoneNumber(nonCanonicalPhoneNumber: E164("+2290195123456")!)
        XCTAssertEqual(newFormat.rawValue.stringValue, "+2290195123456")
        XCTAssertEqual(newFormat.alternatePhoneNumbers().map(\.stringValue), ["+22995123456"])
    }

    func testArgentina() {
        let otherFormat = CanonicalPhoneNumber(nonCanonicalPhoneNumber: E164("+541123456789")!)
        XCTAssertEqual(otherFormat.rawValue.stringValue, "+5491123456789")
        XCTAssertEqual(otherFormat.alternatePhoneNumbers().map(\.stringValue), ["+541123456789"])

        let preferredFormat = CanonicalPhoneNumber(nonCanonicalPhoneNumber: E164("+5491123456789")!)
        XCTAssertEqual(preferredFormat.rawValue.stringValue, "+5491123456789")
        XCTAssertEqual(preferredFormat.alternatePhoneNumbers().map(\.stringValue), ["+541123456789"])
    }

    func testMexico() {
        let oldFormat = CanonicalPhoneNumber(nonCanonicalPhoneNumber: E164("+5212221234567")!)
        XCTAssertEqual(oldFormat.rawValue.stringValue, "+522221234567")
        XCTAssertEqual(oldFormat.alternatePhoneNumbers().map(\.stringValue), ["+5212221234567"])

        let newFormat = CanonicalPhoneNumber(nonCanonicalPhoneNumber: E164("+522221234567")!)
        XCTAssertEqual(newFormat.rawValue.stringValue, "+522221234567")
        XCTAssertEqual(newFormat.alternatePhoneNumbers().map(\.stringValue), ["+5212221234567"])
    }
}
