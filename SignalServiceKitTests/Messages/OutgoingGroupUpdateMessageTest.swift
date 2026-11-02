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

    func testIsUrgent() throws {
        let message = try write { transaction -> OutgoingGroupUpdateMessage in
            OutgoingGroupUpdateMessage(
                in: try createThread(transaction: transaction),
                expiresInSeconds: 60,
                additionalRecipients: [],
                transaction: transaction,
            )
        }
        XCTAssertFalse(message.isUrgent)

        let urgentMessage = try write { transaction -> OutgoingGroupUpdateMessage in
            OutgoingGroupUpdateMessage(
                in: try createThread(transaction: transaction),
                expiresInSeconds: 60,
                additionalRecipients: [],
                isUrgent: true,
                transaction: transaction,
            )
        }
        XCTAssertTrue(urgentMessage.isUrgent)
    }
}
