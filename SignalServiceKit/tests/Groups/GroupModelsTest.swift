//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

private extension UUID {
    static let uuid1 = UUID()
    static let uuid2 = UUID()
    static let uuid3 = UUID()
}

class GroupModelsTest: SSKBaseTestSwift {

    func testGroupMembershipChangingFullMembers() {
        var builder1 = GroupMembership.Builder()
        builder1.addFullMember(.uuid1, role: .normal)
        let membership1 = builder1.build()

        var builder2 = GroupMembership.Builder()
        builder2.addFullMember(.uuid1, role: .administrator)
        let membership2 = builder2.build()

        var builder3 = GroupMembership.Builder()
        builder3.addFullMember(.uuid1, role: .normal)
        builder3.addFullMember(.uuid2, role: .normal)
        let membership3 = builder3.build()

        var builder4 = GroupMembership.Builder()
        builder4.addFullMember(.uuid1, role: .normal)
        let membership4 = builder4.build()

        XCTAssertEqual(membership1, membership4)

        XCTAssertNotEqual(membership1, membership2)

        XCTAssertNotEqual(membership1, membership3)

        XCTAssertNotEqual(membership2, membership3)
    }

    func testGroupMembershipChangingDidJoinFromInviteLink() {
        var builder1 = GroupMembership.Builder()
        builder1.addFullMember(.uuid1, role: .normal, didJoinFromInviteLink: true)
        let membership1 = builder1.build()

        var builder2 = GroupMembership.Builder()
        builder2.addFullMember(.uuid1, role: .normal, didJoinFromInviteLink: false)
        let membership2 = builder2.build()

        XCTAssertEqual(membership1, membership2)
    }

    func testGroupMembershipChangingRequestingMembers() {
        var builder1 = GroupMembership.Builder()
        builder1.addFullMember(.uuid1, role: .normal)
        let membership1 = builder1.build()

        var builder2 = GroupMembership.Builder()
        builder2.addFullMember(.uuid1, role: .normal)
        builder2.addRequestingMember(.uuid2)
        let membership2 = builder2.build()

        var builder3 = GroupMembership.Builder()
        builder3.addFullMember(.uuid1, role: .normal)
        builder3.addRequestingMember(.uuid3)
        let membership3 = builder3.build()

        var builder4 = GroupMembership.Builder()
        builder4.addFullMember(.uuid1, role: .normal)
        builder4.addRequestingMember(.uuid2)
        let membership4 = builder4.build()

        XCTAssertFalse(membership1 == membership2)

        XCTAssertFalse(membership1 == membership3)

        XCTAssertFalse(membership2 == membership3)

        XCTAssertTrue(membership2 == membership4)
    }

    func testGroupMembershipChangingBannedMembers() {
        var builder1 = GroupMembership.Builder()
        builder1.addFullMember(.uuid1, role: .normal)
        let membership1 = builder1.build()

        var builder2 = membership1.asBuilder
        builder2.addFullMember(.uuid1, role: .normal)
        builder2.addBannedMember(.uuid2, bannedAtTimestamp: 3)
        let membership2 = builder2.build()

        var builder3 = GroupMembership.Builder()
        builder3.addFullMember(.uuid1, role: .normal)
        builder3.addBannedMember(.uuid2, bannedAtTimestamp: 12)
        let membership3 = builder3.build()

        var builder4 = GroupMembership.Builder()
        builder4.addFullMember(.uuid1, role: .normal)
        builder4.addBannedMember(.uuid2, bannedAtTimestamp: 3)
        builder4.addBannedMember(.uuid3, bannedAtTimestamp: 4)
        let membership4 = builder4.build()

        var builder5 = GroupMembership.Builder()
        builder5.addFullMember(.uuid1, role: .normal)
        builder5.addBannedMember(.uuid2, bannedAtTimestamp: 3)
        builder5.addBannedMember(.uuid3, bannedAtTimestamp: 4)
        let membership5 = builder5.build()

        XCTAssertNotEqual(membership1, membership2)

        XCTAssertNotEqual(membership2, membership3)

        XCTAssertNotEqual(membership3, membership4)

        XCTAssertEqual(membership4, membership5)
    }
}
