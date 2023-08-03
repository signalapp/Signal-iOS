//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit
@testable import SignalUI

final class PhoneNumberFinderTests: XCTestCase {

    private struct MockContactDiscoveryManager: ContactDiscoveryManager {
        var lookUpBlock: ((Set<String>) -> Promise<Set<SignalRecipient>>)?

        func lookUp(phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>> {
            lookUpBlock?(phoneNumbers) ?? .value([])
        }
    }

    override func setUp() {
        super.setUp()

        SetCurrentAppContext(TestAppContext(), true)
        MockSSKEnvironment.activate()
    }

    func testValidCallingCodes() {
        for callingCode in PhoneNumberFinder.validCallingCodes {
            XCTAssertNotEqual(callingCode, "")
            XCTAssertNotEqual(callingCode, "+0")
            XCTAssertTrue(callingCode.hasPrefix("+"), "callingCode: \(callingCode)")
        }
    }

    func testParseResults() {
        let finder = PhoneNumberFinder(
            localNumber: "+16505550100",
            contactDiscoveryManager: MockContactDiscoveryManager()
        )
        struct TestCase {
            var searchText: String
            var searchResults: [String]
        }
        let testCases: [TestCase] = [
            // test empty results
            TestCase(searchText: "", searchResults: []),
            TestCase(searchText: "12", searchResults: []),
            TestCase(searchText: "+123.cat", searchResults: []),
            TestCase(searchText: "cat.123", searchResults: []),

            // test multiple search results
            TestCase(searchText: "5215550100", searchResults: ["+15215550100", "+5215550100", "+525550100"]),

            // test punctuation and whitespace
            TestCase(searchText: "123", searchResults: ["+1123"]),
            TestCase(searchText: "+123", searchResults: ["+123"]),
            TestCase(searchText: "+1 (23", searchResults: ["+123"]),
            TestCase(searchText: "+1 (234) 555-0100", searchResults: ["+12345550100"]),

            // test too many digits
            TestCase(searchText: "+ 12345 12345 12345 1234", searchResults: ["+1234512345123451234"]),
            TestCase(searchText: "+ 12345 12345 12345 12345", searchResults: [])
        ]
        for testCase in testCases {
            let searchResults = finder.parseResults(for: testCase.searchText).map { $0.maybeValidE164 }
            XCTAssertEqual(searchResults, testCase.searchResults, "searchText: \(testCase.searchText)")
        }
    }

    func testLookUp() throws {
        struct TestCase {
            var searchResult: PhoneNumberFinder.SearchResult
            var isValid: Bool
            var isFound: Bool
        }
        let testCases: [TestCase] = [
            TestCase(searchResult: .valid(validE164: "+16505550100"), isValid: true, isFound: true),
            TestCase(searchResult: .valid(validE164: "+16505550101"), isValid: true, isFound: false),
            TestCase(searchResult: .maybeValid(maybeValidE164: "+16505550102"), isValid: true, isFound: true),
            TestCase(searchResult: .maybeValid(maybeValidE164: "+1650"), isValid: false, isFound: false)
        ]
        for testCase in testCases {
            let context = "searchResult: \(testCase.searchResult)"
            let finder = PhoneNumberFinder(
                localNumber: "+16505550100",
                contactDiscoveryManager: MockContactDiscoveryManager(lookUpBlock: { phoneNumbers in
                    XCTAssertTrue(testCase.isValid)
                    return .value(testCase.isFound ? [SignalRecipient(aci: Aci.randomForTesting(), phoneNumber: nil)] : [])
                })
            )
            let resultPromise = finder.lookUp(phoneNumber: testCase.searchResult)
            let lookupResult = try XCTUnwrap(resultPromise.result).get()
            switch lookupResult {
            case .success:
                XCTAssertTrue(testCase.isFound, context)
            case .notFound(let validE164):
                XCTAssertFalse(testCase.isFound, context)
                XCTAssertEqual(validE164, testCase.searchResult.maybeValidE164, context)
            case .notValid(let invalidE164):
                XCTAssertFalse(testCase.isValid, context)
                XCTAssertEqual(invalidE164, testCase.searchResult.maybeValidE164, context)
            }
        }
    }

}
