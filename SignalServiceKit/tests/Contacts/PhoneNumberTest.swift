//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class PhoneNumberTestSwift: SSKBaseTestSwift {
    func testTryParsePhoneNumberTextOnly() {
        let testCases: [String: String?] = [
            // Phone numbers with explicit region codes
            "+1 (902) 555-0123": "+19025550123",
            "1 (902) 555-0123": "+19025550123",
            "1-902-555-0123": "+19025550123",
            "1 902 555 0123": "+19025550123",
            "1.902.555.0123": "+19025550123",
            "+33 1 70 39 38 00": "+33170393800",
            // Phone numbers missing a calling code. Assumes local region
            "9025550123": "+19025550123",
            "902-555-0123": "+19025550123",
            "902.555.0123": "+19025550123",
            "902 555 0123": "+19025550123",
            "(902) 555-0123": "+19025550123",
            // Phone numbers outside your region without a plus.
            // You must include a plus when dialing outside of your locale.
            // This might not be desired, but documents existing behavior.
            "33 1 70 39 38 00": nil,
            // Phone numbers with a calling code but without a plus
            "19025550123": "+19025550123",
            // Empty input
            "": nil
        ]
        for (input, expected) in testCases {
            let actual = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: input)?.toE164()
            XCTAssertEqual(actual, expected, input)
        }
    }

    func testTryParsePhoneNumberWithCallingCode() {
        XCTAssertEqual(
            PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: "18085550101", callingCode: "1")?.toE164(),
            "+18085550101"
        )
        XCTAssertEqual(
            PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: "61255504321", callingCode: "61")?.toE164(),
            "+61255504321"
        )
        XCTAssertEqual(
            PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: "493083050", callingCode: "49")?.toE164(),
            "+493083050"
        )
    }

    func test_mx_transition() {
        // MX recently removed the mobile 1. So 521xxx numbers can now be dialed on PTSN as 52xxx
        // But legacy users registered using the 521xxx format, and their signal account/sessions are matched to that number
        // so we need to be permissive about matching *either* format until we have a way to migrate client phone numbers.
        let expectedCandidates: Set<String> = ["+528341639157", "+5218341639157"]
        Assert(parsingRawText: "528341639157", localE164: "+13213214321", includesCandidates: expectedCandidates)
        Assert(parsingRawText: "5218341639157", localE164: "+13213214321", includesCandidates: expectedCandidates)

        // Local MX number infers mexican country when parsing numbers, includes candidates with and without mobile 1.
        Assert(parsingRawText: "8341639157", localE164: "+528341635555", includesCandidates: expectedCandidates)
        Assert(parsingRawText: "18341639157", localE164: "+528341635555", includesCandidates: expectedCandidates)
        Assert(parsingRawText: "8341639157", localE164: "+5218341634444", includesCandidates: expectedCandidates)
        Assert(parsingRawText: "18341639157", localE164: "+5218341634444", includesCandidates: expectedCandidates)
        Assert(parsingRawText: "528341639157", localE164: "+5218341634444", includesCandidates: expectedCandidates)
        Assert(parsingRawText: "5218341639157", localE164: "+5218341634444", includesCandidates: expectedCandidates)
    }
}

func Assert(parsingRawText rawText: String,
            localE164: String,
            includesCandidates expectedCandidates: Set<String>,
            file: StaticString = #file,
            line: UInt = #line) {
    let contactFactory = ContactFactory()
    contactFactory.localClientPhonenumber = localE164
    contactFactory.userTextPhoneNumberAndLabelBuilder = {
        return [(rawText, "Main")]
    }

    let contact = try! contactFactory.build()
    let actual = contact.e164sForIntersection
    let missingNumbers = expectedCandidates.subtracting(actual)
    XCTAssert(missingNumbers == [], "missing candidates: \(missingNumbers)", file: file, line: line)
}
