//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class ViewOnceMessagesTest: SSKBaseTestSwift {

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    // MARK: -

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: "+13334445555", uuid: UUID())
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: -

    func test_expiration() {

        let messageCount = { () -> Int in
            return self.databaseStorage.read { transaction in
                return TSInteraction.anyFetchAll(transaction: transaction).count
            }
        }
        let latestCopy = { (message: TSMessage) -> TSMessage in
            let uniqueId = message.uniqueId
            return self.databaseStorage.read { transaction in
                return TSMessage.anyFetch(uniqueId: uniqueId, transaction: transaction) as! TSMessage
            }
        }

        // Factory 1 builds messages that are not view-once messages.
        let factory1 = IncomingMessageFactory()
        factory1.isViewOnceMessageBuilder = {
            return false
        }

        self.write { transaction in
            _ = factory1.create(transaction: transaction)
        }

        XCTAssertEqual(1, messageCount())

        // Factory 2 builds view-once messages.
        let factory2 = IncomingMessageFactory()
        factory2.isViewOnceMessageBuilder = {
            return true
        }

        var viewOnceMessage: TSMessage?
        self.write { transaction in
            viewOnceMessage = factory2.create(transaction: transaction)
        }

        XCTAssertEqual(2, messageCount())

        guard let message = viewOnceMessage else {
            XCTFail("Missing message.")
            return
        }

        XCTAssertTrue(message.isViewOnceMessage)
        XCTAssertFalse(message.isViewOnceComplete)

        XCTAssertTrue(latestCopy(message).isViewOnceMessage)
        XCTAssertFalse(latestCopy(message).isViewOnceComplete)

        self.write { transaction in
            ViewOnceMessages.markAsComplete(message: message,
                                            sendSyncMessages: false,
                                            transaction: transaction)
        }

        XCTAssertTrue(message.isViewOnceMessage)
        XCTAssertTrue(message.isViewOnceComplete)

        XCTAssertTrue(latestCopy(message).isViewOnceMessage)
        XCTAssertTrue(latestCopy(message).isViewOnceComplete)

        XCTAssertEqual(2, messageCount())
    }
}
