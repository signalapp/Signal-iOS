//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit

import LibSignalClient
import XCTest

final class TSMessageStorageTest: SSKBaseTest {
    private var thread: TSContactThread!

    var localAci: Aci { return Aci.parseFrom(aciString: "00000000-0000-4000-8000-000000000000")! }
    var localAddress: SignalServiceAddress { return SignalServiceAddress(localAci) }

    var otherAci: Aci { return Aci.parseFrom(aciString: "00000000-0000-4000-8000-000000000001")! }
    var otherAddress: SignalServiceAddress { return SignalServiceAddress(otherAci) }

    private func numberOfInteractions(thread: TSThread, tx: SDSAnyReadTransaction) -> UInt {
        var count: UInt = 0
        try! InteractionFinder(threadUniqueId: thread.uniqueId)
            .enumerateInteractionIds(transaction: tx) { _, _ in
                count += 1
            }
        return count
    }

    override func setUp() {
        super.setUp()

        write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )

            self.thread = TSContactThread.getOrCreateThread(
                withContactAddress: self.otherAddress,
                transaction: tx
            )
        }
    }

    func testStoreIncomingMessage() {
        write { tx in
            let timestamp: UInt64 = 42
            let body = "So long, and thanks for all the fish!"

            let newMessage: TSIncomingMessage = TSIncomingMessageBuilder
                .withDefaultValues(
                    thread: thread,
                    timestamp: timestamp,
                    authorAci: otherAci,
                    messageBody: body
                ).build()
            newMessage.anyInsert(transaction: tx)

            guard let fetchedMessage = TSIncomingMessage.anyFetchIncomingMessage(
                uniqueId: newMessage.uniqueId,
                transaction: tx
            ) else {
                XCTFail("Failed to find inserted message!")
                return
            }

            XCTAssertEqual(body, fetchedMessage.body)
            XCTAssertEqual(timestamp, fetchedMessage.timestamp)
            XCTAssertFalse(fetchedMessage.wasRead)
            XCTAssertEqual(thread.uniqueId, fetchedMessage.uniqueThreadId)
        }
    }

    func testMessagesDeletedOnThreadDeletion() {
        write { tx -> Void in
            let body = "So long, and thanks for all the fish!"

            let messages = (0..<10).map { idx -> TSIncomingMessage in
                let newMessage: TSIncomingMessage = TSIncomingMessageBuilder
                    .withDefaultValues(
                        thread: thread,
                        timestamp: UInt64(idx) + 1,
                        authorAci: otherAci,
                        messageBody: body
                    ).build()
                newMessage.anyInsert(transaction: tx)
                return newMessage
            }

            for (idx, message) in messages.enumerated() {
                guard let fetchedMessage = TSIncomingMessage.anyFetchIncomingMessage(
                    uniqueId: message.uniqueId,
                    transaction: tx
                ) else {
                    XCTFail("Failed to find inserted message!")
                    return
                }

                XCTAssertEqual(body, fetchedMessage.body)
                XCTAssertEqual(message.uniqueId, fetchedMessage.uniqueId)
                XCTAssertEqual(UInt64(idx + 1), fetchedMessage.timestamp)
                XCTAssertFalse(fetchedMessage.wasRead)
                XCTAssertEqual(thread.uniqueId, fetchedMessage.uniqueThreadId)
            }

            DependenciesBridge.shared.threadSoftDeleteManager
                .softDelete(threads: [thread], sendDeleteForMeSyncMessage: false, tx: tx.asV2Write)

            for message in messages {
                XCTAssertNil(TSIncomingMessage.anyFetchIncomingMessage(
                    uniqueId: message.uniqueId,
                    transaction: tx
                ))
            }

            XCTAssertEqual(0, numberOfInteractions(thread: thread, tx: tx))
        }
    }

    func testGroupMessagesDeletedOnThreadDeletion() {
        write { tx in
            let body = "So long, and thanks for all the fish!"

            let groupThread = try! GroupManager.createGroupForTests(members: [
                localAddress,
                otherAddress
            ], transaction: tx)

            let messages = (0..<10).map { idx -> TSIncomingMessage in
                let authorIdx = idx % groupThread.groupModel.groupMembers.count
                let authorAddress = groupThread.groupModel.groupMembers[authorIdx]
                let newMessage: TSIncomingMessage = TSIncomingMessageBuilder
                    .withDefaultValues(
                        thread: groupThread,
                        timestamp: UInt64(idx + 1),
                        authorAci: authorAddress.aci!,
                        messageBody: body
                    ).build()
                newMessage.anyInsert(transaction: tx)
                return newMessage
            }

            for (idx, message) in messages.enumerated() {
                guard let fetchedMessage = TSIncomingMessage.anyFetchIncomingMessage(
                    uniqueId: message.uniqueId,
                    transaction: tx
                ) else {
                    XCTFail("Failed to find inserted message!")
                    return
                }

                XCTAssertEqual(body, fetchedMessage.body)
                XCTAssertEqual(message.uniqueId, fetchedMessage.uniqueId)
                XCTAssertEqual(UInt64(idx + 1), fetchedMessage.timestamp)
                XCTAssertFalse(fetchedMessage.wasRead)
                XCTAssertEqual(groupThread.uniqueId, fetchedMessage.uniqueThreadId)
            }

            DependenciesBridge.shared.threadSoftDeleteManager
                .softDelete(threads: [groupThread], sendDeleteForMeSyncMessage: false, tx: tx.asV2Write)

            for message in messages {
                XCTAssertNil(TSIncomingMessage.anyFetchIncomingMessage(
                    uniqueId: message.uniqueId,
                    transaction: tx
                ))
            }

            XCTAssertEqual(0, numberOfInteractions(thread: groupThread, tx: tx))
        }
    }
}
