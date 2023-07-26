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

    private var learnMyOwnPniManager: LearnMyOwnPniManager!

    override func setUp() {
        accountServiceClientMock = .init()
        identityManagerMock = .init()
        preKeyManagerMock = .init()
        profileFetcherMock = .init()
        tsAccountManagerMock = .init()

        let kvStoreFactory = InMemoryKeyValueStoreFactory()
        kvStore = TestKeyValueStore(kvStoreFactory: kvStoreFactory)

        let schedulers = TestSchedulers(scheduler: TestScheduler())
        schedulers.scheduler.start()

        learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            accountServiceClient: accountServiceClientMock,
            identityManager: identityManagerMock,
            preKeyManager: preKeyManagerMock,
            profileFetcher: profileFetcherMock,
            tsAccountManager: tsAccountManagerMock,
            databaseStorage: db,
            keyValueStoreFactory: kvStoreFactory,
            schedulers: schedulers
        )
    }

    func testSkipsIfAlreadySucceeded() {
        db.write { kvStore.setHasSucceeded(tx: $0) }

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsIfLinkedDevice() {
        tsAccountManagerMock.isPrimaryDevice = false

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsIfNoLocalIdentifiers() {
        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testFetchesPniIfMissing() {
        let localAci = FutureAci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = FuturePni.randomForTesting()

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.mockWhoAmI = .init(aci: localAci, pni: remotePni, e164: localE164)

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertTrue(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertEqual(remotePni, tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniFetchIfPresent() {
        let localAci = FutureAci.randomForTesting()
        let localPni = FuturePni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testSkipsPniSaveIfMismatchedAci() {
        let localAci = FutureAci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remoteAci = FutureAci.randomForTesting()
        let remotePni = FuturePni.randomForTesting()

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: nil, e164: localE164)
        accountServiceClientMock.mockWhoAmI = .init(aci: remoteAci, pni: remotePni, e164: localE164)

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertTrue(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testCreatesPniKeysWithoutFetchingRemoteIfNoneLocal() {
        let localAci = FutureAci.randomForTesting()
        let localPni = FuturePni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertFalse(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testCreatesPniKeysIfRemoteMissing() {
        let localAci = FutureAci.randomForTesting()
        let localPni = FuturePni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        identityManagerMock.pniPublicKeyData = Data()
        profileFetcherMock.profileFetchResult = .success(nil)

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testCreatesPniKeysIfRemoteDoesNotMatchLocal() {
        let localAci = FutureAci.randomForTesting()
        let localPni = FuturePni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        identityManagerMock.pniPublicKeyData = Data(repeating: 3, count: 12)
        profileFetcherMock.profileFetchResult = .success(Data(repeating: 4, count: 12))

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(profileFetcherMock.completeProfileFetch())
        XCTAssertTrue(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testDoesNotCreatePniKeysIfErrorFetchingRemoteToCompare() {
        let localAci = FutureAci.randomForTesting()
        let localPni = FuturePni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        identityManagerMock.pniPublicKeyData = Data(repeating: 3, count: 12)
        profileFetcherMock.profileFetchResult = .failure(OWSGenericError("whoops"))

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertFalse(db.read { kvStore.hasSucceeded(tx: $0) })
    }

    func testDoesNotCreatePniKeysIfRemoteMatchesLocal() {
        let localAci = FutureAci.randomForTesting()
        let localPni = FuturePni.randomForTesting()
        let localE164 = E164("+17735550199")!

        tsAccountManagerMock.mockIdentifiers = .init(aci: localAci, pni: localPni, e164: localE164)
        identityManagerMock.pniPublicKeyData = Data(repeating: 3, count: 12)
        profileFetcherMock.profileFetchResult = .success(Data(repeating: 3, count: 12))

        db.read { tx in
            _ = learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
        }

        XCTAssertFalse(accountServiceClientMock.completeWhoAmIRequest())
        XCTAssertNil(tsAccountManagerMock.updatedPni)
        XCTAssertTrue(profileFetcherMock.completeProfileFetch())
        XCTAssertFalse(preKeyManagerMock.completeCreatePniKeys())
        XCTAssertTrue(db.read { kvStore.hasSucceeded(tx: $0) })
    }

}

private extension WhoAmIRequestFactory.Responses.WhoAmI {
    init(aci: UntypedServiceId, pni: UntypedServiceId, e164: E164) {
        self.init(aci: aci.uuidValue, pni: pni.uuidValue, e164: e164, usernameHash: nil)
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

private class PreKeyManagerMock: LearnMyOwnPniManagerImpl.Shims.PreKeyManager {
    private var createKeysFuture: Future<Void>?

    /// Completes a mocked operation that is async in the real app. Otherwise,
    /// since tests complete promises synchronously we may get database
    /// re-entrance.
    /// - Returns whether or not a mocked operation was completed.
    func completeCreatePniKeys() -> Bool {
        guard let createKeysFuture else {
            return false
        }

        createKeysFuture.resolve()
        return true
    }

    func createPniIdentityKeyAndUploadPreKeys() -> Promise<Void> {
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

    func fetchPniIdentityPublicKey(localPni: UntypedServiceId) -> Promise<Data?> {
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
    var updatedPni: UntypedServiceId?

    func isPrimaryDevice(tx _: DBReadTransaction) -> Bool {
        return isPrimaryDevice
    }

    func localIdentifiers(tx _: DBReadTransaction) -> LocalIdentifiers? {
        return mockIdentifiers
    }

    func updateLocalIdentifiers(e164 _: E164, aci _: UntypedServiceId, pni: UntypedServiceId, tx _: DBWriteTransaction) {
        updatedPni = pni
    }
}
