//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import LibSignalClient
@testable import SignalServiceKit

@MainActor
struct OWSPollTest {
    let aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")

    @Test
    func testSortedOptions() throws {
        let poll = OWSPoll(
            interactionId: 1,
            question: "Are polls working?",
            options: ["Yes", "No", "Maybe"],
            localUserPendingState: [:],
            allowsMultiSelect: false,
            votes: [:],
            isEnded: false,
            ownerIsLocalUser: true,
        )

        let sortedOptions = poll.sortedOptions()
        #expect(sortedOptions.count == 3)
        #expect(sortedOptions[0].text == "Yes", "Sorted options should be in the same order as originally input")
        #expect(sortedOptions[1].text == "No", "Sorted options should be in the same order as originally input")
        #expect(sortedOptions[2].text == "Maybe", "Sorted options should be in the same order as originally input")
    }
}
