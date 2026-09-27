//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
@testable import SignalServiceKit

struct PhoneNumberRegionsTest {
    @Test(arguments: [
        ("", []),
        ("   ", []),
        ("a", []),
        ("1", ["1"]),
        (" 1a ", ["1"]),
        ("+1,", ["1"]),
        ("1١", ["1"]),
        ("6️⃣1", ["1"]),
        ("1,2 345, +6 7,, ,89,٦,6️⃣", ["1", "2345", "67", "89"]),
    ])
    func testRemoteConfig(testCase: (remoteConfigValue: String, regions: [String])) {
        let regions = PhoneNumberRegions.parseRemoteConfigRegions(testCase.remoteConfigValue)
        #expect(Array(regions) == testCase.regions)
    }

    @Test
    func testIsEmpty() {
        let empty = PhoneNumberRegions([])
        #expect(empty.isEmpty)

        let notEmpty = PhoneNumberRegions(["1", "44"])
        #expect(!notEmpty.isEmpty)
    }

    @Test
    func testContains() {
        let regions = PhoneNumberRegions(["1", "44"])
        #expect(regions.contains(e164: "+17345550123"))
        #expect(regions.contains(e164: "+447700900123"))
        #expect(!regions.contains(e164: "+33639981234"))
        // This tests the caching behavior, which should not affect results.
        #expect(!regions.contains(e164: "+33639981234"))
    }
}
