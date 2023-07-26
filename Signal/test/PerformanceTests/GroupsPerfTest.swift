//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit
import XCTest

class GroupsPerfTest: PerformanceBaseTest {

    private let iterationCount: UInt64 = DebugFlags.fastPerfTests ? 5 : 5 * 1000

    func testMembershipSerialization() {
        setUpIteration()

        let membership = Self.buildMembership()

        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: true) {
            for _ in 0..<iterationCount {
                let data = try! Self.serialize(membership: membership)
                let copy = try! Self.deserialize(data: data)
                assert(membership == copy)
            }
        }
    }

    static func buildMembership() -> GroupMembership {
        let memberCount: UInt = 32

        var builder = GroupMembership.Builder()
        for _ in 0..<memberCount {
            builder.addFullMember(FutureAci.randomForTesting().uuidValue, role: .`normal`)
        }
        for _ in 0..<memberCount {
            builder.addInvitedMember(FutureAci.randomForTesting().uuidValue, role: .`normal`, addedByUuid: FutureAci.randomForTesting().uuidValue)
        }
        for _ in 0..<memberCount {
            builder.addRequestingMember(FutureAci.randomForTesting().uuidValue)
        }
        for i in 0..<memberCount {
            builder.addBannedMember(FutureAci.randomForTesting().uuidValue, bannedAtTimestamp: UInt64(i))
        }
        return builder.build()
    }

    static func serialize(membership: GroupMembership) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: membership, requiringSecureCoding: false)
    }

    static func deserialize(data: Data) throws -> GroupMembership {
        try NSKeyedUnarchiver.unarchivedObject(ofClass: GroupMembership.self, from: data, requiringSecureCoding: false)!
    }
}
