//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class SignalAccountFinderTest: SSKBaseTestSwift {
    override func setUp() {
        super.setUp()
        // Create local account.
        tsAccountManager.registerForTests(localIdentifiers: .forUnitTests)
    }

    private func createAccount(serviceId: ServiceId, phoneNumber: E164?) -> SignalAccount {
        write {
            let account = SignalAccount(address: SignalServiceAddress(serviceId: serviceId, phoneNumber: phoneNumber?.stringValue))
            account.anyInsert(transaction: $0)
            return account
        }
    }

    func testFetchAccounts() {
        let aci1 = Aci.randomForTesting()
        let pn1 = E164("+16505550100")!
        let account1 = createAccount(serviceId: aci1, phoneNumber: pn1)

        let aci2 = Aci.randomForTesting()
        let account2 = createAccount(serviceId: aci2, phoneNumber: nil)

        // Nothing prevents us from creating multiple accounts for the same recipient.
        let aci3 = Aci.randomForTesting()
        let pn3 = E164("+16505550101")!
        let account3 = createAccount(serviceId: aci3, phoneNumber: pn3)
        _ = createAccount(serviceId: aci3, phoneNumber: pn3)

        // Create an account but don't fetch it.
        let aci4 = Aci.randomForTesting()
        _ = createAccount(serviceId: aci4, phoneNumber: nil)

        // Create a ServiceId without an account.
        let aci5 = Aci.randomForTesting()

        // Create an account for a PNI-only contact
        let pni6 = Pni.randomForTesting()
        let pn6 = E164("+17735550155")!
        let account6 = createAccount(serviceId: pni6, phoneNumber: pn6)

        let addressesToFetch: [SignalServiceAddress] = [
            SignalServiceAddress(aci1),
            SignalServiceAddress(aci2),
            SignalServiceAddress(aci3),
            SignalServiceAddress(aci5),
            SignalServiceAddress(pni6),

            // In practice, every SignalAccount has a UUID, and we should be populating
            // the UUID for phone number-only addresses. However, keep this around for
            // historical purposes (for now).
            SignalServiceAddress(serviceId: nil as ServiceId?, phoneNumber: pn1.stringValue, ignoreCache: true)
        ]

        let expectedAccounts: [SignalAccount?] = [
            account1,
            account2,
            account3,
            nil,
            account6,
            account1
        ]

        read { tx in
            let accountFinder = SignalAccountFinder()
            let actualAccounts = accountFinder.signalAccounts(for: addressesToFetch, tx: tx)
            XCTAssertEqual(
                actualAccounts.map { $0?.recipientAddress },
                expectedAccounts.map { $0?.recipientAddress }
            )
        }
    }
}
