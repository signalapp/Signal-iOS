//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class LearnMyOwnPniManagerTest: XCTestCase {
    private struct TestKeyValueStore {
        static let hasSucceededKey = "hasCompletedPniLearning"

        private let kvStore: KeyValueStore

        init(kvStoreFactory: KeyValueStoreFactory) {
            kvStore = kvStoreFactory.keyValueStore(collection: "LearnMyOwnPniManagerImpl")
        }

        func hasSucceeded(tx: DBReadTransaction) -> Bool {
            return kvStore.getBool(Self.hasSucceededKey, defaultValue: false, transaction: tx)
        }

        func setHasSucceeded(tx: DBWriteTransaction) {
            kvStore.setBool(true, key: Self.hasSucceededKey, transaction: tx)
        }
    }

    private var accountServiceClientMock: AccountServiceClientMock!
    private var pniIdentityKeyCheckerMock: PniIdentityKeyCheckerMock!
    private var preKeyManagerMock: PreKeyManagerMock!
    private var tsAccountManagerMock: TSAccountManagerMock!

    private var kvStore: TestKeyValueStore!
    private let db = MockDB()
    private var scheduler: TestScheduler!

    private var learnMyOwnPniManager: LearnMyOwnPniManager!

    override func setUp() {
        accountServiceClientMock = .init()
        pniIdentityKeyCheckerMock = .init()
        preKeyManagerMock = .init()
        tsAccountManagerMock = .init()

        let kvStoreFactory = InMemoryKeyValueStoreFactory()
        kvStore = TestKeyValueStore(kvStoreFactory: kvStoreFactory)

        scheduler = TestScheduler()
        let schedulers = TestSchedulers(scheduler: scheduler)
        schedulers.scheduler.start()

        learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            accountServiceClient: accountServiceClientMock,
            db: db,
            keyValueStoreFactory: kvStoreFactory,
            pniIdentityKeyChecker: pniIdentityKeyCheckerMock,
            preKeyManager: preKeyManagerMock,
            schedulers: schedulers,
            tsAccountManager: tsAccountManagerMock
        )
    }

    override func tearDown() {
        accountServiceClientMock.whoAmIResult.ensureUnset()
        pniIdentityKeyCheckerMock.checkResult.ensureUnset()
        preKeyManagerMock.createKeysResult.ensureUnset()
    }

    func testSkipsIfAlreadySucceeded() {
        db.write { kvStore.setHasSucceeded(tx: $0) }

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsIfLinkedDevice() {
        tsAccountManagerMock.isPrimaryDevice = false

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsIfNoLocalIdentifiers() {
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testFetchesPniAndCreatesKeysIfMissingPni() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: localE164))
        pniIdentityKeyCheckerMock.checkResult = .value(false) // Can assume false since we didn't even know the PNI
        preKeyManagerMock.createKeysResult = .value(())

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertEqual(remotePni, tsAccountManagerMock.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniFetchButCreatesKeysIfPniPresentButKeyDoesntMatch() {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        pniIdentityKeyCheckerMock.checkResult = .value(false)
        preKeyManagerMock.createKeysResult = .value(())

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniFetchAndDoesntCreateKeysIfPniPresentAndKeyMatches() {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        pniIdentityKeyCheckerMock.checkResult = .value(true)

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniSaveIfMismatchedAci() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remoteAci = Aci.randomForTesting()
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.whoAmIResult = .value(.init(aci: remoteAci, pni: remotePni, e164: localE164))

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniSaveIfMismatchedE164() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remotePni = Pni.randomForTesting()
        let remoteE164 = E164("+17735550198")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: remoteE164))

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testConcurrentCalls() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: localE164))
        pniIdentityKeyCheckerMock.checkResult = .value(true)

        // Stop the scheduler and call twice; should only fetch once!
        scheduler.stop()
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()
        scheduler.start()

        XCTAssertEqual(remotePni, tsAccountManagerMock.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

}

private extension WhoAmIRequestFactory.Responses.WhoAmI {
    init(aci: Aci, pni: Pni, e164: E164) {
        self.init(aci: aci, pni: pni, e164: e164, usernameHash: nil)
    }
}

// MARK: - Mocks

// MARK: AccountServiceClient

private class AccountServiceClientMock: LearnMyOwnPniManagerImpl.Shims.AccountServiceClient {
    typealias WhoAmI = WhoAmIRequestFactory.Responses.WhoAmI

    var whoAmIResult: ConsumableMockPromise<WhoAmI> = .unset

    func getAccountWhoAmI() -> Promise<WhoAmI> {
        return whoAmIResult.consumeIntoPromise()
    }
}

// MARK: PniIdentityKeyChecker

private class PniIdentityKeyCheckerMock: PniIdentityKeyChecker {
    var checkResult: ConsumableMockPromise<Bool> = .unset

    func serverHasSameKeyAsLocal(localPni: Pni, tx: DBReadTransaction) -> Promise<Bool> {
        return checkResult.consumeIntoPromise()
    }
}

// MARK: PreKeyManager

private class PreKeyManagerMock: MockPreKeyManager {
    var createKeysResult: ConsumableMockPromise<Void> = .unset

    override func createOrRotatePNIPreKeys(auth: ChatServiceAuth) -> Promise<Void> {
        return createKeysResult.consumeIntoPromise()
    }
}

// MARK: TSAccountManager

private class TSAccountManagerMock: LearnMyOwnPniManagerImpl.Shims.TSAccountManager {
    var isPrimaryDevice: Bool = true
    var mockIdentifiers: LocalIdentifiers?
    var updatedPni: Pni?

    func isPrimaryDevice(tx _: DBReadTransaction) -> Bool {
        return isPrimaryDevice
    }

    func localIdentifiers(tx _: DBReadTransaction) -> LocalIdentifiers? {
        return mockIdentifiers
    }

    func updateLocalIdentifiers(e164 _: E164, aci _: Aci, pni: Pni, tx _: DBWriteTransaction) {
        updatedPni = pni
    }
}
