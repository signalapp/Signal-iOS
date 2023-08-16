//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class PniHelloWorldManagerTest: XCTestCase {
    private struct TestKeyValueStore {
        static let hasSaidHelloWorldKey = "hasSaidHelloWorld"

        private let kvStore: KeyValueStore

        init(keyValueStoreFactory: KeyValueStoreFactory) {
            kvStore = keyValueStoreFactory.keyValueStore(collection: "PniHelloWorldManagerImpl")
        }

        func hasSaidHelloWorld(tx: DBReadTransaction) -> Bool {
            return kvStore.getBool(Self.hasSaidHelloWorldKey, defaultValue: false, transaction: tx)
        }

        func setHasSaidHelloWorld(tx: DBWriteTransaction) {
            kvStore.setBool(true, key: Self.hasSaidHelloWorldKey, transaction: tx)
        }
    }

    private var identityManagerMock: IdentityManagerMock!
    private var networkManagerMock: NetworkManagerMock!
    private var pniDistributionParameterBuilderMock: PniDistributionParamaterBuilderMock!
    private var pniSignedPreKeyStoreMock: MockSignalSignedPreKeyStore!
    private var pniKyberPreKeyStoreMock: MockKyberPreKeyStore!
    private var profileManagerMock: ProfileManagerMock!
    private var signalRecipientStoreMock: SignalRecipientStoreMock!
    private var tsAccountManagerMock: TSAccountManagerMock!

    private var kvStore: TestKeyValueStore!
    private let db = MockDB()

    private var pniHelloWorldManager: PniHelloWorldManager!

    override func setUp() {
        identityManagerMock = .init()
        networkManagerMock = .init()
        pniDistributionParameterBuilderMock = .init()
        pniSignedPreKeyStoreMock = .init()
        pniKyberPreKeyStoreMock = .init(dateProvider: Date.provider)
        profileManagerMock = .init()
        signalRecipientStoreMock = .init()
        tsAccountManagerMock = .init()

        let kvStoreFactory = InMemoryKeyValueStoreFactory()
        kvStore = TestKeyValueStore(keyValueStoreFactory: kvStoreFactory)

        let schedulers = TestSchedulers(scheduler: TestScheduler())
        schedulers.scheduler.start()

        pniHelloWorldManager = PniHelloWorldManagerImpl(
            database: db,
            identityManager: identityManagerMock,
            keyValueStoreFactory: kvStoreFactory,
            networkManager: networkManagerMock,
            pniDistributionParameterBuilder: pniDistributionParameterBuilderMock,
            pniSignedPreKeyStore: pniSignedPreKeyStoreMock,
            pniKyberPreKeyStore: pniKyberPreKeyStoreMock,
            profileManager: profileManagerMock,
            schedulers: schedulers,
            signalRecipientStore: signalRecipientStoreMock,
            tsAccountManager: tsAccountManagerMock
        )
    }

    private func setMocksForHappyPath() {
        tsAccountManagerMock.isPrimaryDevice = true
        tsAccountManagerMock.localIdentifiers = .mock
        signalRecipientStoreMock.localAccountId = "foobar"
        signalRecipientStoreMock.deviceIds = [1, 2, 3]
        profileManagerMock.isPniCapable = true

        let keyPair = Curve25519.generateKeyPair()
        identityManagerMock.identityKeyPair = keyPair
        pniSignedPreKeyStoreMock.setCurrentSignedPreKey(
            pniSignedPreKeyStoreMock.generateSignedPreKey(
                signedBy: keyPair
            )
        )
        db.write { tx in
            let key = try! pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: keyPair, tx: tx)
            try! pniKyberPreKeyStoreMock.storeLastResortPreKeyAndMarkAsCurrent(record: key, tx: tx)
        }

        pniDistributionParameterBuilderMock.buildOutcomes = [.success]
        networkManagerMock.requestShouldSucceed = true
    }

    func testHappyPath() {
        setMocksForHappyPath()

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3]])
        XCTAssertTrue(networkManagerMock.completeRequest())
        XCTAssertTrue(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfLinkedDevice() {
        setMocksForHappyPath()
        tsAccountManagerMock.isPrimaryDevice = false

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(networkManagerMock.completeRequest())
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfAlreadyCompleted() {
        setMocksForHappyPath()
        db.write { kvStore.setHasSaidHelloWorld(tx: $0) }

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(networkManagerMock.completeRequest())
        XCTAssertTrue(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingLocalIdentifiers() {
        setMocksForHappyPath()
        tsAccountManagerMock.localIdentifiers = nil

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(networkManagerMock.completeRequest())
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingLocalPni() {
        setMocksForHappyPath()
        tsAccountManagerMock.localIdentifiers = .missingPni

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(networkManagerMock.completeRequest())
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingAccountAndDeviceIds() {
        setMocksForHappyPath()
        signalRecipientStoreMock.localAccountId = nil
        signalRecipientStoreMock.deviceIds = nil

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(networkManagerMock.completeRequest())
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfNotPniCapable() {
        setMocksForHappyPath()
        profileManagerMock.isPniCapable = false

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(networkManagerMock.completeRequest())
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingPniKeyParameters() {
        setMocksForHappyPath()
        identityManagerMock.identityKeyPair = nil
        pniSignedPreKeyStoreMock.setCurrentSignedPreKey(nil)

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(networkManagerMock.completeRequest())
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsRequestIfBuildFailed() {
        setMocksForHappyPath()
        pniDistributionParameterBuilderMock.buildOutcomes = [.failure]

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3]])
        XCTAssertFalse(networkManagerMock.completeRequest())
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testDoesNotSaveIfRequestFailed() {
        setMocksForHappyPath()
        networkManagerMock.requestShouldSucceed = false

        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3]])
        XCTAssertTrue(networkManagerMock.completeRequest())
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }
}

private extension LocalIdentifiers {
    static var mock: LocalIdentifiers {
        return .withPni(pni: Pni.randomForTesting())
    }

    static var missingPni: LocalIdentifiers {
        return .withPni(pni: nil)
    }

    private static func withPni(pni: Pni?) -> LocalIdentifiers {
        return LocalIdentifiers(aci: Aci.randomForTesting(), pni: pni, e164: E164("+17735550199")!)
    }
}

// MARK: - Mocks

// MARK: IdentityManager

private class IdentityManagerMock: _PniHelloWorldManagerImpl_IdentityManager_Shim {
    var identityKeyPair: ECKeyPair?

    func pniIdentityKeyPair(tx: DBReadTransaction) -> ECKeyPair? {
        return identityKeyPair
    }
}

// MARK: NetworkManager

private class NetworkManagerMock: _PniHelloWorldManagerImpl_NetworkManager_Shim {
    var requestShouldSucceed: Bool?
    private var requestFuture: Future<Void>?

    /// Completes a mocked operation that is async in the real app. Otherwise,
    /// since tests complete promises synchronously we may get database
    /// re-entrance.
    /// - Returns whether or not a mocked operation was completed.
    func completeRequest() -> Bool {
        guard let requestFuture else {
            return false
        }

        guard let requestShouldSucceed else {
            XCTFail("Missing mock outcome!")
            return false
        }

        if requestShouldSucceed {
            requestFuture.resolve()
        } else {
            requestFuture.reject(OWSGenericError("Request failed!"))
        }

        return true
    }

    func makeHelloWorldRequest(pniDistributionParameters _: PniDistribution.Parameters) -> Promise<Void> {
        guard requestFuture == nil else {
            XCTFail("Request already in flight!")
            return Promise(error: OWSGenericError("Request already in flight!"))
        }

        let (promise, future) = Promise<Void>.pending()
        requestFuture = future
        return promise
    }
}

// MARK: PniDistributionParameterBuilder

private class PniDistributionParamaterBuilderMock: PniDistributionParamaterBuilder {
    enum BuildOutcome {
        case success
        case failure
    }

    var buildOutcomes: [BuildOutcome] = []
    var buildRequestedDeviceIds: [[UInt32]] = []

    func buildPniDistributionParameters(
        localAci _: UntypedServiceId,
        localAccountId _: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: SignalServiceKit.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) -> Guarantee<PniDistribution.ParameterGenerationResult> {
        guard let buildOutcome = buildOutcomes.first else {
            XCTFail("Missing build outcome!")
            return .value(.failure)
        }

        buildOutcomes = Array(buildOutcomes.dropFirst())

        buildRequestedDeviceIds.append(localUserAllDeviceIds)

        switch buildOutcome {
        case .success:
            return .value(.success(.mock(
                pniIdentityKeyPair: localPniIdentityKeyPair,
                localDeviceId: localDeviceId,
                localDevicePniSignedPreKey: localDevicePniSignedPreKey,
                localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKey,
                localDevicePniRegistrationId: localDevicePniRegistrationId
            )))
        case .failure:
            return .value(.failure)
        }
    }
}

// MARK: ProfileManager

private class ProfileManagerMock: _PniHelloWorldManagerImpl_ProfileManager_Shim {
    var isPniCapable: Bool = false

    func isLocalProfilePniCapable() -> Bool {
        return isPniCapable
    }
}

// MARK: SignalRecipientStore

private class SignalRecipientStoreMock: _PniHelloWorldManagerImpl_SignalRecipientStore_Shim {
    var localAccountId: String?
    var deviceIds: [UInt32]?

    func localAccountAndDeviceIds(
        localAci: UntypedServiceId,
        tx: DBReadTransaction
    ) -> (accountId: String, deviceIds: [UInt32])? {
        guard let localAccountId, let deviceIds else {
            return nil
        }

        return (localAccountId, deviceIds)
    }
}

// MARK: TSAccountManager

private class TSAccountManagerMock: _PniHelloWorldManagerImpl_TSAccountManager_Shim {
    var isPrimaryDevice: Bool = false
    var localIdentifiers: LocalIdentifiers?

    func isPrimaryDevice(tx: DBReadTransaction) -> Bool {
        return isPrimaryDevice
    }

    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return localIdentifiers
    }

    func localDeviceId(tx: DBReadTransaction) -> UInt32 {
        return 1
    }

    func getPniRegistrationId(tx: DBWriteTransaction) -> UInt32 {
        return UInt32.random(in: 0..<500)
    }
}
