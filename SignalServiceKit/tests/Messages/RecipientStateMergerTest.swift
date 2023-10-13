//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class RecipientStateMergerTest: XCTestCase {
    private var mockDB: MockDB!
    private var _signalServiceAddressCache: SignalServiceAddressCache!
    private var recipientStateMerger: RecipientStateMerger!
    private var recipientStore: MockRecipientDataStore!

    override func setUp() {
        super.setUp()

        mockDB = MockDB()
        _signalServiceAddressCache = SignalServiceAddressCache()
        recipientStore = MockRecipientDataStore()
        recipientStateMerger = RecipientStateMerger(
            recipientStore: recipientStore,
            signalServiceAddressCache: _signalServiceAddressCache
        )
    }

    func testNormalize() {
        let aci1 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let pni1 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")
        let aci2 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a2")
        let pni3 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b3")
        let aci4 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a4")
        let pni4 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b4")

        mockDB.write { tx in
            recipientStore.insertRecipient(SignalRecipient(aci: aci1, pni: pni1, phoneNumber: nil), transaction: tx)
            recipientStore.insertRecipient(SignalRecipient(aci: aci4, pni: pni4, phoneNumber: nil), transaction: tx)
        }

        var recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]? = [
            makeAddress(pni1): makeState(deliveryTimestamp: 1),
            makeAddress(aci2): makeState(deliveryTimestamp: 2),
            makeAddress(pni3): makeState(deliveryTimestamp: 3),
            makeAddress(aci4): makeState(deliveryTimestamp: 4),
            makeAddress(pni4): makeState(deliveryTimestamp: 5)
        ]
        mockDB.read { tx in
            recipientStateMerger.normalize(&recipientStates, tx: tx)
        }

        XCTAssertEqual(recipientStates!.removeValue(forKey: makeAddress(aci1))?.deliveryTimestamp?.uint64Value, 1)
        XCTAssertEqual(recipientStates!.removeValue(forKey: makeAddress(aci2))?.deliveryTimestamp?.uint64Value, 2)
        XCTAssertEqual(recipientStates!.removeValue(forKey: makeAddress(pni3))?.deliveryTimestamp?.uint64Value, 3)
        XCTAssertEqual(recipientStates!.removeValue(forKey: makeAddress(aci4))?.deliveryTimestamp?.uint64Value, 4)
        XCTAssertEqual(recipientStates, [:])
    }

    private func makeAddress(_ serviceId: ServiceId) -> SignalServiceAddress {
        return SignalServiceAddress(
            serviceId: serviceId,
            phoneNumber: nil,
            cache: _signalServiceAddressCache,
            cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
        )
    }

    private func makeState(deliveryTimestamp: UInt64) -> TSOutgoingMessageRecipientState {
        let result = TSOutgoingMessageRecipientState()!
        result.deliveryTimestamp = NSNumber(value: deliveryTimestamp)
        return result
    }
}
