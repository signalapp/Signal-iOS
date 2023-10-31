//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class RecipientDatabaseTableTest: XCTestCase {
    func testFetchServiceIdForContactThread() {
        let s = MockRecipientDatabaseTable()
        let aci1 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let aci2 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a2")
        let phoneNumber1 = E164("+16505550101")!
        let phoneNumber2 = E164("+16505550102")!
        let pni1 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")
        let pni2 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2")

        MockDB().write { tx in
            s.insertRecipient(SignalRecipient(aci: aci1, pni: pni1, phoneNumber: phoneNumber1), transaction: tx)
        }

        func fetchServiceId(_ serviceId: ServiceId?, _ phoneNumber: E164?) -> ServiceId? {
            return MockDB().read { tx in s.fetchServiceId(for: makeThread(serviceId, phoneNumber), tx: tx) }
        }

        XCTAssertEqual(fetchServiceId(aci2, phoneNumber1), aci2)
        XCTAssertEqual(fetchServiceId(pni1, phoneNumber2), nil)
        XCTAssertEqual(fetchServiceId(pni1, phoneNumber1), aci1)
        XCTAssertEqual(fetchServiceId(pni1, nil), aci1)
        XCTAssertEqual(fetchServiceId(pni2, nil), pni2)
    }

    private func makeThread(_ serviceId: ServiceId?, _ phoneNumber: E164?) -> TSContactThread {
        return TSContactThread(contactAddress: SignalServiceAddress(
            serviceId: serviceId,
            phoneNumber: phoneNumber?.stringValue,
            cache: SignalServiceAddressCache(),
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        ))
    }
}
