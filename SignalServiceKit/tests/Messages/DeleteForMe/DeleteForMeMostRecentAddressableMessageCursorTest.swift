//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class DeleteForMeMostRecentAddressableMessageCursorTest: XCTestCase {
    func makeMessage(rowId: Int64) -> TSMessage {
        let message = TSOutgoingMessage(
            outgoingMessageWith: .withDefaultValues(thread: TSThread(uniqueId: .uniqueId())),
            recipientAddressStates: [:]
        )
        message.updateRowId(rowId)
        return message
    }

    func testInterleavedCursorOrdering() throws {
        let incomingMessageCursor = MockInteractionCursor(messages: [
            makeMessage(rowId: 111),
            makeMessage(rowId: 11),
            makeMessage(rowId: 1),
        ])

        let outgoingMessageCursor = MockInteractionCursor(messages: [
            makeMessage(rowId: 12),
            makeMessage(rowId: 10),
            makeMessage(rowId: 9),
            makeMessage(rowId: 8),
        ])

        let addressableMessageCursor = try DeleteForMeMostRecentAddressableMessageCursor(
            addressableMessageCursors: [incomingMessageCursor, outgoingMessageCursor]
        )

        XCTAssertEqual(try! addressableMessageCursor.next()!.sqliteRowId!, 111)
        XCTAssertEqual(try! addressableMessageCursor.next()!.sqliteRowId!, 12)
        XCTAssertEqual(try! addressableMessageCursor.next()!.sqliteRowId!, 11)
        XCTAssertEqual(try! addressableMessageCursor.next()!.sqliteRowId!, 10)
        XCTAssertEqual(try! addressableMessageCursor.next()!.sqliteRowId!, 9)
        XCTAssertEqual(try! addressableMessageCursor.next()!.sqliteRowId!, 8)
        XCTAssertEqual(try! addressableMessageCursor.next()!.sqliteRowId!, 1)
        XCTAssertNil(try! addressableMessageCursor.next())
    }
}

// MARK: -

private class MockInteractionCursor: DeleteForMeAddressableMessageCursor {
    private var messages: [TSMessage]

    init(messages: [TSMessage]) {
        self.messages = messages
    }

    func nextAddressableMessage() throws -> TSMessage? {
        return messages.popFirst()
    }
}

// MARK: -

private extension String {
    static func uniqueId() -> String {
        return UUID().uuidString
    }
}
