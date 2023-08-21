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
    private var identityManagerMock: IdentityManagerMock!
    private var preKeyManagerMock: PreKeyManagerMock!
    private var profileFetcherMock: ProfileFetcherMock!
    private var tsAccountManagerMock: TSAccountManagerMock!

    private var kvStore: TestKeyValueStore!
    private let db = MockDB()
    private var scheduler: TestScheduler!

    private var learnMyOwnPniManager: LearnMyOwnPniManager!

    override func setUp() {
        accountServiceClientMock = .init()
        identityManagerMock = .init()
        preKeyManagerMock = .init(identityManagerMock: identityManagerMock)
        profileFetcherMock = .init()
        tsAccountManagerMock = .init()

        let kvStoreFactory = InMemoryKeyValueStoreFactory()
        kvStore = TestKeyValueStore(kvStoreFactory: kvStoreFactory)

        scheduler = TestScheduler()
        let schedulers = TestSchedulers(scheduler: scheduler)
        schedulers.scheduler.start()

        learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            accountServiceClient: accountServiceClientMock,
            db: db,
            identityManager: identityManagerMock,
            keyValueStoreFactory: kvStoreFactory,
            preKeyManager: preKeyManagerMock,
            profileFetcher: profileFetcherMock,
            schedulers: schedulers,
            tsAccountManager: tsAccountManagerMock
        )
    }

    func testSkipsIfAlreadySucceeded() {
        db.write { kvStore.setHasSucceeded(tx: $0) }

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsIfLinkedDevice() {
        tsAccountManagerMock.isPrimaryDevice = false

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsIfNoLocalIdentifiers() {
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testFetchesPniIfMissing() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.mockWhoAmI = .init(aci: localAci, pni: remotePni, e164: localE164)

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertTrue(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertEqual(remotePni, tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniFetchIfPresent() {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniSaveIfMismatchedAci() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remoteAci = Aci.randomForTesting()
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.mockWhoAmI = .init(aci: remoteAci, pni: remotePni, e164: localE164)

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertTrue(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testCreatesPniKeysWithoutFetchingRemoteIfNoneLocal() {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testCreatesPniKeysIfRemoteMissing() {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        identityManagerMock.pniPublicKeyData = Data()
        profileFetcherMock.profileFetchResult = .success(nil)

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testCreatesPniKeysIfRemoteDoesNotMatchLocal() {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        identityManagerMock.pniPublicKeyData = Data(repeating: 3, count: 12)
        profileFetcherMock.profileFetchResult = .success(Data(repeating: 4, count: 12))

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testDoesNotCreatePniKeysIfErrorFetchingRemoteToCompare() {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        identityManagerMock.pniPublicKeyData = Data(repeating: 3, count: 12)
        profileFetcherMock.profileFetchResult = .failure(OWSGenericError("whoops"))

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testDoesNotCreatePniKeysIfRemoteMatchesLocal() {
        let localAci = Aci.randomForTesting()
        let localPni = Pni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        identityManagerMock.pniPublicKeyData = Data(repeating: 3, count: 12)
        profileFetcherMock.profileFetchResult = .success(Data(repeating: 3, count: 12))

        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testConcurrentCalls() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.mockWhoAmI = .init(aci: localAci, pni: remotePni, e164: localE164)

        // Stop the scheduler and call twice; should only fetch once!
        scheduler.stop()
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().cauterize()
        scheduler.start()

        XCTAssertTrue(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertEqual(remotePni, tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
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

    var mockWhoAmI: WhoAmI?
    private var whoAmIRequestFuture: Future<WhoAmI>?

    /// Completes a mocked operation that is async in the real app. Otherwise,
    /// since tests complete promises synchronously we may get database
    /// re-entrance.
    /// - Returns whether or not a mocked operation was completed.
    func completeWhoAmIRequest() -> Bool {
        guard let whoAmIRequestFuture else {
            return false
        }

        guard let mockWhoAmI else {
            whoAmIRequestFuture.reject(OWSGenericError("Missing mock!"))
            return false
        }

        whoAmIRequestFuture.resolve(mockWhoAmI)
        return true
    }

    func getAccountWhoAmI() -> Promise<WhoAmI> {
        guard whoAmIRequestFuture == nil else {
            XCTFail("Request already in-flight!")
            return Promise(error: OWSGenericError("Request already in flight!"))
        }

        let (promise, future) = Promise<WhoAmI>.pending()

        whoAmIRequestFuture = future
        return promise
    }
}

// MARK: IdentityManager

private class IdentityManagerMock: LearnMyOwnPniManagerImpl.Shims.IdentityManager {
    var pniPublicKeyData: Data?

    func pniIdentityPublicKeyData(tx _: DBReadTransaction) -> Data? {
        return pniPublicKeyData
    }
}

// MARK: PreKeyManager

private class PreKeyManagerMock: MockPreKeyManager {

    private let identityManagerMock: IdentityManagerMock

    init(identityManagerMock: IdentityManagerMock) {
        self.identityManagerMock = identityManagerMock
    }

    private var createKeysFuture: Future<Void>?

    /// Completes a mocked operation that is async in the real app. Otherwise,
    /// since tests complete promises synchronously we may get database
    /// re-entrance.
    /// - Returns whether or not a mocked operation was completed.
    func completeCreatePniKeys(_ pniIdentityKey: ECKeyPair? = nil) -> Bool {
        guard let createKeysFuture else {
            return false
        }
        identityManagerMock.pniPublicKeyData = (pniIdentityKey ?? Curve25519.generateKeyPair()).publicKey
        createKeysFuture.resolve()
        return true
    }

    override func createOrRotatePNIPreKeys(auth: ChatServiceAuth) -> Promise<Void> {
        guard createKeysFuture == nil else {
            XCTFail("Creation already in-flight!")
            return Promise(error: OWSGenericError("Creation already in-flight!"))
        }

        let (promise, future) = Promise<Void>.pending()

        createKeysFuture = future
        return promise
    }
}

// MARK: ProfileFetcher

private class ProfileFetcherMock: LearnMyOwnPniManagerImpl.Shims.ProfileFetcher {
    var profileFetchResult: Result<Data?, Error>?
    private var profileFetchFuture: Future<Data?>?

    /// Completes a mocked operation that is async in the real app. Otherwise,
    /// since tests complete promises synchronously we may get database
    /// re-entrance.
    /// - Returns whether or not a mocked operation was completed.
    func completeProfileFetch() -> Bool {
        guard let profileFetchFuture else {
            return false
        }

        guard let profileFetchResult else {
            XCTFail("Missing mock!")
            return false
        }

        switch profileFetchResult {
        case .success(let data):
            profileFetchFuture.resolve(data)
        case .failure(let error):
            profileFetchFuture.reject(error)
        }

        return true
    }

    func fetchPniIdentityPublicKey(localPni: Pni) -> Promise<Data?> {
        guard profileFetchFuture == nil else {
            XCTFail("Fetch already in-flight!")
            return Promise(error: OWSGenericError("Fetch already in flight!"))
        }

        let (promise, future) = Promise<Data?>.pending()

        profileFetchFuture = future
        return promise
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
