//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest
@testable import SignalServiceKit

class TSMessageTest: SSKBaseTest {
    private var thread: TSThread!

    override func setUp() {
        super.setUp()

        self.thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(phoneNumber: "fake-thread-id"))
    }

    func testExpiresAtWithoutStartedTimer() {
        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(
            thread: self.thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody("foo"),
        )
        builder.timestamp = 1
        builder.expiresInSeconds = 100

        let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }
        XCTAssertEqual(0, message.expiresAt)
    }

    func testExpiresAtWithStartedTimer() {
        let now = Date.ows_millisecondTimestamp()
        let expirationSeconds: UInt32 = 10

        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(
            thread: self.thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody("foo"),
        )
        builder.timestamp = 1
        builder.expiresInSeconds = expirationSeconds
        builder.expireStartedAt = now

        let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }
        XCTAssertEqual(now + UInt64(expirationSeconds * 1000), message.expiresAt)
    }
}

// MARK: -

// TODO: Remove SSKBaseTest once GroupMembership no longer relies on
// SignalServiceAddress and SignalServiceAddressCache.
class TSMessageDeleteForEveryoneTest: SSKBaseTest {
    private let localIdentifiers = LocalIdentifiers.forUnitTests
    private let otherAci = Aci.randomForTesting()
    private let now = Date()

    // Admin deletes have a longer window than regular deletes, so we can test
    // falling back to an admin delete.
    private let remoteConfig = RemoteConfig(clockSkew: 0, valueFlags: [
        "global.normalDeleteMaxAgeInSeconds": "\(Int(TimeInterval.day))",
        "global.adminDeleteMaxAgeInSeconds": "\(Int(3 * TimeInterval.day))",
    ])

    private struct TestCase: CustomStringConvertible {
        enum Direction {
            case incoming
            case outgoing
        }

        enum Age {
            /// Inside both windows.
            case recent
            /// Outside the regular window, but inside the admin window.
            case old
            /// Outside both windows.
            case veryOld
            /// Sent "in the future".
            case future
        }

        var direction: Direction
        var age: Age
        var hasGiftBadge = false
        var wasRemotelyDeleted = false
        var expected: TSMessage.DeleteForEveryoneType?

        var description: String {
            "\(direction), \(age), hasGiftBadge: \(hasGiftBadge), wasRemotelyDeleted: \(wasRemotelyDeleted)"
        }
    }

    private func runTestCases(
        _ testCases: [TestCase],
        thread: TSThread,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        for testCase in testCases {
            let message = buildMessage(testCase: testCase, thread: thread)
            let deleteType = message.deleteForEveryoneType(
                thread: thread,
                localIdentifiers: localIdentifiers,
                remoteConfig: remoteConfig,
                now: now,
            )
            XCTAssertEqual(deleteType, testCase.expected, "\(testCase)", file: file, line: line)
        }
    }

    private func buildMessage(testCase: TestCase, thread: TSThread) -> TSMessage {
        let date: Date
        switch testCase.age {
        case .recent:
            date = now.addingTimeInterval(-.minute)
        case .old:
            date = now.addingTimeInterval(-2 * .day)
        case .veryOld:
            date = now.addingTimeInterval(-4 * .day)
        case .future:
            date = now.addingTimeInterval(2 * .day)
        }
        let giftBadge = testCase.hasGiftBadge ? OWSGiftBadge(redemptionCredential: Data()) : nil

        switch testCase.direction {
        case .incoming:
            return TSIncomingMessageBuilder.withDefaultValues(
                thread: thread,
                timestamp: date.ows_millisecondsSince1970,
                authorAci: otherAci,
                serverTimestamp: date.ows_millisecondsSince1970,
                wasRemotelyDeleted: testCase.wasRemotelyDeleted,
                giftBadge: giftBadge,
            ).build()
        case .outgoing:
            let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
            builder.timestamp = date.ows_millisecondsSince1970
            builder.giftBadge = giftBadge
            builder.wasRemotelyDeleted = testCase.wasRemotelyDeleted
            return SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }
        }
    }

    private func buildGroupThread(
        localRole: TSGroupMemberRole,
        isTerminated: Bool = false,
    ) -> TSGroupThread {
        var membershipBuilder = GroupMembership.Builder()
        membershipBuilder.addFullMember(localIdentifiers.aci, role: localRole)
        membershipBuilder.addFullMember(otherAci, role: .normal)

        var groupModelBuilder = TSGroupModelBuilder(secretParams: try! GroupSecretParams.generate())
        groupModelBuilder.groupMembership = membershipBuilder.build()
        groupModelBuilder.isTerminated = isTerminated
        return TSGroupThread(groupModel: try! groupModelBuilder.buildAsV2())
    }

    // MARK: -

    func testContactThread() {
        runTestCases(
            [
                TestCase(direction: .outgoing, age: .recent, expected: .regular),
                TestCase(direction: .outgoing, age: .future, expected: .regular),
                TestCase(direction: .outgoing, age: .old, expected: nil),
                TestCase(direction: .outgoing, age: .recent, hasGiftBadge: true, expected: nil),
                TestCase(direction: .outgoing, age: .recent, wasRemotelyDeleted: true, expected: nil),
                TestCase(direction: .incoming, age: .recent, expected: nil),
            ],
            thread: TSContactThread(contactAddress: SignalServiceAddress(otherAci)),
        )
    }

    func testNoteToSelf() {
        runTestCases(
            [
                TestCase(direction: .outgoing, age: .recent, expected: nil),
            ],
            thread: TSContactThread(contactAddress: SignalServiceAddress(localIdentifiers.aci)),
        )
    }

    func testGroupAsAdmin() {
        runTestCases(
            [
                TestCase(direction: .outgoing, age: .recent, expected: .regular),
                TestCase(direction: .outgoing, age: .old, expected: .admin),
                TestCase(direction: .outgoing, age: .veryOld, expected: nil),
                TestCase(direction: .incoming, age: .recent, expected: .admin),
                TestCase(direction: .incoming, age: .old, expected: .admin),
                TestCase(direction: .incoming, age: .future, expected: .admin),
                TestCase(direction: .incoming, age: .veryOld, expected: nil),
                TestCase(direction: .incoming, age: .recent, hasGiftBadge: true, expected: nil),
                TestCase(direction: .incoming, age: .recent, wasRemotelyDeleted: true, expected: nil),
            ],
            thread: buildGroupThread(localRole: .administrator),
        )
    }

    func testGroupAsNonAdmin() {
        runTestCases(
            [
                TestCase(direction: .outgoing, age: .recent, expected: .regular),
                TestCase(direction: .outgoing, age: .old, expected: nil),
                TestCase(direction: .incoming, age: .recent, expected: nil),
            ],
            thread: buildGroupThread(localRole: .normal),
        )
    }

    func testTerminatedGroup() {
        runTestCases(
            [
                TestCase(direction: .outgoing, age: .recent, expected: nil),
                TestCase(direction: .incoming, age: .recent, expected: nil),
            ],
            thread: buildGroupThread(localRole: .administrator, isTerminated: true),
        )
    }
}
