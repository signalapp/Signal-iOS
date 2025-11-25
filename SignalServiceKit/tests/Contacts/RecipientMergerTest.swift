//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import XCTest

@testable import SignalServiceKit

private class MockStorageServiceManager: StorageServiceManager {
    func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiers) {}
    func registerForCron(_ cron: Cron) {}
    func currentManifestVersion(tx: DBReadTransaction) -> UInt64 { 0 }
    func currentManifestHasRecordIkm(tx: DBReadTransaction) -> Bool { false }
    func recordPendingUpdates(updatedRecipientUniqueIds: [RecipientUniqueId]) {}
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    func recordPendingUpdates(updatedGroupV2MasterKeys: [GroupMasterKey]) {}
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {}
    func recordPendingUpdates(callLinkRootKeys: [CallLinkRootKey]) {}
    func recordPendingLocalAccountUpdates() {}
    func backupPendingChanges(authedDevice: AuthedDevice) {}
    func resetLocalData(transaction: DBWriteTransaction) {}
    func restoreOrCreateManifestIfNecessary(authedDevice: AuthedDevice, masterKeySource: StorageService.MasterKeySource) -> Promise<Void> { Promise<Void>(error: OWSGenericError("Not implemented.")) }
    func rotateManifest(mode: ManifestRotationMode, authedDevice: AuthedDevice) async throws { throw OWSGenericError("Not implemented.") }
    func waitForPendingRestores() async throws { throw OWSGenericError("Not implemented.") }
}

private class TestDependencies {
    let aciSessionStore: SignalSessionStore
    var aciSessionStoreKeyValueStore: KeyValueStore {
        KeyValueStore(collection: "TSStorageManagerSessionStoreCollection")
    }
    let identityManager: MockIdentityManager
    let mockDB = InMemoryDB()
    let recipientMerger: RecipientMerger
    let recipientDatabaseTable = RecipientDatabaseTable()
    let recipientFetcher: RecipientFetcher
    let recipientIdFinder: RecipientIdFinder
    let threadAssociatedDataStore: MockThreadAssociatedDataStore
    let threadStore: MockThreadStore
    let threadMerger: ThreadMerger

    init(observers: [RecipientMergeObserver] = []) {
        let searchableNameIndexer = MockSearchableNameIndexer()
        let storageServiceManager = MockStorageServiceManager()
        recipientFetcher = RecipientFetcherImpl(
            recipientDatabaseTable: recipientDatabaseTable,
            searchableNameIndexer: searchableNameIndexer,
        )
        recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)
        aciSessionStore = SSKSessionStore(for: .aci, recipientIdFinder: recipientIdFinder)
        identityManager = MockIdentityManager(recipientIdFinder: recipientIdFinder)
        identityManager.recipientIdentities = [:]
        identityManager.sessionSwitchoverMessages = []
        threadAssociatedDataStore = MockThreadAssociatedDataStore()
        threadStore = MockThreadStore()
        threadMerger = ThreadMerger.forUnitTests(
            threadAssociatedDataStore: threadAssociatedDataStore,
            threadStore: threadStore
        )
        recipientMerger = RecipientMergerImpl(
            aciSessionStore: aciSessionStore,
            blockedRecipientStore: BlockedRecipientStore(),
            identityManager: identityManager,
            observers: RecipientMergerImpl.Observers(
                preThreadMerger: [],
                threadMerger: threadMerger,
                postThreadMerger: observers
            ),
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            searchableNameIndexer: searchableNameIndexer,
            storageServiceManager: storageServiceManager,
            storyRecipientStore: StoryRecipientStore()
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
            initialState: [(rowId: Int64, aci: Aci?, phoneNumber: E164?)],
            finalState: [(rowId: Int64, aci: Aci?, phoneNumber: E164?)]
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
                    let recipient = try! SignalRecipient.insertRecord(
                        aci: initialRecipient.aci,
                        phoneNumber: initialRecipient.phoneNumber,
                        pni: nil,
                        tx: transaction,
                    )
                    XCTAssertEqual(recipient.id, initialRecipient.rowId, "\(testCase)")
                }

                switch (testCase.trustLevel, testCase.mergeRequest.aci, testCase.mergeRequest.phoneNumber) {
                case (.high, let aci?, let phoneNumber?):
                    _ = d.recipientMerger.applyMergeFromContactSync(
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

                var recipientTable = [SignalRecipient.RowId: SignalRecipient]()
                d.recipientDatabaseTable.enumerateAll(tx: transaction) {
                    recipientTable[$0.id] = $0
                }

                for finalRecipient in testCase.finalState.reversed() {
                    let signalRecipient = recipientTable.removeValue(forKey: finalRecipient.rowId)
                    XCTAssertEqual(signalRecipient?.aci, finalRecipient.aci, "\(idx)")
                    XCTAssertEqual(signalRecipient?.phoneNumber?.stringValue, finalRecipient.phoneNumber?.stringValue, "\(idx)")
                }
                XCTAssert(recipientTable.isEmpty, "\(idx)")
            }
            d.mockDB.write { run(transaction: $0) }
        }
    }

    func testNotifier() {
        let recipientMergeNotifier = RecipientMergeNotifier()
        let d = TestDependencies(observers: [recipientMergeNotifier])

        let aci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let phoneNumber = E164("+16505550101")!
        let pni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")

        let observerThatWillFail = NotificationCenter.default.addObserver(
            forName: .didLearnRecipientAssociation,
            object: recipientMergeNotifier,
            queue: nil,
            using: { _ in XCTFail("Unexpected notification!") }
        )
        d.mockDB.write { tx in
            _ = d.recipientMerger.applyMergeFromSealedSender(
                localIdentifiers: .forUnitTests,
                aci: aci,
                phoneNumber: nil,
                tx: tx
            )
        }
        NotificationCenter.default.removeObserver(observerThatWillFail)

        let notificationExpectation = XCTNSNotificationExpectation(name: .didLearnRecipientAssociation)
        notificationExpectation.expectedFulfillmentCount = 2
        notificationExpectation.assertForOverFulfill = true
        d.mockDB.write { tx in
            _ = d.recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: .forUnitTests,
                phoneNumber: phoneNumber,
                pni: pni,
                aci: aci,
                tx: tx
            )
        }

        wait(for: [notificationExpectation], timeout: 1)
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

            d.identityManager.identityChangeInfoMessages = []

            d.mockDB.write { tx in
                for initialState in testCase.initialState {
                    let recipient = try! SignalRecipient.insertRecord(
                        aci: initialState.aci,
                        phoneNumber: initialState.phoneNumber,
                        pni: nil,
                        tx: tx,
                    )
                    if let identityKey = initialState.identityKey {
                        d.identityManager.recipientIdentities[recipient.uniqueId] = OWSRecipientIdentity(
                            uniqueId: recipient.uniqueId,
                            identityKey: identityKey.publicKey.keyBytes,
                            isFirstKnownKey: true,
                            createdAt: Date(),
                            verificationState: .default
                        )
                        d.aciSessionStoreKeyValueStore.setData(Data(), key: recipient.uniqueId, transaction: tx)
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

    func testAciPhoneNumberPniMerges() throws {
        let aci1 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let pni1 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")
        let phone1 = E164("+16505550101")!
        let phone2 = E164("+16505550102")!

        let testCases: [(
            initialState: [(aci: Aci?, phoneNumber: E164?, pni: Pni?)],
            includeAci: Bool,
            finalState: [(aci: Aci?, phoneNumber: E164?, pni: Pni?)?]
        )] = [
            // If they're already associated, do nothing.
            ([(aci1, phone1, pni1)], false, [(aci1, phone1, pni1)]),
            ([(aci1, phone1, pni1)], true, [(aci1, phone1, pni1)]),
            ([(nil, phone1, pni1)], false, [(nil, phone1, pni1)]),
            ([(aci1, phone1, pni1)], true, [(aci1, phone1, pni1)]),

            // If the PNI doesn't exist anywhere, just add it.
            ([(aci1, phone1, nil)], false, [(aci1, phone1, pni1)]),
            ([(aci1, phone1, nil)], true, [(aci1, phone1, pni1)]),

            // If the PNI exists elsewhere, steal it.
            ([(nil, phone1, nil), (nil, phone2, pni1)], false, [(nil, phone1, pni1), (nil, phone2, nil)]),

            // If the PNI exists, steal it if possible.
            ([(nil, nil, pni1)], false, [(nil, phone1, pni1)]),
            ([(nil, phone2, pni1)], false, [(nil, phone2, nil), (nil, phone1, pni1)]),
            ([(aci1, nil, pni1)], false, [(aci1, phone1, pni1)]),

            // If nothing exists, create it.
            ([], false, [(nil, phone1, pni1)])
        ]

        for testCase in testCases {
            let d = TestDependencies()
            let mergedRecipient = d.mockDB.write { tx in
                for initialState in testCase.initialState {
                    _ = try! SignalRecipient.insertRecord(
                        aci: initialState.aci,
                        phoneNumber: initialState.phoneNumber,
                        pni: initialState.pni,
                        tx: tx,
                    )
                }
                return d.recipientMerger.applyMergeFromContactDiscovery(
                    localIdentifiers: .forUnitTests,
                    phoneNumber: phone1,
                    pni: pni1,
                    aci: testCase.includeAci ? aci1 : nil,
                    tx: tx
                )
            }

            // Make sure the returned recipient has the correct details.
            XCTAssertEqual(mergedRecipient?.phoneNumber?.stringValue, phone1.stringValue)
            XCTAssertEqual(mergedRecipient?.pni, pni1)
            if testCase.includeAci { XCTAssertEqual(mergedRecipient?.aci, aci1) }

            var recipientTable = [SignalRecipient.RowId: SignalRecipient]()
            d.mockDB.read { tx in
                d.recipientDatabaseTable.enumerateAll(tx: tx) {
                    recipientTable[$0.id] = $0
                }
            }

            // Make sure all the recipients have been updated properly.
            for (idx, finalState) in testCase.finalState.enumerated() {
                let recipient = try XCTUnwrap(recipientTable.removeValue(forKey: Int64(idx + 1)))
                XCTAssertEqual(recipient.phoneNumber?.stringValue, finalState?.phoneNumber?.stringValue)
                XCTAssertEqual(recipient.pni, finalState?.pni)
                XCTAssertEqual(recipient.aci, finalState?.aci)
            }
            XCTAssert(recipientTable.isEmpty)
        }
    }

    func testSessionSwitchoverEvents() throws {
        let aci1 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let phone1 = E164("+16505550101")!
        let pni1 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")

        let aci2 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a2")
        let phone2 = E164("+16505550102")!
        let pni2 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2")

        struct TestCase {
            let mergeRequest: (aci: Aci?, phoneNumber: E164, pni: Pni)
            let hasSession: [Int]
            let needsEvent: [Int]
            let lineNumber: Int

            init(
                _ mergeRequest: (aci: Aci?, phoneNumber: E164, pni: Pni),
                hasSession: [Int],
                needsEvent: [Int],
                _ lineNumber: Int = #line
            ) {
                self.mergeRequest = mergeRequest
                self.hasSession = hasSession
                self.needsEvent = needsEvent
                self.lineNumber = lineNumber
            }
        }

        let testCases: [TestCase] = [
            // If there's no session, there's no session switchover.
            TestCase((aci1, phone1, pni1), hasSession: [], needsEvent: []),
            // If there's a session, there's a session switchover.
            TestCase((aci1, phone1, pni1), hasSession: [1], needsEvent: [1]),
            // If we're already communicating with the aci, there's no switchover.
            TestCase((aci2, phone2, pni1), hasSession: [2], needsEvent: []),
            // But the source of the pni might need one if it had a session.
            TestCase((aci2, phone2, pni1), hasSession: [1, 2], needsEvent: [1]),
            // If we do a thread merge, we can skip the session switchover.
            TestCase((aci2, phone1, pni1), hasSession: [1, 2], needsEvent: []),
        ]

        for testCase in testCases {
            Logger.verbose("Starting test case from line \(testCase.lineNumber)")
            defer { Logger.flush() }

            let d = TestDependencies()
            let recipients = d.mockDB.write { tx in
                let recipient1 = try! SignalRecipient.insertRecord(aci: nil, phoneNumber: phone1, pni: pni1, tx: tx)
                let recipient2 = try! SignalRecipient.insertRecord(aci: aci2, phoneNumber: phone2, pni: pni2, tx: tx)
                return [recipient1, recipient2]
            }

            d.mockDB.write { tx in
                for recipientNumber in testCase.hasSession {
                    let recipient = recipients.dropFirst(recipientNumber - 1).first!
                    d.aciSessionStoreKeyValueStore.setData(Data(), key: recipient.uniqueId, transaction: tx)
                    let thread = TSContactThread(contactAddress: SignalServiceAddress(
                        serviceId: recipient.aci ?? recipient.pni,
                        phoneNumber: recipient.phoneNumber?.stringValue,
                        cache: SignalServiceAddressCache()
                    ))
                    thread.shouldThreadBeVisible = true
                    d.threadStore.insertThread(thread)
                    d.threadAssociatedDataStore.values[thread.uniqueId] = ThreadAssociatedData(threadUniqueId: thread.uniqueId)
                }
            }

            d.mockDB.write { tx in
                _ = d.recipientMerger.applyMergeFromContactDiscovery(
                    localIdentifiers: .forUnitTests,
                    phoneNumber: testCase.mergeRequest.phoneNumber,
                    pni: testCase.mergeRequest.pni,
                    aci: testCase.mergeRequest.aci,
                    tx: tx
                )
            }

            for recipientNumberNeedingEvent in testCase.needsEvent {
                let recipientNeedingEvent = recipients.dropFirst(recipientNumberNeedingEvent - 1).first!
                let foundRecipient = d.identityManager.sessionSwitchoverMessages.removeFirst(where: { (recipient, _) in
                    recipient.uniqueId == recipientNeedingEvent.uniqueId
                })
                XCTAssertNotNil(foundRecipient)
            }
            XCTAssertEqual(d.identityManager.sessionSwitchoverMessages.count, 0)
        }
    }

    func testPniSignatureMerge() throws {
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")

        let phoneNumber = E164("+16505550101")!
        let pni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")

        let d = TestDependencies()
        let aciRecipient = d.mockDB.write { tx in
            let aciRecipient = try! SignalRecipient.insertRecord(aci: aci, tx: tx)
            d.aciSessionStoreKeyValueStore.setData(Data(), key: aciRecipient.uniqueId, transaction: tx)

            let pniRecipient = try! SignalRecipient.insertRecord(phoneNumber: phoneNumber, pni: pni, tx: tx)
            d.aciSessionStoreKeyValueStore.setData(Data(), key: pniRecipient.uniqueId, transaction: tx)

            return aciRecipient
        }

        d.mockDB.write { tx in
            d.recipientMerger.applyMergeFromPniSignature(localIdentifiers: .forUnitTests, aci: aci, pni: pni, tx: tx)
        }

        var recipientTable = [SignalRecipient.RowId: SignalRecipient]()
        d.mockDB.read { tx in
            d.recipientDatabaseTable.enumerateAll(tx: tx) {
                recipientTable[$0.id] = $0
            }
        }

        XCTAssertEqual(recipientTable.values.map({ $0.uniqueId }), [aciRecipient.uniqueId])
        XCTAssertEqual(d.identityManager.sessionSwitchoverMessages.count, 0)
    }

    func testStorageServiceMerges() throws {
        let aci1 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let aci2 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a2")
        let pni1 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")
        let pni2 = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2")
        let phoneNumber1 = E164("+16505550101")!
        let phoneNumber2 = E164("+16505550102")!

        struct TestCase {
            let isPrimaryDevice: Bool
            let initialState: [(aci: Aci?, phoneNumber: E164?, pni: Pni?)]
            let mergeRequest: (aci: Aci?, phoneNumber: E164?, pni: Pni?)
            let finalState: [(aci: Aci?, phoneNumber: E164?, pni: Pni?, isResult: Bool)]
            let lineNumber: Int

            init(
                isPrimaryDevice: Bool,
                initialState: [(aci: Aci?, phoneNumber: E164?, pni: Pni?)],
                mergeRequest: (aci: Aci?, phoneNumber: E164?, pni: Pni?),
                finalState: [(aci: Aci?, phoneNumber: E164?, pni: Pni?, isResult: Bool)],
                lineNumber: Int = #line
            ) {
                self.isPrimaryDevice = isPrimaryDevice
                self.initialState = initialState
                self.mergeRequest = mergeRequest
                self.finalState = finalState
                self.lineNumber = lineNumber
            }
        }

        let testCases: [TestCase] = [
            // If we know the ACI/PNI, we can add the phone number.
            TestCase(
                isPrimaryDevice: true,
                initialState: [(aci1, nil, pni1)],
                mergeRequest: (nil, phoneNumber1, pni1),
                finalState: [(aci1, phoneNumber1, pni1, true)]
            ),
            // If we're linking a phone number/PNI across recipients, the phone number has precedence.
            TestCase(
                isPrimaryDevice: true,
                initialState: [(aci1, nil, pni1), (aci2, phoneNumber1, nil)],
                mergeRequest: (nil, phoneNumber1, pni1),
                finalState: [(aci1, nil, nil, false), (aci2, phoneNumber1, pni1, true)]
            ),
            // If we're trying to re-associate on a primary, that's not allowed/ignored.
            TestCase(
                isPrimaryDevice: true,
                initialState: [(aci1, phoneNumber1, pni1)],
                mergeRequest: (nil, phoneNumber1, pni2),
                finalState: [(aci1, phoneNumber1, pni1, true)]
            ),
            TestCase(
                isPrimaryDevice: false,
                initialState: [(aci1, phoneNumber1, pni1)],
                mergeRequest: (nil, phoneNumber1, pni2),
                finalState: [(aci1, phoneNumber1, pni2, true)]
            ),
            TestCase(
                isPrimaryDevice: true,
                initialState: [(aci1, phoneNumber1, pni1)],
                mergeRequest: (nil, phoneNumber2, pni1),
                finalState: [(aci1, phoneNumber1, pni1, true)]
            ),
            TestCase(
                isPrimaryDevice: false,
                initialState: [(aci1, phoneNumber1, pni1)],
                mergeRequest: (nil, phoneNumber2, pni1),
                finalState: [(aci1, phoneNumber1, nil, false), (nil, phoneNumber2, pni1, true)]
            ),
            // If we learn the PNI but not the phone number, we should add the PNI.
            TestCase(
                isPrimaryDevice: true,
                initialState: [(aci1, phoneNumber1, nil)],
                mergeRequest: (aci1, nil, pni1),
                finalState: [(aci1, phoneNumber1, pni1, true)]
            ),
            // But not if we already know some other PNI for the phone number.
            TestCase(
                isPrimaryDevice: true,
                initialState: [(aci1, phoneNumber1, pni1)],
                mergeRequest: (aci1, nil, pni2),
                finalState: [(aci1, phoneNumber1, pni1, true)]
            ),
            // Unless we're on a linked device.
            TestCase(
                isPrimaryDevice: false,
                initialState: [(aci1, phoneNumber1, pni1)],
                mergeRequest: (aci1, nil, pni2),
                finalState: [(aci1, phoneNumber1, pni2, true)]
            ),
            // But we can if we don't know a phone number.
            TestCase(
                isPrimaryDevice: true,
                initialState: [(aci1, nil, pni1)],
                mergeRequest: (aci1, nil, pni2),
                finalState: [(aci1, nil, pni2, true)]
            ),
            // If we get an ACI/PNI result, we should infer the phone number.
            TestCase(
                isPrimaryDevice: true,
                initialState: [(aci1, phoneNumber2, pni2), (nil, phoneNumber1, pni1)],
                mergeRequest: (aci1, nil, pni1),
                finalState: [(aci1, phoneNumber1, pni1, true)]
            ),
        ]

        for testCase in testCases {
            Logger.verbose("Starting test on line \(testCase.lineNumber)")
            defer { Logger.flush() }
            let d = TestDependencies()
            let mergedRecipient = d.mockDB.write { tx in
                for initialState in testCase.initialState {
                    _ = try! SignalRecipient.insertRecord(
                        aci: initialState.aci,
                        phoneNumber: initialState.phoneNumber,
                        pni: initialState.pni,
                        tx: tx,
                    )
                }
                return d.recipientMerger.applyMergeFromStorageService(
                    localIdentifiers: .forUnitTests,
                    isPrimaryDevice: testCase.isPrimaryDevice,
                    serviceIds: AtLeastOneServiceId(aci: testCase.mergeRequest.aci, pni: testCase.mergeRequest.pni)!,
                    phoneNumber: testCase.mergeRequest.phoneNumber,
                    tx: tx
                )
            }

            var recipientTable = [SignalRecipient.RowId: SignalRecipient]()
            d.mockDB.read { tx in
                d.recipientDatabaseTable.enumerateAll(tx: tx) {
                    recipientTable[$0.id] = $0
                }
            }

            // Make sure all the recipients have been updated properly.
            for (idx, finalState) in testCase.finalState.enumerated() {
                let recipient = try XCTUnwrap(recipientTable.removeValue(forKey: Int64(idx + 1)))
                XCTAssertEqual(recipient.phoneNumber?.stringValue, finalState.phoneNumber?.stringValue)
                XCTAssertEqual(recipient.pni, finalState.pni)
                XCTAssertEqual(recipient.aci, finalState.aci)
                if finalState.isResult {
                    XCTAssertEqual(mergedRecipient.uniqueId, recipient.uniqueId)
                }
            }
            XCTAssert(recipientTable.isEmpty)
        }
    }
}
