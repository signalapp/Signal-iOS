//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Contacts
@testable import SignalUI

final class ContactsPickerTest: XCTestCase {
    func testCollation() {
        struct TestCase {
            var givenName: String?
            var familyName: String?
            var emailAddress: String?
            var sortOrder: CNContactSortOrder
            var expectedResult: String
        }
        let testCases: [TestCase] = [
            TestCase(givenName: nil, familyName: nil, sortOrder: .familyName, expectedResult: ""),
            TestCase(givenName: " Alice", familyName: nil, sortOrder: .familyName, expectedResult: "Alice"),
            TestCase(givenName: "", familyName: "Johnson ", sortOrder: .familyName, expectedResult: "Johnson"),
            TestCase(givenName: "Alice ", familyName: " Johnson", sortOrder: .familyName, expectedResult: "Johnson Alice"),
            TestCase(givenName: "Alice ", familyName: " Johnson", emailAddress: "abc@example.com", sortOrder: .givenName, expectedResult: "Alice   Johnson"),
            TestCase(emailAddress: "  abc@example.com", sortOrder: .givenName, expectedResult: "abc@example.com")
        ]
        for testCase in testCases {
            let cnContact = CNMutableContact()
            if let givenName = testCase.givenName {
                cnContact.givenName = givenName
            }
            if let familyName = testCase.familyName {
                cnContact.familyName = familyName
            }
            if let emailAddress = testCase.emailAddress {
                cnContact.emailAddresses.append(CNLabeledValue(label: nil, value: emailAddress as NSString))
            }

            let actualResult = cnContact.collationName(sortOrder: testCase.sortOrder)
            XCTAssertEqual(actualResult, testCase.expectedResult)
        }
    }
}
