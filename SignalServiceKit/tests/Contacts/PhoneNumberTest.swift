//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class PhoneNumberTestSwift: SSKBaseTestSwift {

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

    func test_resemblesE164() {
        XCTAssertTrue(PhoneNumber.resemblesE164("+5218341639157"))
        XCTAssertFalse(PhoneNumber.resemblesE164("5218341639157"))
        XCTAssertTrue(PhoneNumber.resemblesE164("+18018108311"))
        XCTAssertFalse(PhoneNumber.resemblesE164("18018108311"))

        // E164 must have leading +.
        XCTAssertFalse(PhoneNumber.resemblesE164("a18018108311"))

        // E164 must have exactly 1 leading +.
        XCTAssertFalse(PhoneNumber.resemblesE164("++18018108311"))

        // E164 must only contains 0-9 arabic digits.
        XCTAssertFalse(PhoneNumber.resemblesE164("+18018108311a"))

        // E164 must have at least 10 digits.
        XCTAssertTrue(PhoneNumber.resemblesE164("+1234567890"))
        XCTAssertFalse(PhoneNumber.resemblesE164("+123456789"))
        // E164 must have no more than 15 digits.
        XCTAssertTrue(PhoneNumber.resemblesE164("+123456789012345"))
        XCTAssertFalse(PhoneNumber.resemblesE164("+1234567890123456"))
        XCTAssertFalse(PhoneNumber.resemblesE164("+12345678901234567890"))
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
