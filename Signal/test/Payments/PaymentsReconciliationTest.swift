//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
@testable import SignalMessaging
@testable import SignalUI
@testable import Signal
@testable import MobileCoin

private struct MockTransactionHistoryItem: MCTransactionHistoryItem {
    let amountPicoMob: UInt64
    let txoPublicKey: Data
    let keyImage: Data
    let receivedBlock: MobileCoin.BlockMetadata
    let spentBlock: MobileCoin.BlockMetadata?
}

// MARK: -

private struct MockTransactionHistory: MCTransactionHistory {
    let items: [MCTransactionHistoryItem]
    let blockCount: UInt64
}

// MARK: -

private extension PaymentsDatabaseState {
    var incomingIdentifiedUnverifiedCount: Int {
        allPaymentModels.filter { paymentModel in
            paymentModel.isIncoming && paymentModel.isIdentifiedPayment && !paymentModel.isVerified && !paymentModel.isFailed
        }.count
    }

    var incomingIdentifiedVerifiedCount: Int {
        allPaymentModels.filter { paymentModel in
            paymentModel.isIncoming && paymentModel.isIdentifiedPayment && paymentModel.isVerified && !paymentModel.isFailed
        }.count
    }

    var incomingUnidentifiedCount: Int {
        allPaymentModels.filter { paymentModel in
            paymentModel.isIncoming && paymentModel.isUnidentified
        }.count
    }
}

// MARK: -

class PaymentsReconciliationTest: SignalBaseTest {

    // MARK: -

    override func setUp() {
        super.setUp()

        SSKEnvironment.shared.setPaymentsHelperForUnitTests(PaymentsHelperImpl())
        SUIEnvironment.shared.paymentsRef = PaymentsImpl()
    }

    func test_reconcileAccountActivity_empty() {
        do {
            try databaseStorage.read { (transaction) -> Void in
                let transactionHistory = Self.buildTransactionHistory_empty()
                let databaseState = Self.buildPaymentsDatabaseState_empty()
                try PaymentsReconciliation.reconcile(transactionHistory: transactionHistory,
                                                     databaseState: databaseState,
                                                     transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            XCTFail("Error: \(error)")
        }
    }

    private static func buildTransactionHistory_empty() -> MCTransactionHistory {
        let items = [MockTransactionHistoryItem]()
        let blockCount: UInt64 = 5
        return MockTransactionHistory(items: items,
                                      blockCount: blockCount)
    }

    private static func buildPaymentsDatabaseState_empty() -> PaymentsDatabaseState {
        PaymentsDatabaseState()
    }

    func test_reconcileAccountActivity_unsavedChanges() {
        do {
            try databaseStorage.read { (transaction) -> Void in
                let buildItem2a_incomingUnspent = Self.buildItem2a_incomingUnspent()
                let transactionHistory = MockTransactionHistory(items: [
                    buildItem2a_incomingUnspent
                ],
                blockCount: 3)
                let databaseState = Self.buildPaymentsDatabaseState_empty()
                try PaymentsReconciliation.reconcile(transactionHistory: transactionHistory,
                                                     databaseState: databaseState,
                                                     transaction: transaction)
            }
            XCTFail("Missing error.")
        } catch {
            if case PaymentsReconciliation.ReconciliationError.unsavedChanges = error {
                // Do nothing.
            } else {
                owsFailDebug("Error: \(error)")
                XCTFail("Error: \(error)")
            }
        }
    }

    func test_reconcileAccountActivity_fillIn1() {
        do {
            try databaseStorage.write { (transaction) -> Void in

                let buildItem2a_incomingUnspent = Self.buildItem2a_incomingUnspent()
                let transactionHistory = MockTransactionHistory(items: [
                    buildItem2a_incomingUnspent
                ],
                blockCount: 3)

                // Reconciliation 1

                do {
                    var databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)

                    XCTAssertEqual(databaseState.allPaymentModels.count, 0)
                    XCTAssertEqual(databaseState.incomingAnyMap.count, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedUnverifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedVerifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingUnidentifiedCount, 0)
                    XCTAssertEqual(databaseState.spentImageKeyMap.count, 0)
                    XCTAssertEqual(databaseState.outputPublicKeyMap.count, 0)

                    // This reconciliation pass should create an "unidentified incoming" payment model.
                    try PaymentsReconciliation.reconcile(transactionHistory: transactionHistory,
                                                         databaseState: databaseState,
                                                         transaction: transaction)
                    databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)

                    XCTAssertEqual(databaseState.allPaymentModels.count, 1)
                    XCTAssertEqual(databaseState.incomingAnyMap.count, 1)
                    XCTAssertEqual(databaseState.incomingIdentifiedUnverifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedVerifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingUnidentifiedCount, 1)
                    XCTAssertEqual(databaseState.spentImageKeyMap.count, 0)
                    XCTAssertEqual(databaseState.outputPublicKeyMap.count, 0)

                    let paymentModels = databaseState.incomingAnyMap[buildItem2a_incomingUnspent.txoPublicKey]
                    guard paymentModels.count == 1,
                          let paymentModel = paymentModels.first else {
                        XCTFail("Unexpected paymentModel count: \(paymentModels.count)")
                        return
                    }

                    let item = buildItem2a_incomingUnspent
                    XCTAssertEqual(TSPaymentType.incomingUnidentified, paymentModel.paymentType)
                    XCTAssertEqual(TSPaymentState.incomingComplete, paymentModel.paymentState)
                    XCTAssertEqual(TSPaymentFailure.none, paymentModel.paymentFailure)
                    XCTAssertEqual(TSPaymentCurrency.mobileCoin, paymentModel.paymentAmount?.currency)
                    XCTAssertEqual(item.amountPicoMob, paymentModel.paymentAmount?.picoMob)
                    XCTAssertEqual([item.txoPublicKey], paymentModel.mobileCoin?.incomingTransactionPublicKeys)
                    XCTAssertTrue(item.receivedBlock.index == paymentModel.mobileCoin?.ledgerBlockIndex)
                    XCTAssertTrue(item.receivedBlock.timestamp?.ows_millisecondsSince1970 == paymentModel.mobileCoin?.ledgerBlockTimestamp)
                    XCTAssertNil(paymentModel.addressUuidString)
                    XCTAssertNil(paymentModel.memoMessage)
                    XCTAssertEqual(true, paymentModel.isUnread)
                    XCTAssertNil(paymentModel.mobileCoin?.recipientPublicAddressData)
                    XCTAssertNil(paymentModel.mobileCoin?.transactionData)
                    XCTAssertNil(paymentModel.mobileCoin?.receiptData)
                    XCTAssertNil(paymentModel.mobileCoin?.spentKeyImages)
                    XCTAssertNil(paymentModel.mobileCoin?.outputPublicKeys)
                    XCTAssertNil(paymentModel.mobileCoin?.feeAmount)
                }

                // Reconciliation 2

                do {
                    // This reconciliation pass should have no effect.
                    var databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)
                    try PaymentsReconciliation.reconcile(transactionHistory: transactionHistory,
                                                         databaseState: databaseState,
                                                         transaction: transaction)
                    databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)

                    XCTAssertEqual(databaseState.allPaymentModels.count, 1)
                    XCTAssertEqual(databaseState.incomingAnyMap.count, 1)
                    XCTAssertEqual(databaseState.incomingIdentifiedUnverifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedVerifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingUnidentifiedCount, 1)
                    XCTAssertEqual(databaseState.spentImageKeyMap.count, 0)
                    XCTAssertEqual(databaseState.outputPublicKeyMap.count, 0)
                }
            }
        } catch {
            owsFailDebug("Error: \(error)")
            XCTFail("Error: \(error)")
        }
    }

    func test_reconcileAccountActivity_unspentThenSpent() {
        do {
            try databaseStorage.write { (transaction) -> Void in

                // Reconciliation 1

                do {
                    let buildItem2a_incomingUnspent = Self.buildItem2a_incomingUnspent()
                    let transactionHistory2 = MockTransactionHistory(items: [
                        buildItem2a_incomingUnspent
                    ],
                    blockCount: 2)

                    var databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)

                    XCTAssertEqual(databaseState.allPaymentModels.count, 0)
                    XCTAssertEqual(databaseState.incomingAnyMap.count, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedUnverifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedVerifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingUnidentifiedCount, 0)
                    XCTAssertEqual(databaseState.spentImageKeyMap.count, 0)
                    XCTAssertEqual(databaseState.outputPublicKeyMap.count, 0)

                    // This reconciliation pass should create an "unidentified incoming" payment model.
                    try PaymentsReconciliation.reconcile(transactionHistory: transactionHistory2,
                                                         databaseState: databaseState,
                                                         transaction: transaction)
                    databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)

                    XCTAssertEqual(databaseState.allPaymentModels.count, 1)
                    XCTAssertEqual(databaseState.incomingAnyMap.count, 1)
                    XCTAssertEqual(databaseState.incomingIdentifiedUnverifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedVerifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingUnidentifiedCount, 1)
                    XCTAssertEqual(databaseState.spentImageKeyMap.count, 0)
                    XCTAssertEqual(databaseState.outputPublicKeyMap.count, 0)

                    let paymentModels = databaseState.incomingAnyMap[buildItem2a_incomingUnspent.txoPublicKey]
                    guard paymentModels.count == 1,
                          let paymentModel = paymentModels.first else {
                        XCTFail("Unexpected paymentModel count: \(paymentModels.count)")
                        return
                    }

                    let item = buildItem2a_incomingUnspent
                    XCTAssertEqual(TSPaymentType.incomingUnidentified, paymentModel.paymentType)
                    XCTAssertEqual(TSPaymentState.incomingComplete, paymentModel.paymentState)
                    XCTAssertEqual(TSPaymentFailure.none, paymentModel.paymentFailure)
                    XCTAssertEqual(TSPaymentCurrency.mobileCoin, paymentModel.paymentAmount?.currency)
                    XCTAssertEqual(item.amountPicoMob, paymentModel.paymentAmount?.picoMob)
                    XCTAssertEqual([item.txoPublicKey], paymentModel.mobileCoin?.incomingTransactionPublicKeys)
                    XCTAssertTrue(item.receivedBlock.index == paymentModel.mobileCoin?.ledgerBlockIndex)
                    XCTAssertTrue(item.receivedBlock.timestamp?.ows_millisecondsSince1970 == paymentModel.mobileCoin?.ledgerBlockTimestamp)
                    XCTAssertNil(paymentModel.addressUuidString)
                    XCTAssertNil(paymentModel.memoMessage)
                    XCTAssertEqual(true, paymentModel.isUnread)
                    XCTAssertNil(paymentModel.mobileCoin?.recipientPublicAddressData)
                    XCTAssertNil(paymentModel.mobileCoin?.transactionData)
                    XCTAssertNil(paymentModel.mobileCoin?.receiptData)
                    XCTAssertNil(paymentModel.mobileCoin?.spentKeyImages)
                    XCTAssertNil(paymentModel.mobileCoin?.outputPublicKeys)
                    XCTAssertNil(paymentModel.mobileCoin?.feeAmount)
                }

                // Reconciliation 2

                do {
                    let buildItem2a_incomingSpentIn4 = Self.buildItem2a_incomingSpentIn4()
                    let transactionHistory4 = MockTransactionHistory(items: [
                        buildItem2a_incomingSpentIn4
                    ],
                    blockCount: 4)

                    // This reconciliation pass should create an "unidentified outgoing" payment model.
                    var databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)
                    try PaymentsReconciliation.reconcile(transactionHistory: transactionHistory4,
                                                         databaseState: databaseState,
                                                         transaction: transaction)
                    databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)

                    XCTAssertEqual(databaseState.allPaymentModels.count, 2)
                    XCTAssertEqual(databaseState.incomingAnyMap.count, 1)
                    XCTAssertEqual(databaseState.incomingIdentifiedUnverifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedVerifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingUnidentifiedCount, 1)
                    XCTAssertEqual(databaseState.spentImageKeyMap.count, 1)
                    XCTAssertEqual(databaseState.outputPublicKeyMap.count, 0)

                    if let paymentModel = databaseState.spentImageKeyMap[buildItem2a_incomingSpentIn4.keyImage] {
                        let item = buildItem2a_incomingSpentIn4
                        XCTAssertEqual(TSPaymentType.outgoingUnidentified, paymentModel.paymentType)
                        XCTAssertEqual(TSPaymentState.outgoingComplete, paymentModel.paymentState)
                        XCTAssertEqual(TSPaymentFailure.none, paymentModel.paymentFailure)
                        XCTAssertEqual(TSPaymentCurrency.mobileCoin, paymentModel.paymentAmount?.currency)
                        XCTAssertEqual(item.amountPicoMob, paymentModel.paymentAmount?.picoMob)
                        XCTAssertNil(paymentModel.mobileCoin?.incomingTransactionPublicKeys?.nilIfEmpty)
                        XCTAssertTrue(item.spentBlock?.index == paymentModel.mobileCoin?.ledgerBlockIndex)
                        XCTAssertTrue(item.spentBlock?.timestamp?.ows_millisecondsSince1970 == paymentModel.mobileCoin?.ledgerBlockTimestamp)
                        XCTAssertNil(paymentModel.addressUuidString)
                        XCTAssertNil(paymentModel.memoMessage)
                        XCTAssertEqual(true, paymentModel.isUnread)
                        XCTAssertNil(paymentModel.mobileCoin?.recipientPublicAddressData)
                        XCTAssertNil(paymentModel.mobileCoin?.transactionData)
                        XCTAssertNil(paymentModel.mobileCoin?.receiptData)
                        XCTAssertEqual([item.keyImage], paymentModel.mobileCoin?.spentKeyImages)
                        XCTAssertNil(paymentModel.mobileCoin?.outputPublicKeys?.nilIfEmpty)
                        XCTAssertNil(paymentModel.mobileCoin?.feeAmount)
                    } else {
                        XCTFail("Missing paymentModel for item2a.txoPublicKey")
                    }
                }

                // Reconciliation 3

                do {
                    let buildItem2a_incomingSpentIn4 = Self.buildItem2a_incomingSpentIn4()
                    let transactionHistory4 = MockTransactionHistory(items: [
                        buildItem2a_incomingSpentIn4
                    ],
                    blockCount: 4)

                    // This reconciliation pass should have no effect.
                    var databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)
                    try PaymentsReconciliation.reconcile(transactionHistory: transactionHistory4,
                                                         databaseState: databaseState,
                                                         transaction: transaction)
                    databaseState = PaymentsReconciliation.buildPaymentsDatabaseState(transaction: transaction)

                    XCTAssertEqual(databaseState.allPaymentModels.count, 2)
                    XCTAssertEqual(databaseState.incomingAnyMap.count, 1)
                    XCTAssertEqual(databaseState.incomingIdentifiedUnverifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingIdentifiedVerifiedCount, 0)
                    XCTAssertEqual(databaseState.incomingUnidentifiedCount, 1)
                    XCTAssertEqual(databaseState.spentImageKeyMap.count, 1)
                    XCTAssertEqual(databaseState.outputPublicKeyMap.count, 0)
                }
            }
        } catch {
            owsFailDebug("Error: \(error)")
            XCTFail("Error: \(error)")
        }
    }

    private static let date2 = NSDate.ows_date(withMillisecondsSince1970: 1000 + 2)
    private static let block2 = MobileCoin.BlockMetadata(index: 2, timestamp: date2)
    private static let block4 = MobileCoin.BlockMetadata(index: 2, timestamp: date2)

    private static func randomTxoPublicKey() -> Data {
        Randomness.generateRandomBytes(32)
    }

    private static func randomKeyImage() -> Data {
        Randomness.generateRandomBytes(32)
    }

    private static let txoPublicKey2a = randomTxoPublicKey()
    private static let keyImage2a = randomKeyImage()

    private static func buildItem2a_incomingUnspent() -> MCTransactionHistoryItem {
        MockTransactionHistoryItem(amountPicoMob: 1002,
                                   txoPublicKey: txoPublicKey2a,
                                   keyImage: keyImage2a,
                                   receivedBlock: block2,
                                   spentBlock: nil)
    }

    private static func buildItem2a_incomingSpentIn4() -> MCTransactionHistoryItem {
        MockTransactionHistoryItem(amountPicoMob: 1002,
                                   txoPublicKey: txoPublicKey2a,
                                   keyImage: keyImage2a,
                                   receivedBlock: block2,
                                   spentBlock: block4)
    }
}
