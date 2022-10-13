//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

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
        OWSIdentityManager.shared.saveRemoteIdentity(
            Data(count: Int(kStoredIdentityKeyLength)),
            address: contactThread.contactAddress
        )

        XCTAssert(contactThread.hasSafetyNumbers())
    }
}
