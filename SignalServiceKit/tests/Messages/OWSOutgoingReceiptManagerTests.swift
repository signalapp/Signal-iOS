//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class OWSOutgoingReceiptManagerTests: SSKBaseTestSwift, Dependencies {

    func testMergeAddress() {
        // Setup – Store two different receipt sets for a uuid and an e164
        let uuidAddress = SignalServiceAddress.randomForTesting()
        let uuidReceiptSet = MessageReceiptSet()
        uuidReceiptSet.insert(timestamp: 1234, messageUniqueId: "uuid")

        let e164Address = SignalServiceAddress(phoneNumber: "+1234567890")
        let e164ReceiptSet = MessageReceiptSet()
        e164ReceiptSet.insert(timestamp: 5678, messageUniqueId: "e164")

        databaseStorage.write { writeTx in
            outgoingReceiptManager.storeReceiptSet(uuidReceiptSet, type: .delivery, address: uuidAddress, transaction: writeTx)
            outgoingReceiptManager.storeReceiptSet(e164ReceiptSet, type: .delivery, address: e164Address, transaction: writeTx)
        }

        // Test – Fetch the receipt set for a merged address
        let mergedAddress = SignalServiceAddress(serviceId: uuidAddress.untypedServiceId!, phoneNumber: e164Address.phoneNumber!)
        let mergedReceipt = databaseStorage.write { tx in
            outgoingReceiptManager.fetchAndMergeReceiptSet(type: .delivery, address: mergedAddress, transaction: tx)
        }

        // Verify – All timestamps exist in the merged receipt
        XCTAssertTrue(mergedReceipt.timestamps.contains(1234))
        XCTAssertTrue(mergedReceipt.timestamps.contains(5678))
        XCTAssertTrue(mergedReceipt.uniqueIds.contains("uuid"))
        XCTAssertTrue(mergedReceipt.uniqueIds.contains("e164"))
    }

    func testMergeAll() {
        // Setup – Store two different receipt sets for a uuid and an e164
        let uuidAddress = SignalServiceAddress.randomForTesting()
        let uuidReceiptSet = MessageReceiptSet()
        uuidReceiptSet.insert(timestamp: 1234, messageUniqueId: "uuid")

        let e164Address = SignalServiceAddress(phoneNumber: "+1234567890")
        let e164ReceiptSet = MessageReceiptSet()
        e164ReceiptSet.insert(timestamp: 5678, messageUniqueId: "e164")

        databaseStorage.write { writeTx in
            outgoingReceiptManager.storeReceiptSet(uuidReceiptSet, type: .delivery, address: uuidAddress, transaction: writeTx)
            outgoingReceiptManager.storeReceiptSet(e164ReceiptSet, type: .delivery, address: e164Address, transaction: writeTx)
        }

        // Test – Mark the merged address as high trust, then fetch all receipt sets
        signalServiceAddressCache.updateRecipient(
            SignalRecipient(serviceId: uuidAddress.untypedServiceId, phoneNumber: e164Address.e164)
        )
        let allReceipts = databaseStorage.read { readTx in
            outgoingReceiptManager.fetchAllReceiptSets(type: .delivery, transaction: readTx)
        }

        // Verify – The resulting dictionary contains one element. Maps the merged address to the merged receipt
        XCTAssertEqual(allReceipts.count, 1)
        XCTAssertEqual(allReceipts.keys.first?.untypedServiceId, uuidAddress.untypedServiceId)
        XCTAssertEqual(allReceipts.keys.first?.phoneNumber, e164Address.phoneNumber)

        XCTAssertTrue(allReceipts.values.first!.timestamps.contains(1234))
        XCTAssertTrue(allReceipts.values.first!.timestamps.contains(5678))
        XCTAssertTrue(allReceipts.values.first!.uniqueIds.contains("uuid"))
        XCTAssertTrue(allReceipts.values.first!.uniqueIds.contains("e164"))
    }

}
