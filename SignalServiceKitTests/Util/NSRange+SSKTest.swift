//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct NSRangeTest {
    @Test(arguments: [
        ([], []),
        ([NSRange(location: 0, length: 1)], []),
        (
            [NSRange(location: 1, length: 2), NSRange(location: 5, length: 2), NSRange(location: 7, length: 1)],
            [NSRange(location: 3, length: 2), NSRange(location: 7, length: 0)],
        ),
    ])
    func testGapsBetweenNonOverlappingSortedRanges(testCase: (input: [NSRange], expectedOutput: [NSRange])) {
        let actualOutput = NSRange.gapsBetweenNonOverlappingSortedRanges(testCase.input)
        #expect(actualOutput == testCase.expectedOutput)
    }
}
