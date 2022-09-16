//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OutgoingGroupUpdateMessageTest: SSKBaseTestSwift {
    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+12225550101", uuid: UUID(), pni: UUID())
    }

    func createThread(transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        try GroupManager.createGroupForTests(
            members: [],
            name: "Test group",
            groupsVersion: .V2,
            transaction: transaction
        )
    }

    func testShouldBeSaved() throws {
        let thread = try write { try createThread(transaction: $0) }
        read { transaction in
            let metaMessages: [TSGroupMetaMessage: Bool] = [
                .unspecified: true,
                .new: false,
                .update: false,
                .deliver: true,
                .quit: false,
                .requestInfo: false
            ]
            for (groupMetaMessage, expected) in metaMessages {
                let message = OutgoingGroupUpdateMessage(
                    in: thread,
                    groupMetaMessage: groupMetaMessage,
                    expiresInSeconds: 60,
                    additionalRecipients: [],
                    transaction: transaction
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
                transaction: transaction
            )
        }
        XCTAssertFalse(message.isUrgent)
    }
}
