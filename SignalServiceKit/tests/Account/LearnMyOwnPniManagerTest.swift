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
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var tsAccountManagerMock: MockTSAccountManager!

    private var kvStore: TestKeyValueStore!
    private let db = MockDB()
    private var scheduler: TestScheduler!

    private var learnMyOwnPniManager: LearnMyOwnPniManager!

    private var updatedPni: Pni?

    override func setUp() {
        accountServiceClientMock = .init()
        pniIdentityKeyCheckerMock = .init()
        preKeyManagerMock = .init()
        registrationStateChangeManagerMock = .init()
        tsAccountManagerMock = .init()

        registrationStateChangeManagerMock.didUpdateLocalPhoneNumberMock = { [weak self] _, _, pni in
            self?.updatedPni = pni
        }

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
            registrationStateChangeManager: registrationStateChangeManagerMock,
            schedulers: schedulers,
            tsAccountManager: tsAccountManagerMock
        )
    }

    override func tearDown() {
        accountServiceClientMock.whoAmIResult.ensureUnset()
        pniIdentityKeyCheckerMock.checkResult.ensureUnset()
        preKeyManagerMock.createKeysResult.ensureUnset()
    }

    func testSkipsIfAlreadySucceeded() async throws {
        db.write { kvStore.setHasSucceeded(tx: $0) }

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertNil(self.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsIfLinkedDevice() async throws {
        tsAccountManagerMock.registrationStateMock = { .provisioned }

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertNil(self.updatedPni)
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsIfNoLocalIdentifiers() async throws {
        tsAccountManagerMock.localIdentifiersMock = { nil }
        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertNil(self.updatedPni)
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testFetchesPniAndCreatesKeysIfMissingPni() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: localE164))
        pniIdentityKeyCheckerMock.checkResult = .value(false) // Can assume false since we didn't even know the PNI
        preKeyManagerMock.createKeysResult = .value(())

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertEqual(remotePni, self.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniFetchButCreatesKeysIfPniPresentButKeyDoesntMatch() async throws {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: localPni, e164: localE164) }
        pniIdentityKeyCheckerMock.checkResult = .value(false)
        preKeyManagerMock.createKeysResult = .value(())

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertNil(self.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniFetchAndDoesntCreateKeysIfPniPresentAndKeyMatches() async throws {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: localPni, e164: localE164) }
        pniIdentityKeyCheckerMock.checkResult = .value(true)

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertNil(self.updatedPni)
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniSaveIfMismatchedAci() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remoteAci = Aci.randomForTesting()
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        accountServiceClientMock.whoAmIResult = .value(.init(aci: remoteAci, pni: remotePni, e164: localE164))

        do {
            try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()
            XCTFail("Expecting an error!")
        } catch {
            // We expect an error
        }

        XCTAssertNil(self.updatedPni)
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniSaveIfMismatchedE164() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remotePni = Pni.randomForTesting()
        let remoteE164 = E164("+17735550198")!

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: remoteE164))

        do {
            try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()
            XCTFail("Expecting an error!")
        } catch {
            // We expect an error
        }

        XCTAssertNil(self.updatedPni)
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testConcurrentCalls() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: localE164))
        pniIdentityKeyCheckerMock.checkResult = .value(true)

        // Stop the scheduler and call twice; should only fetch once!
        scheduler.stop()
        let expectation1 = self.expectation(description: "1")
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().observe(on: scheduler) {
            switch $0 {
            case .success:
                expectation1.fulfill()
            case .failure:
                XCTFail("Got error!")
            }
        }
        let expectation2 = self.expectation(description: "2")
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().observe(on: scheduler) {
            switch $0 {
            case .success:
                expectation2.fulfill()
            case .failure:
                XCTFail("Got error!")
            }
        }
        scheduler.start()

        self.wait(for: [expectation1, expectation2], timeout: 1, enforceOrder: false)

        XCTAssertEqual(remotePni, self.updatedPni)
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

    override func createOrRotatePNIPreKeys(auth: ChatServiceAuth) async -> Task<Void, Error> {
        return Task {
            return try await createKeysResult.consumeIntoPromise().awaitable()
        }
    }
}
