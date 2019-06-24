//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class PerMessageExpirationTest: SSKBaseTestSwift {

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: -

    override func setUp() {
        super.setUp()

        tsAccountManager.storeLocalNumber("+13334445555", uuid: UUID())
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: -

    func test_expiration() {

        let messageCount = { () -> Int in
            return self.databaseStorage.readReturningResult { transaction in
                return TSInteraction.anyFetchAll(transaction: transaction).count
            }
        }
        let latestCopy = { (message: TSMessage) -> TSMessage in
            let uniqueId = message.uniqueId!
            return self.databaseStorage.readReturningResult { transaction in
                return TSMessage.anyFetch(uniqueId: uniqueId, transaction: transaction) as! TSMessage
            }
        }

        // Factory 1 builds messages without per-message expiration.
        let factory1 = IncomingMessageFactory()
        factory1.perMessageExpirationDurationSecondsBuilder = {
            return 0
        }

        self.write { transaction in
            _ = factory1.create(transaction: transaction)
        }

        XCTAssertEqual(1, messageCount())

        // Factory 2 builds messages with per-message expiration.
        let expirationSeconds: UInt32 = 1
        let factory2 = IncomingMessageFactory()
        factory2.perMessageExpirationDurationSecondsBuilder = {
            return expirationSeconds
        }

        var disappearingMessage: TSMessage?
        self.write { transaction in
            disappearingMessage = factory2.create(transaction: transaction)
        }

        XCTAssertEqual(2, messageCount())

        guard let message = disappearingMessage else {
            XCTFail("Missing message.")
            return
        }

        XCTAssertTrue(message.hasPerMessageExpiration)
        XCTAssertFalse(message.hasPerMessageExpirationStarted)
        XCTAssertFalse(message.perMessageExpirationHasExpired)

        XCTAssertTrue(latestCopy(message).hasPerMessageExpiration)
        XCTAssertFalse(latestCopy(message).hasPerMessageExpirationStarted)
        XCTAssertFalse(latestCopy(message).perMessageExpirationHasExpired)

        self.write { transaction in
            PerMessageExpiration.startPerMessageExpiration(forMessage: message,
                                                           transaction: transaction)
        }

        XCTAssertTrue(message.hasPerMessageExpiration)
        XCTAssertTrue(message.hasPerMessageExpirationStarted)
        XCTAssertFalse(message.perMessageExpirationHasExpired)

        XCTAssertTrue(latestCopy(message).hasPerMessageExpiration)
        XCTAssertTrue(latestCopy(message).hasPerMessageExpirationStarted)
        XCTAssertFalse(latestCopy(message).perMessageExpirationHasExpired)

        XCTAssertEqual(2, messageCount())

        Logger.verbose("Sleeping for \(expirationSeconds + 1)")
        // Sleep for a little extra time to avoid races.
        sleep(expirationSeconds + 1)
        Logger.verbose("Slept for \(expirationSeconds + 1)")

        XCTAssertTrue(latestCopy(message).hasPerMessageExpiration)
        XCTAssertTrue(latestCopy(message).hasPerMessageExpirationStarted)
        XCTAssertTrue(latestCopy(message).perMessageExpirationHasExpired)

        XCTAssertEqual(2, messageCount())
    }
}
