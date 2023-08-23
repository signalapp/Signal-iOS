//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class OWSOutgoingReceiptManagerTests: SSKBaseTestSwift, Dependencies {
    func testMergeAddress() {
        // Setup – Store two different receipt sets for an ACI and an e164.
        let aciAddress = SignalServiceAddress.randomForTesting()
        let aciReceiptSet = MessageReceiptSet()
        aciReceiptSet.insert(timestamp: 1234, messageUniqueId: "00000000-0000-4000-8000-000000000AAA")

        let e164Address = SignalServiceAddress(phoneNumber: "+16505550101")
        let e164ReceiptSet = MessageReceiptSet()
        e164ReceiptSet.insert(timestamp: 5678, messageUniqueId: "00000000-0000-4000-8000-000000000BBB")

        databaseStorage.write { tx in
            outgoingReceiptManager.storeReceiptSet(aciReceiptSet, type: .delivery, address: aciAddress, transaction: tx)
            outgoingReceiptManager.storeReceiptSet(e164ReceiptSet, type: .delivery, address: e164Address, transaction: tx)
        }

        // Test – Fetch the receipt set for a merged address
        let mergedAddress = SignalServiceAddress(serviceId: aciAddress.aci!, phoneNumber: e164Address.phoneNumber!)
        let mergedReceipt = databaseStorage.write { tx in
            outgoingReceiptManager.fetchAndMergeReceiptSet(type: .delivery, address: mergedAddress, transaction: tx)
        }

        // Verify – All timestamps exist in the merged receipt
        XCTAssertEqual(mergedReceipt.timestamps, [1234, 5678])
        XCTAssertEqual(mergedReceipt.uniqueIds, ["00000000-0000-4000-8000-000000000AAA", "00000000-0000-4000-8000-000000000BBB"])
    }

    func testMergeAll() {
        // Setup – Store two different receipt sets for a uuid and an e164
        let aciAddress = SignalServiceAddress.randomForTesting()
        let aciReceiptSet = MessageReceiptSet()
        aciReceiptSet.insert(timestamp: 1234, messageUniqueId: "00000000-0000-4000-8000-000000000AAA")

        let e164Address = SignalServiceAddress(phoneNumber: "+16505550101")
        let e164ReceiptSet = MessageReceiptSet()
        e164ReceiptSet.insert(timestamp: 5678, messageUniqueId: "00000000-0000-4000-8000-000000000BBB")

        databaseStorage.write { tx in
            outgoingReceiptManager.storeReceiptSet(aciReceiptSet, type: .delivery, address: aciAddress, transaction: tx)
            outgoingReceiptManager.storeReceiptSet(e164ReceiptSet, type: .delivery, address: e164Address, transaction: tx)
        }

        // Test – Mark the merged address as high trust, then fetch all receipt sets
        signalServiceAddressCache.updateRecipient(
            SignalRecipient(aci: aciAddress.aci, phoneNumber: e164Address.e164)
        )
        let allReceipts = databaseStorage.read { readTx in
            outgoingReceiptManager.fetchAllReceiptSets(type: .delivery, transaction: readTx)
        }

        // Verify – The resulting dictionary contains one element. Maps the merged address to the merged receipt
        XCTAssertEqual(allReceipts.count, 1)
        XCTAssertEqual(allReceipts.keys.first!.serviceId, aciAddress.aci!)
        XCTAssertEqual(allReceipts.keys.first!.phoneNumber, e164Address.phoneNumber)

        XCTAssertEqual(allReceipts.values.first!.timestamps, [1234, 5678])
        XCTAssertEqual(allReceipts.values.first!.uniqueIds, ["00000000-0000-4000-8000-000000000AAA", "00000000-0000-4000-8000-000000000BBB"])
    }
}
