//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import XCTest

@testable import SignalServiceKit

private class MockRecipientDataStore: RecipientDataStore {
    var nextRowId = 1
    var recipientTable: [Int: SignalRecipient] = [:]

    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient? {
        copyRecipient(recipientTable.values.first(where: { $0.recipientUUID == serviceId.uuidValue.uuidString }) ?? nil)
    }

    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient? {
        copyRecipient(recipientTable.values.first(where: { $0.recipientPhoneNumber == phoneNumber }) ?? nil)
    }

    private func copyRecipient(_ signalRecipient: SignalRecipient?) -> SignalRecipient? {
        signalRecipient?.copy() as! SignalRecipient?
    }

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        precondition(rowId(for: signalRecipient) == nil)
        recipientTable[nextRowId] = copyRecipient(signalRecipient)
        nextRowId += 1
    }

    func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        let rowId = rowId(for: signalRecipient)!
        recipientTable[rowId] = copyRecipient(signalRecipient)
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
    func clearMappings(phoneNumber: String, transaction: DBWriteTransaction) {}

    func clearMappings(serviceId: ServiceId, transaction: DBWriteTransaction) {}

    func didUpdatePhoneNumber(oldServiceIdString: String?, oldPhoneNumber: String?, newServiceIdString: String?, newPhoneNumber: String?, transaction: DBWriteTransaction) {}

    func mergeUserProfilesIfNecessary(serviceId: ServiceId, phoneNumber: String, transaction: DBWriteTransaction) {}

    func hasActiveSignalProtocolSession(recipientId: String, deviceId: Int32, transaction: DBWriteTransaction) -> Bool { false }
}

private class MockStorageServiceManager: StorageServiceManager {
    func recordPendingDeletions(deletedGroupV1Ids: [Data]) {}
    func recordPendingUpdates(updatedAccountIds: [AccountId], authedAccount: AuthedAccount) {}
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress], authedAccount: AuthedAccount) {}
    func recordPendingUpdates(updatedGroupV1Ids: [Data]) {}
    func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {}
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {}
    func recordPendingUpdates(groupModel: TSGroupModel) {}
    func recordPendingLocalAccountUpdates() {}
    func backupPendingChanges(authedAccount: AuthedAccount) {}
    func resetLocalData(transaction: SDSAnyWriteTransaction) {}
    func restoreOrCreateManifestIfNecessary(authedAccount: AuthedAccount) -> AnyPromise {
        AnyPromise(Promise<Void>(error: OWSGenericError("Not implemented.")))
    }
    func waitForPendingRestores() -> AnyPromise {
        AnyPromise(Promise<Void>(error: OWSGenericError("Not implemented.")))
    }
}

class RecipientMergerTest: XCTestCase {
    func testTwoWayMergeCases() {
        let aci_A = ServiceId(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let aci_B = ServiceId(uuidString: "00000000-0000-4000-8000-00000000000B")!
        let e164_A = E164("+16505550101")!
        let e164_B = E164("+16505550102")!

        // Taken from the "ACI-E164 Merging Test Cases" document.
        let testCases: [(
            trustLevel: SignalRecipientTrustLevel,
            mergeRequest: (serviceId: ServiceId?, phoneNumber: E164?),
            initialState: [(rowId: Int, serviceId: ServiceId?, phoneNumber: E164?)],
            finalState: [(rowId: Int, serviceId: ServiceId?, phoneNumber: E164?)]
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
            (.high, (aci_A, e164_A), [(1, aci_A, e164_A)], [(1, aci_A, e164_A)]),
            (.low, (aci_A, e164_A), [(1, aci_A, e164_A)], [(1, aci_A, e164_A)]),
            (.high, (aci_A, e164_A), [(1, aci_A, nil), (2, nil, e164_A)], [(1, aci_A, e164_A)]),
            (.low, (aci_A, e164_A), [(1, aci_A, nil), (2, nil, e164_A)], [(1, aci_A, nil), (2, nil, e164_A)]),
            (.high, (aci_A, e164_A), [(1, aci_A, e164_B), (2, aci_B, e164_A)], [(1, aci_A, e164_A), (2, aci_B, nil)]),
            (.low, (aci_A, e164_A), [(1, aci_A, e164_B), (2, aci_B, e164_A)], [(1, aci_A, e164_B), (2, aci_B, e164_A)])
        ]

        for (idx, testCase) in testCases.enumerated() {
            let mockDB = MockDB()
            let mockDataStore = MockRecipientDataStore()
            let recipientMerger = RecipientMergerImpl(
                temporaryShims: MockRecipientMergerTemporaryShims(),
                dataStore: mockDataStore,
                storageServiceManager: MockStorageServiceManager()
            )
            mockDB.write {
                for initialRecipient in testCase.initialState {
                    XCTAssertEqual(mockDataStore.nextRowId, initialRecipient.rowId, "\(testCase)")
                    mockDataStore.insertRecipient(
                        SignalRecipient(
                            serviceId: initialRecipient.serviceId.map { ServiceIdObjC($0) },
                            phoneNumber: initialRecipient.phoneNumber?.stringValue
                        ),
                        transaction: $0
                    )
                }

                _ = recipientMerger.merge(
                    trustLevel: testCase.trustLevel,
                    serviceId: testCase.mergeRequest.serviceId,
                    phoneNumber: testCase.mergeRequest.phoneNumber?.stringValue,
                    transaction: $0
                )

                for finalRecipient in testCase.finalState.reversed() {
                    let signalRecipient = mockDataStore.recipientTable.removeValue(forKey: finalRecipient.rowId)
                    XCTAssertEqual(signalRecipient?.recipientUUID, finalRecipient.serviceId?.uuidValue.uuidString, "\(idx)")
                    XCTAssertEqual(signalRecipient?.recipientPhoneNumber, finalRecipient.phoneNumber?.stringValue, "\(idx)")
                }
                XCTAssertEqual(mockDataStore.recipientTable, [:], "\(idx)")
            }
        }
    }
}
