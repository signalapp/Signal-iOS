//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct HydratedMessageBodyTest {
    struct TestCase {
        var text: String
        var mentions: [NSRange]
        var spoilers: [NSRange]
        var hydratedText: String
    }

    @Test(arguments: [
        TestCase(text: "ABC", mentions: [NSMakeRange(2, 1)], spoilers: [NSMakeRange(1, 2)], hydratedText: "A■■■■"),
        TestCase(text: "ABC", mentions: [NSMakeRange(2, 2)], spoilers: [NSMakeRange(1, 2)], hydratedText: "A■■"),
        TestCase(text: "ABC", mentions: [NSMakeRange(1, 200)], spoilers: [NSMakeRange(2, 1)], hydratedText: "A■■"),
        TestCase(text: "ABC", mentions: [NSMakeRange(0, 200)], spoilers: [NSMakeRange(1, 1)], hydratedText: "■■■"),
    ])
    func testVarious(testCase: TestCase) {
        let hydratedMessageBody = HydratedMessageBody(
            messageBody: MessageBody(
                text: testCase.text,
                ranges: MessageBodyRanges(
                    mentions: testCase.mentions.map({ NSRangedValue(Aci.randomForTesting(), range: $0) }),
                    styles: testCase.spoilers.map({ NSRangedValue(.spoiler, range: $0) }),
                ),
            ),
            mentionHydrator: { aci in .hydrate("John") },
            isRTL: false,
        )
        #expect(hydratedMessageBody.asPlaintext() == testCase.hydratedText)
    }
}
