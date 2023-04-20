//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class SignalAccountFinderTest: SSKBaseTestSwift {
    private lazy var localAddress = CommonGenerator.address()

    override func setUp() {
        super.setUp()
        // Create local account.
        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!, uuid: localAddress.uuid!)
    }

    private func createAccount(serviceId: ServiceId, phoneNumber: E164?) -> SignalAccount {
        write {
            let account = SignalAccount(address: SignalServiceAddress(uuid: serviceId.uuidValue, phoneNumber: phoneNumber?.stringValue))
            account.anyInsert(transaction: $0)
            return account
        }
    }

    func testFetchAccounts() {
        let sid1 = ServiceId(UUID())
        let pn1 = E164("+16505550100")!
        let account1 = createAccount(serviceId: sid1, phoneNumber: pn1)

        let sid2 = ServiceId(UUID())
        let account2 = createAccount(serviceId: sid2, phoneNumber: nil)

        // Nothing prevents us from creating multiple accounts for the same recipient.
        let sid3 = ServiceId(UUID())
        let pn3 = E164("+16505550101")!
        let account3a = createAccount(serviceId: sid3, phoneNumber: pn3)
        _ = createAccount(serviceId: sid3, phoneNumber: pn3)

        // Create an account but don't fetch it.
        let sid4 = ServiceId(UUID())
        _ = createAccount(serviceId: sid4, phoneNumber: nil)

        // Create a ServiceId without an account.
        let sid5 = ServiceId(UUID())

        let addressesToFetch: [SignalServiceAddress] = [
            SignalServiceAddress(sid1),
            SignalServiceAddress(sid2),
            SignalServiceAddress(sid3),
            SignalServiceAddress(sid5),

            // In practice, every SignalAccount has a UUID, and we should be populating
            // the UUID for phone number-only addresses. However, keep this around for
            // historical purposes (for now).
            SignalServiceAddress(uuid: nil, phoneNumber: pn1.stringValue, ignoreCache: true)
        ]

        let expectedAccounts: [SignalAccount?] = [
            account1,
            account2,
            account3a,
            nil,
            account1
        ]

        read { transaction in
            let accountFinder = AnySignalAccountFinder()
            let actualAccounts = accountFinder.signalAccounts(for: addressesToFetch, transaction: transaction)
            XCTAssertEqual(
                actualAccounts.map { $0?.recipientAddress },
                expectedAccounts.map { $0?.recipientAddress }
            )
        }
    }
}
