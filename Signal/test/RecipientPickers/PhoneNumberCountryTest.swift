//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalUI

final class PhoneNumberCountryTest: XCTestCase {
    func testCountryCodesForSearchTerm() {
        func countryCodes(forSearchTerm searchTerm: String?) -> [String] {
            return PhoneNumberCountry.buildCountries(searchText: searchTerm).map(\.countryCode)
        }
        // Empty search.
        XCTAssertGreaterThan(countryCodes(forSearchTerm: nil).count, 30)
        XCTAssertGreaterThan(countryCodes(forSearchTerm: "").count, 30)
        XCTAssertGreaterThan(countryCodes(forSearchTerm: " ").count, 30)

        // Searches with no results.
        XCTAssertEqual(countryCodes(forSearchTerm: " . ").count, 0)
        XCTAssertEqual(countryCodes(forSearchTerm: " XXXXX ").count, 0)
        XCTAssertEqual(countryCodes(forSearchTerm: " ! ").count, 0)

        // Search by country code.
        XCTAssertEqual(countryCodes(forSearchTerm: "GB"), ["GB"])
        XCTAssertEqual(countryCodes(forSearchTerm: "gb"), ["GB"])
        XCTAssertEqual(countryCodes(forSearchTerm: "GB "), ["GB"])
        XCTAssertEqual(countryCodes(forSearchTerm: " GB"), ["GB"])
        XCTAssert(countryCodes(forSearchTerm: " G").contains("GB"))
        XCTAssertFalse(countryCodes(forSearchTerm: " B").contains("GB"))

        // Search by country name.
        XCTAssertEqual(countryCodes(forSearchTerm: "united kingdom"), ["GB"])
        XCTAssertEqual(countryCodes(forSearchTerm: " UNITED KINGDOM "), ["GB"])
        XCTAssertEqual(countryCodes(forSearchTerm: " UNITED KING "), ["GB"])
        XCTAssertEqual(countryCodes(forSearchTerm: " UNI KING "), ["GB"])
        XCTAssertEqual(countryCodes(forSearchTerm: " u k "), ["GB"])
        XCTAssert(countryCodes(forSearchTerm: " u").contains("GB"))
        XCTAssert(countryCodes(forSearchTerm: " k").contains("GB"))
        XCTAssertFalse(countryCodes(forSearchTerm: " m").contains("GB"))

        // Search by calling code.
        XCTAssert(countryCodes(forSearchTerm: " +44 ").contains("GB"))
        XCTAssert(countryCodes(forSearchTerm: " 44 ").contains("GB"))
        XCTAssert(countryCodes(forSearchTerm: " +4 ").contains("GB"))
        XCTAssert(countryCodes(forSearchTerm: " 4 ").contains("GB"))
        XCTAssertFalse(countryCodes(forSearchTerm: " +123 ").contains("GB"))
        XCTAssertFalse(countryCodes(forSearchTerm: " +444 ").contains("GB"))
    }
}
