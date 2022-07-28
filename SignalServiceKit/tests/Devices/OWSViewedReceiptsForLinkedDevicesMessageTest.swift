//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OWSViewedReceiptsForLinkedDevicesMessageTest: SSKBaseTestSwift {
    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+12225550101", uuid: UUID(), pni: UUID())
    }

    private func getViewedReceiptsForLinkedDevicesMessage() -> OWSViewedReceiptsForLinkedDevicesMessage {
        write { transaction in
            OWSViewedReceiptsForLinkedDevicesMessage(
                thread: TSContactThread.getOrCreateThread(
                    withContactAddress: SignalServiceAddress(phoneNumber: "+12225550102"),
                    transaction: transaction
                ),
                viewedReceipts: [],
                transaction: transaction
            )
        }
    }

    func testIsUrgent() throws {
        XCTAssertFalse(getViewedReceiptsForLinkedDevicesMessage().isUrgent)
    }
}
