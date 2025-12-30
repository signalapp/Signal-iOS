//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class OutgoingGroupUpdateMessageTest: SSKBaseTest {
    override func setUp() {
        super.setUp()
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }
    }

    func throwSkipForCompileOnlyTest() throws {
        throw XCTSkip("compilation-only test")
    }

    func createThread(transaction: DBWriteTransaction) throws -> TSGroupThread {
        try GroupManager.createGroupForTests(
            members: [],
            name: "Test group",
            transaction: transaction,
        )
    }

    func testShouldBeSaved() throws {
        // TODO: Fix this test.
        try throwSkipForCompileOnlyTest()

        let thread = try write { try createThread(transaction: $0) }
        read { transaction in
            let metaMessages: [TSGroupMetaMessage: Bool] = [
                .unspecified: true,
                .new: false,
                .update: false,
                .deliver: true,
                .quit: false,
                .requestInfo: false,
            ]
            for (groupMetaMessage, expected) in metaMessages {
                let message = OutgoingGroupUpdateMessage(
                    in: thread,
                    groupMetaMessage: groupMetaMessage,
                    expiresInSeconds: 60,
                    additionalRecipients: [],
                    transaction: transaction,
                )
                let actual = message.shouldBeSaved
                XCTAssertEqual(actual, expected, "\(groupMetaMessage.rawValue)")
            }
        }
    }

    func testIsUrgent() throws {
        let message = try write { transaction -> OutgoingGroupUpdateMessage in
            OutgoingGroupUpdateMessage(
                in: try createThread(transaction: transaction),
                groupMetaMessage: .update,
                expiresInSeconds: 60,
                additionalRecipients: [],
                transaction: transaction,
            )
        }
        XCTAssertFalse(message.isUrgent)

        let urgentMessage = try write { transaction -> OutgoingGroupUpdateMessage in
            OutgoingGroupUpdateMessage(
                in: try createThread(transaction: transaction),
                groupMetaMessage: .update,
                expiresInSeconds: 60,
                additionalRecipients: [],
                isUrgent: true,
                transaction: transaction,
            )
        }
        XCTAssertTrue(urgentMessage.isUrgent)
    }
}
