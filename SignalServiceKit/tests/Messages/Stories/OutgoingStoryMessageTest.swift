//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OutgoingStoryMessageTest: SSKBaseTestSwift {
    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+12225550101", uuid: UUID(), pni: UUID())
    }

    func testIsUrgent() throws {
        write { transaction in
            let outgoingStoryMessage = OutgoingStoryMessage.createUnsentMessage(
                attachment: TSAttachmentStream(
                    contentType: OWSMimeTypeImagePng,
                    byteCount: 1234,
                    sourceFilename: "test.png",
                    caption: nil,
                    albumMessageId: nil
                ),
                thread: TSContactThread.getOrCreateThread(
                    withContactAddress: SignalServiceAddress(phoneNumber: "+12225550102"),
                    transaction: transaction
                ),
                transaction: transaction
            )
            XCTAssertFalse(outgoingStoryMessage.isUrgent)
        }
    }
}
