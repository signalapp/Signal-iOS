//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class ReceiptSenderTest: XCTestCase {
    private var mockDb: MockDB!
    private var receiptSender: ReceiptSender!
    private var signalServiceAddressCacheRef: SignalServiceAddressCache!

    override func setUp() {
        super.setUp()

        mockDb = MockDB()
        signalServiceAddressCacheRef = SignalServiceAddressCache()
        receiptSender = ReceiptSender(
            kvStoreFactory: InMemoryKeyValueStoreFactory(),
            signalServiceAddressCache: signalServiceAddressCacheRef
        )
    }

    func testMergeAddress() {
        // Setup – Store two different receipt sets for an ACI and an e164.
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let aciAddress = SignalServiceAddress(
            serviceId: aci, phoneNumber: nil, cache: signalServiceAddressCacheRef, cachePolicy: .ignoreCache
        )
        let aciReceiptSet = MessageReceiptSet()
        aciReceiptSet.insert(timestamp: 1234, messageUniqueId: "00000000-0000-4000-8000-000000000AAA")

        let e164 = E164("+16505550101")!
        let e164Address = SignalServiceAddress(
            serviceId: nil, phoneNumber: e164.stringValue, cache: signalServiceAddressCacheRef, cachePolicy: .ignoreCache
        )
        let e164ReceiptSet = MessageReceiptSet()
        e164ReceiptSet.insert(timestamp: 5678, messageUniqueId: "00000000-0000-4000-8000-000000000BBB")

        mockDb.write { tx in
            receiptSender.storeReceiptSet(aciReceiptSet, receiptType: .delivery, address: aciAddress, tx: tx)
            receiptSender.storeReceiptSet(e164ReceiptSet, receiptType: .delivery, address: e164Address, tx: tx)
        }

        // Test – Fetch the receipt set for a merged address
        let mergedAddress = SignalServiceAddress(
            serviceId: aci, phoneNumber: e164.stringValue, cache: signalServiceAddressCacheRef, cachePolicy: .ignoreCache
        )
        let mergedReceipt = mockDb.write { tx in
            receiptSender.fetchAndMergeReceiptSet(receiptType: .delivery, address: mergedAddress, tx: tx)
        }

        // Verify – All timestamps exist in the merged receipt
        XCTAssertEqual(mergedReceipt.timestamps, [1234, 5678])
        XCTAssertEqual(mergedReceipt.uniqueIds, ["00000000-0000-4000-8000-000000000AAA", "00000000-0000-4000-8000-000000000BBB"])
    }

    func testMergeAll() {
        // Setup – Store two different receipt sets for a uuid and an e164
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let aciAddress = SignalServiceAddress(
            serviceId: aci, phoneNumber: nil, cache: signalServiceAddressCacheRef, cachePolicy: .ignoreCache
        )
        let aciReceiptSet = MessageReceiptSet()
        aciReceiptSet.insert(timestamp: 1234, messageUniqueId: "00000000-0000-4000-8000-000000000AAA")

        let e164 = E164("+16505550101")!
        let e164Address = SignalServiceAddress(
            serviceId: nil, phoneNumber: e164.stringValue, cache: signalServiceAddressCacheRef, cachePolicy: .ignoreCache
        )
        let e164ReceiptSet = MessageReceiptSet()
        e164ReceiptSet.insert(timestamp: 5678, messageUniqueId: "00000000-0000-4000-8000-000000000BBB")

        mockDb.write { tx in
            receiptSender.storeReceiptSet(aciReceiptSet, receiptType: .delivery, address: aciAddress, tx: tx)
            receiptSender.storeReceiptSet(e164ReceiptSet, receiptType: .delivery, address: e164Address, tx: tx)
        }

        // Test – Mark the merged address as high trust, then fetch all receipt sets
        signalServiceAddressCacheRef.updateRecipient(SignalRecipient(aci: aci, pni: nil, phoneNumber: e164))
        let allReceipts = mockDb.read { tx in receiptSender.fetchAllReceiptSets(receiptType: .delivery, tx: tx) }

        // Verify – The resulting dictionary contains one element. Maps the merged address to the merged receipt
        XCTAssertEqual(allReceipts.count, 1)
        XCTAssertEqual(allReceipts.keys.first!.serviceId, aci)
        XCTAssertEqual(allReceipts.keys.first!.phoneNumber, e164.stringValue)

        XCTAssertEqual(allReceipts.values.first!.timestamps, [1234, 5678])
        XCTAssertEqual(allReceipts.values.first!.uniqueIds, ["00000000-0000-4000-8000-000000000AAA", "00000000-0000-4000-8000-000000000BBB"])
    }
}
