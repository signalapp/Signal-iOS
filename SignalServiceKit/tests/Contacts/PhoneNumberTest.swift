//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
