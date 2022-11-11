//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class TypingIndicatorMessageTest: SSKBaseTestSwift {
    private func makeThread(transaction: SDSAnyWriteTransaction) -> TSThread {
        TSContactThread.getOrCreateThread(
            withContactAddress: SignalServiceAddress(phoneNumber: "+12223334444"),
            transaction: transaction
        )
    }

    func testIsOnline() throws {
        write { transaction in
            let message = TypingIndicatorMessage(
                thread: makeThread(transaction: transaction),
                action: .started,
                transaction: transaction
            )
            XCTAssertTrue(message.isOnline)
        }
    }

    func testIsUrgent() throws {
        write { transaction in
            let message = TypingIndicatorMessage(
                thread: makeThread(transaction: transaction),
                action: .started,
                transaction: transaction
            )
            XCTAssertFalse(message.isUrgent)
        }
    }
}
