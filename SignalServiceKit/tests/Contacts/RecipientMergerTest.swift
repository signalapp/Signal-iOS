//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit
import XCTest

@testable import SignalServiceKit

private class MockRecipientDataStore: RecipientDataStore {
    var nextRowId = 1
    var recipientTable: [Int: SignalRecipient] = [:]

    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient? {
        return recipientTable.values.first(where: { $0.aci == serviceId || $0.pni == serviceId })?.copyRecipient() ?? nil
    }

    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient? {
        return recipientTable.values.first(where: { $0.phoneNumber == phoneNumber })?.copyRecipient() ?? nil
    }

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        precondition(rowId(for: signalRecipient) == nil)
        recipientTable[nextRowId] = signalRecipient.copyRecipient()
        nextRowId += 1
    }

    func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        let rowId = rowId(for: signalRecipient)!
        recipientTable[rowId] = signalRecipient.copyRecipient()
    }

    func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        let rowId = rowId(for: signalRecipient)!
        recipientTable[rowId] = nil
    }

    private func rowId(for signalRecipient: SignalRecipient) -> Int? {
        for (rowId, value) in recipientTable {
            if value.uniqueId == signalRecipient.uniqueId {
                return rowId
            }
        }
        return nil
    }
}

private class MockRecipientMergerTemporaryShims: RecipientMergerTemporaryShims {
    func hasActiveSignalProtocolSession(recipientId: String, deviceId: Int32, transaction: DBWriteTransaction) -> Bool { false }
}

private class MockStorageServiceManager: StorageServiceManager {
    func recordPendingUpdates(updatedAccountIds: [AccountId]) {}
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {}
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {}
    func recordPendingUpdates(groupModel: TSGroupModel) {}
    func recordPendingLocalAccountUpdates() {}
    func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiersObjC) {}
    func backupPendingChanges(authedAccount: AuthedAccount) {}
    func resetLocalData(transaction: DBWriteTransaction) {}
    func restoreOrCreateManifestIfNecessary(authedAccount: AuthedAccount) -> AnyPromise {
        AnyPromise(Promise<Void>(error: OWSGenericError("Not implemented.")))
    }
    func waitForPendingRestores() -> AnyPromise {
        AnyPromise(Promise<Void>(error: OWSGenericError("Not implemented.")))
    }
}

class RecipientMergerTest: XCTestCase {
    func testTwoWayMergeCases() {
        let aci_A = Aci.constantForTesting("00000000-0000-4000-8000-00000000000A")
        let aci_B = Aci.constantForTesting("00000000-0000-4000-8000-00000000000B")
        let aciMe = Aci.constantForTesting("00000000-0000-4000-8000-00000000000C")
        let e164_A = E164("+16505550101")!
        let e164_B = E164("+16505550102")!
        let e164Me = E164("+16505550103")!
        let localIdentifiers = LocalIdentifiers(aci: aciMe, pni: nil, phoneNumber: e164Me.stringValue)

        enum TrustLevel {
            case high
            case low
        }

        // Taken from the "ACI-E164 Merging Test Cases" document.
        let testCases: [(
            trustLevel: TrustLevel,
            mergeRequest: (aci: Aci?, phoneNumber: E164?),
            initialState: [(rowId: Int, aci: Aci?, phoneNumber: E164?)],
            finalState: [(rowId: Int, aci: Aci?, phoneNumber: E164?)]
        )] = [
            (.high, (aci_A, nil), [], [(1, aci_A, nil)]),
            (.low, (aci_A, nil), [], [(1, aci_A, nil)]),
            (.high, (nil, e164_A), [], [(1, nil, e164_A)]),
            (.low, (nil, e164_A), [], [(1, nil, e164_A)]),
            (.high, (aci_A, e164_A), [], [(1, aci_A, e164_A)]),
            (.low, (aci_A, e164_A), [], [(1, aci_A, nil)]),
            (.high, (aci_A, e164_A), [(1, aci_A, nil)], [(1, aci_A, e164_A)]),
            (.low, (aci_A, e164_A), [(1, aci_A, nil)], [(1, aci_A, nil)]),
            (.high, (aci_A, e164_B), [(1, aci_A, e164_A)], [(1, aci_A, e164_B)]),
            (.low, (aci_A, e164_B), [(1, aci_A, e164_A)], [(1, aci_A, e164_A)]),
            (.high, (aci_A, e164_A), [(1, nil, e164_A)], [(1, aci_A, e164_A)]),
            (.low, (aci_A, e164_A), [(1, nil, e164_A)], [(1, nil, e164_A), (2, aci_A, nil)]),
            (.high, (aci_B, e164_A), [(1, aci_A, e164_A)], [(1, aci_A, nil), (2, aci_B, e164_A)]),
            (.low, (aci_B, e164_A), [(1, aci_A, e164_A)], [(1, aci_A, e164_A), (2, aci_B, nil)]),
            (.high, (aci_B, e164Me), [(1, aciMe, e164Me)], [(1, aciMe, e164Me), (2, aci_B, nil)]),
            (.low, (aci_B, e164Me), [(1, aciMe, e164Me)], [(1, aciMe, e164Me), (2, aci_B, nil)]),
            (.high, (aci_A, e164_A), [(1, aci_A, e164_A)], [(1, aci_A, e164_A)]),
            (.low, (aci_A, e164_A), [(1, aci_A, e164_A)], [(1, aci_A, e164_A)]),
            (.high, (aci_A, e164_A), [(1, aci_A, nil), (2, nil, e164_A)], [(1, aci_A, e164_A)]),
            (.low, (aci_A, e164_A), [(1, aci_A, nil), (2, nil, e164_A)], [(1, aci_A, nil), (2, nil, e164_A)]),
            (.high, (aci_A, e164_A), [(1, aci_A, e164_B), (2, aci_B, e164_A)], [(1, aci_A, e164_A), (2, aci_B, nil)]),
            (.low, (aci_A, e164_A), [(1, aci_A, e164_B), (2, aci_B, e164_A)], [(1, aci_A, e164_B), (2, aci_B, e164_A)]),
            (.high, (aci_A, e164_A), [(1, aci_A, e164_B), (2, nil, e164_A)], [(1, aci_A, e164_A)]),
            (.high, (aci_A, e164Me), [(1, aciMe, e164Me), (2, aci_A, nil)], [(1, aciMe, e164Me), (2, aci_A, nil)]),
            (.low, (aci_A, e164Me), [(1, aciMe, e164Me), (2, aci_A, nil)], [(1, aciMe, e164Me), (2, aci_A, nil)])
        ]

        for (idx, testCase) in testCases.enumerated() {
            let mockDB = MockDB()
            let mockDataStore = MockRecipientDataStore()
            let recipientFetcher = RecipientFetcherImpl(recipientStore: mockDataStore)
            let recipientMerger = RecipientMergerImpl(
                temporaryShims: MockRecipientMergerTemporaryShims(),
                observers: [],
                recipientFetcher: recipientFetcher,
                dataStore: mockDataStore,
                storageServiceManager: MockStorageServiceManager()
            )
            func run(transaction: DBWriteTransaction) {
                for initialRecipient in testCase.initialState {
                    XCTAssertEqual(mockDataStore.nextRowId, initialRecipient.rowId, "\(testCase)")
                    mockDataStore.insertRecipient(
                        SignalRecipient(
                            aci: initialRecipient.aci,
                            pni: nil,
                            phoneNumber: initialRecipient.phoneNumber
                        ),
                        transaction: transaction
                    )
                }

                switch (testCase.trustLevel, testCase.mergeRequest.aci, testCase.mergeRequest.phoneNumber) {
                case (.high, let aci?, let phoneNumber?):
                    _ = recipientMerger.applyMergeFromLinkedDevice(
                        localIdentifiers: localIdentifiers,
                        aci: aci,
                        phoneNumber: phoneNumber,
                        tx: transaction
                    )
                case (_, let aci?, _):
                    _ = recipientFetcher.fetchOrCreate(serviceId: aci, tx: transaction)
                case (_, _, let phoneNumber):
                    _ = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber!, tx: transaction)
                }

                for finalRecipient in testCase.finalState.reversed() {
                    let signalRecipient = mockDataStore.recipientTable.removeValue(forKey: finalRecipient.rowId)
                    XCTAssertEqual(signalRecipient?.aci, finalRecipient.aci, "\(idx)")
                    XCTAssertEqual(signalRecipient?.phoneNumber, finalRecipient.phoneNumber?.stringValue, "\(idx)")
                }
                XCTAssertEqual(mockDataStore.recipientTable, [:], "\(idx)")
            }
            mockDB.write { run(transaction: $0) }
        }
    }

    func testNotifier() {
        let mockDB = MockDB()
        let mockDataStore = MockRecipientDataStore()
        let recipientFetcher = RecipientFetcherImpl(recipientStore: mockDataStore)
        let recipientMergeNotifier = RecipientMergeNotifier(scheduler: SyncScheduler())
        let recipientMerger = RecipientMergerImpl(
            temporaryShims: MockRecipientMergerTemporaryShims(),
            observers: [recipientMergeNotifier],
            recipientFetcher: recipientFetcher,
            dataStore: mockDataStore,
            storageServiceManager: MockStorageServiceManager()
        )
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let phoneNumber = E164("+16505550101")!

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .didLearnRecipientAssociation,
            object: recipientMergeNotifier,
            queue: nil,
            using: { note in
                notificationCount += 1
            }
        )
        mockDB.write { tx in
            _ = recipientMerger.applyMergeFromSealedSender(
                localIdentifiers: .forUnitTests,
                aci: aci,
                phoneNumber: nil,
                tx: tx
            )
        }
        XCTAssertEqual(notificationCount, 0)
        mockDB.write { tx in
            _ = recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: .forUnitTests,
                aci: aci,
                phoneNumber: phoneNumber,
                tx: tx
            )
        }
        XCTAssertEqual(notificationCount, 1)
        NotificationCenter.default.removeObserver(observer)
    }
}
