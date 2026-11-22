//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class InteractionFinderTest: SSKBaseTest {

    func testBuildUniqueIdCursorForConversationView() {
        let thread = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334444"))
        var messages = [TSOutgoingMessage]()
        self.write { transaction in
            thread.anyInsert(transaction: transaction)
            for idx in 1...5 {
                let message = TSOutgoingMessage(in: thread, messageBody: "message \(idx)")
                message.anyInsert(transaction: transaction)
                messages.append(message)
            }
        }

        let uniqueIds = messages.map { $0.uniqueId }
        let rowIds = messages.map { $0.sqliteRowId! }

        func drain(_ filter: InteractionFinder.RowIdFilter, tx: DBReadTransaction) -> [String] {
            var cursor = InteractionFinder(threadUniqueId: thread.uniqueId)
                .buildUniqueIdCursorForConversationView(rowIdFilter: filter, tx: tx)
            var results = [String]()
            while let uniqueId = cursor.next() {
                results.append(uniqueId)
            }
            return results
        }

        self.read { transaction in
            // These filters must yield uniqueIds newest first.
            XCTAssertEqual(drain(.newest, tx: transaction), Array(uniqueIds.reversed()))
            XCTAssertEqual(drain(.atOrBefore(rowIds[2]), tx: transaction), [uniqueIds[2], uniqueIds[1], uniqueIds[0]])
            XCTAssertEqual(drain(.before(rowIds[2]), tx: transaction), [uniqueIds[1], uniqueIds[0]])
            // These filters must yield uniqueIds oldest first.
            XCTAssertEqual(drain(.after(rowIds[2]), tx: transaction), [uniqueIds[3], uniqueIds[4]])
            XCTAssertEqual(drain(.range(rowIds[1]...rowIds[3]), tx: transaction), [uniqueIds[1], uniqueIds[2], uniqueIds[3]])
        }
    }
}

// MARK: -

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, messageBody: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody(messageBody),
        )
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
