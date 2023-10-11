//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit
import XCTest

@testable import SignalServiceKit

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

private class TestDependencies {
    let aciSessionStore: SignalSessionStore
    let identityManager: MockIdentityManager
    let keyValueStoreFactory = InMemoryKeyValueStoreFactory()
    let mockDB = MockDB()
    let recipientMerger: RecipientMerger
    let recipientStore = MockRecipientDataStore()
    let recipientFetcher: RecipientFetcher
    let recipientIdFinder: RecipientIdFinder

    init(observers: [RecipientMergeObserver] = []) {
        recipientFetcher = RecipientFetcherImpl(recipientStore: recipientStore)
        recipientIdFinder = RecipientIdFinder(recipientFetcher: recipientFetcher, recipientStore: recipientStore)
        aciSessionStore = SSKSessionStore(for: .aci, keyValueStoreFactory: keyValueStoreFactory, recipientIdFinder: recipientIdFinder)
        identityManager = MockIdentityManager(recipientIdFinder: recipientIdFinder)
        identityManager.recipientIdentities = [:]
        recipientMerger = RecipientMergerImpl(
            aciSessionStore: aciSessionStore,
            identityManager: identityManager,
            observers: observers,
            recipientFetcher: recipientFetcher,
            recipientStore: recipientStore,
            storageServiceManager: MockStorageServiceManager()
        )
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
            let d = TestDependencies()
            func run(transaction: DBWriteTransaction) {
                for initialRecipient in testCase.initialState {
                    XCTAssertEqual(d.recipientStore.nextRowId, initialRecipient.rowId, "\(testCase)")
                    d.recipientStore.insertRecipient(
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
                    _ = d.recipientMerger.applyMergeFromLinkedDevice(
                        localIdentifiers: localIdentifiers,
                        aci: aci,
                        phoneNumber: phoneNumber,
                        tx: transaction
                    )
                case (_, let aci?, _):
                    _ = d.recipientFetcher.fetchOrCreate(serviceId: aci, tx: transaction)
                case (_, _, let phoneNumber):
                    _ = d.recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber!, tx: transaction)
                }

                for finalRecipient in testCase.finalState.reversed() {
                    let signalRecipient = d.recipientStore.recipientTable.removeValue(forKey: finalRecipient.rowId)
                    XCTAssertEqual(signalRecipient?.aci, finalRecipient.aci, "\(idx)")
                    XCTAssertEqual(signalRecipient?.phoneNumber, finalRecipient.phoneNumber?.stringValue, "\(idx)")
                }
                XCTAssertEqual(d.recipientStore.recipientTable, [:], "\(idx)")
            }
            d.mockDB.write { run(transaction: $0) }
        }
    }

    func testNotifier() {
        let recipientMergeNotifier = RecipientMergeNotifier(scheduler: SyncScheduler())
        let d = TestDependencies(observers: [recipientMergeNotifier])

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
        d.mockDB.write { tx in
            _ = d.recipientMerger.applyMergeFromSealedSender(
                localIdentifiers: .forUnitTests,
                aci: aci,
                phoneNumber: nil,
                tx: tx
            )
        }
        XCTAssertEqual(notificationCount, 0)
        d.mockDB.write { tx in
            _ = d.recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: .forUnitTests,
                aci: aci,
                phoneNumber: phoneNumber,
                tx: tx
            )
        }
        XCTAssertEqual(notificationCount, 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testAciPhoneNumberSafetyNumberChange() {
        let ac1 = Aci.constantForTesting("00000000-0000-4000-8000-00000000000A")
        let ac2 = Aci.constantForTesting("00000000-0000-4000-8000-00000000000B")
        let ik1 = IdentityKey(publicKey: IdentityKeyPair.generate().publicKey)
        let ik2 = IdentityKey(publicKey: IdentityKeyPair.generate().publicKey)
        let pn1 = E164("+16505550101")!
        let pn2 = E164("+16505550102")!

        let testCases: [(
            initialState: [(aci: Aci?, phoneNumber: E164?, identityKey: IdentityKey?)],
            shouldInsertEvent: Bool
        )] = [
            ([(ac1, nil, ik1), (nil, pn1, ik2)], true),
            ([(ac1, nil, ik1), (nil, pn1, ik1)], false),
            ([(ac1, nil, ik1), (nil, pn1, nil)], false),
            ([(ac1, nil, nil), (nil, pn1, ik1)], false),
            ([(ac1, pn2, ik1), (nil, pn1, ik1)], false),
            ([(ac1, pn2, ik1), (nil, pn1, ik2)], true),
            ([(ac1, nil, ik1), (ac2, pn1, ik1)], false),
            ([(ac1, nil, ik1), (ac2, pn1, ik2)], false)
        ]

        for testCase in testCases {
            let d = TestDependencies()

            let aciSessionKeyValueStore = d.keyValueStoreFactory.keyValueStore(collection: "TSStorageManagerSessionStoreCollection")
            d.identityManager.identityChangeInfoMessages = []

            d.mockDB.write { tx in
                for initialState in testCase.initialState {
                    let recipient = SignalRecipient(aci: initialState.aci, pni: nil, phoneNumber: initialState.phoneNumber)
                    d.recipientStore.insertRecipient(recipient, transaction: tx)
                    if let identityKey = initialState.identityKey {
                        d.identityManager.recipientIdentities[recipient.uniqueId] = OWSRecipientIdentity(
                            accountId: recipient.uniqueId,
                            identityKey: Data(identityKey.publicKey.keyBytes),
                            isFirstKnownKey: true,
                            createdAt: Date(),
                            verificationState: .default
                        )
                        aciSessionKeyValueStore.setData(Data(), key: recipient.uniqueId, transaction: tx)
                    }
                }

                let mergedRecipient = d.recipientMerger.applyMergeFromSealedSender(
                    localIdentifiers: .forUnitTests,
                    aci: ac1,
                    phoneNumber: pn1,
                    tx: tx
                )

                XCTAssertEqual(d.identityManager.identityChangeInfoMessages, testCase.shouldInsertEvent ? [ac1] : [])
                XCTAssertEqual(try! d.identityManager.identityKey(for: ac1, tx: tx), ik1)
                XCTAssertTrue(d.aciSessionStore.mightContainSession(for: mergedRecipient, tx: tx))
            }
        }
    }
}
