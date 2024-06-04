//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class DeleteForMeMostRecentAddressableMessageCursorTest: XCTestCase {
    func makeInteraction(rowId: Int64) -> TSInteraction {
        let interaction = TSInteraction(
            uniqueId: .uniqueId(),
            thread: TSThread(uniqueId: .uniqueId())
        )
        interaction.updateRowId(rowId)
        return interaction
    }

    func testInterleavedCursorOrdering() throws {
        let incomingMessageCursor = MockInteractionCursor(interactions: [
            makeInteraction(rowId: 111),
            makeInteraction(rowId: 11),
            makeInteraction(rowId: 1),
        ])

        let outgoingMessageCursor = MockInteractionCursor(interactions: [
            makeInteraction(rowId: 12),
            makeInteraction(rowId: 10),
            makeInteraction(rowId: 9),
            makeInteraction(rowId: 8),
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
    private var interactions: [TSInteraction]

    init(interactions: [TSInteraction]) {
        self.interactions = interactions
    }

    func nextAddressableMessage() throws -> TSInteraction? {
        return interactions.popFirst()
    }
}

// MARK: -

private extension String {
    static func uniqueId() -> String {
        return UUID().uuidString
    }
}
