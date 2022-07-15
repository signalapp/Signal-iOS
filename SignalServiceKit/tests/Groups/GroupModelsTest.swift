//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

class GroupModelsTest: SSKBaseTestSwift {

    func test_groupMembershipComparison() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let uuid3 = UUID()
        let uuid4 = UUID()

        var membershipBuilder1 = GroupMembership.Builder()
        membershipBuilder1.addFullMember(uuid1, role: .`normal`)
        membershipBuilder1.addRequestingMember(uuid2)
        let membership1 = membershipBuilder1.build()

        var membershipBuilder2 = GroupMembership.Builder()
        membershipBuilder2.addFullMember(uuid1, role: .`normal`)
        let membership2 = membershipBuilder2.build()

        var membershipBuilder3 = GroupMembership.Builder()
        membershipBuilder3.addFullMember(uuid1, role: .`normal`)
        membershipBuilder3.addRequestingMember(uuid2)
        let membership3 = membershipBuilder3.build()

        var membershipBuilder4 = GroupMembership.Builder()
        membershipBuilder4.addFullMember(uuid1, role: .`normal`)
        let membership4 = membershipBuilder4.build()

        XCTAssertFalse(membership1 == membership2)
        XCTAssertTrue(membership1 == membership3)
        XCTAssertFalse(membership1 == membership4)

        XCTAssertFalse(membership2 == membership3)
        XCTAssertTrue(membership2 == membership4)

        XCTAssertFalse(membership3 == membership4)

        var membershipBuilder5 = GroupMembership.Builder()
        membershipBuilder5.addInvitedMember(uuid3, role: .normal, addedByUuid: uuid1)
        membershipBuilder5.addBannedMember(uuid4, bannedAtTimestamp: 3)
        let membership5 = membershipBuilder5.build()

        var membershipBuilder6 = GroupMembership.Builder()
        membershipBuilder6.addInvitedMember(uuid3, role: .normal, addedByUuid: uuid1)
        membershipBuilder6.addBannedMember(uuid4, bannedAtTimestamp: 3)
        let membership6 = membershipBuilder6.build()

        var membershipBuilder7 = GroupMembership.Builder()
        membershipBuilder7.addBannedMember(uuid3, bannedAtTimestamp: 12)
        membershipBuilder7.addBannedMember(uuid4, bannedAtTimestamp: 3)
        let membership7 = membershipBuilder7.build()

        XCTAssertTrue(membership5 == membership6)
        XCTAssertFalse(membership5 == membership7)
    }
}
