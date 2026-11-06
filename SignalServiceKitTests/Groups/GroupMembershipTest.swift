//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct GroupMembershipTest {
    private static let localAci = LocalIdentifiers.forUnitTests.aci
    private static let otherAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")
    @Test(arguments: [
        (true, [], []),
        (true, [Self.localAci], [Self.localAci]),
        (false, [Self.localAci], [Self.localAci, Self.otherAci]),
        (true, [Self.localAci, Self.otherAci], [Self.localAci, Self.otherAci]),
        (true, [], [Self.localAci]),
        (true, [], [Self.localAci, Self.otherAci]),
        (true, [Self.otherAci], [Self.localAci, Self.otherAci]),
    ])
    func testCanLocalUserLeaveGroup(testCase: (canLeave: Bool, admins: [Aci], members: [Aci])) {
        let localAci = Self.localAci
        let canLeave = GroupMembership.canLocalUserLeaveGroupWithoutChoosingNewAdmin(
            localAci: localAci,
            fullMembers: Set(testCase.members),
            admins: Set(testCase.admins),
        )
        #expect(canLeave == testCase.canLeave)
    }
}
