//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class TSContactThreadTest: SSKBaseTestSwift {
    private func contactThread() -> TSContactThread {
        TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(phoneNumber: "+12225550123"))
    }

    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+13335550123", uuid: UUID())
    }

    func testHasSafetyNumbersWithoutRemoteIdentity() {
        XCTAssertFalse(contactThread().hasSafetyNumbers())
    }

    func testHasSafetyNumbersWithRemoteIdentity() {
        let contactThread = self.contactThread()

        let identityManager = DependenciesBridge.shared.identityManager
        databaseStorage.write { tx in
            identityManager.saveIdentityKey(Data(count: 32), for: contactThread.contactAddress, tx: tx.asV2Write)
        }

        XCTAssert(contactThread.hasSafetyNumbers())
    }

    func testCanSendChatMessagesToThread() {
        XCTAssertTrue(contactThread().canSendChatMessagesToThread())
    }
}
