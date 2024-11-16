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

        init() {
            kvStore = KeyValueStore(collection: "PniHelloWorldManagerImpl")
        }

        func hasSaidHelloWorld(tx: DBReadTransaction) -> Bool {
            return kvStore.getBool(Self.hasSaidHelloWorldKey, defaultValue: false, transaction: tx)
        }

        func setHasSaidHelloWorld(tx: DBWriteTransaction) {
            kvStore.setBool(true, key: Self.hasSaidHelloWorldKey, transaction: tx)
        }
    }

    private var identityManagerMock: MockIdentityManager!
    private var networkManagerMock: NetworkManagerMock!
    private var pniDistributionParameterBuilderMock: PniDistributionParamaterBuilderMock!
    private var pniSignedPreKeyStoreMock: MockSignalSignedPreKeyStore!
    private var pniKyberPreKeyStoreMock: MockKyberPreKeyStore!
    private var recipientDatabaseTableMock: MockRecipientDatabaseTable!
    private var tsAccountManagerMock: MockTSAccountManager!

    private let db = InMemoryDB()
    private var kvStore: TestKeyValueStore!
    private var testScheduler: TestScheduler!

    private var pniHelloWorldManager: PniHelloWorldManager!

    override func setUp() {
        let recipientDatabaseTable = MockRecipientDatabaseTable()
        let recipientFetcher = RecipientFetcherImpl(recipientDatabaseTable: recipientDatabaseTable)
        identityManagerMock = .init(recipientIdFinder: RecipientIdFinder(
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher
        ))
        networkManagerMock = .init()
        pniDistributionParameterBuilderMock = .init()
        pniSignedPreKeyStoreMock = .init()
        pniKyberPreKeyStoreMock = .init(dateProvider: Date.provider)
        recipientDatabaseTableMock = .init()
        tsAccountManagerMock = .init()

        kvStore = TestKeyValueStore()

        testScheduler = TestScheduler()
        let schedulers = TestSchedulers(scheduler: testScheduler)

        pniHelloWorldManager = PniHelloWorldManagerImpl(
            database: db,
            identityManager: identityManagerMock,
            networkManager: networkManagerMock,
            pniDistributionParameterBuilder: pniDistributionParameterBuilderMock,
            pniSignedPreKeyStore: pniSignedPreKeyStoreMock,
            pniKyberPreKeyStore: pniKyberPreKeyStoreMock,
            recipientDatabaseTable: recipientDatabaseTableMock,
            schedulers: schedulers,
            tsAccountManager: tsAccountManagerMock
        )
    }

    override func tearDown() {
        networkManagerMock.requestResult.ensureUnset()
    }

    private func runRunRun() {
        db.write { tx in
            pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
        }

        testScheduler.runUntilIdle()
    }

    private func setMocksForHappyPath(
        includingNetworkRequest mockNetworkRequest: Bool = false
    ) {
        let localIdentifiers = LocalIdentifiers.forUnitTests
        tsAccountManagerMock.registrationStateMock = { .registered }
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers }
        db.write { tx in
            recipientDatabaseTableMock.insertRecipient(SignalRecipient(
                aci: localIdentifiers.aci,
                pni: localIdentifiers.pni,
                phoneNumber: E164(localIdentifiers.phoneNumber)!,
                deviceIds: [1, 2, 3]
            ), transaction: tx)
        }

        let keyPair = ECKeyPair.generateKeyPair()
        identityManagerMock.identityKeyPairs[.pni] = keyPair

        pniDistributionParameterBuilderMock.buildOutcomes = [.success]

        if mockNetworkRequest {
            networkManagerMock.requestResult = .value(())
        }
    }

    func testHappyPath() {
        setMocksForHappyPath(includingNetworkRequest: true)

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3]])
        XCTAssertTrue(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testGeneratesIfMissingPniIdentityKey() {
        setMocksForHappyPath(includingNetworkRequest: true)
        identityManagerMock.identityKeyPairs[.pni] = nil

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3]])
        XCTAssertTrue(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfLinkedDevice() {
        setMocksForHappyPath()
        tsAccountManagerMock.registrationStateMock = { .provisioned }

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfAlreadyCompleted() {
        setMocksForHappyPath()
        db.write { kvStore.setHasSaidHelloWorld(tx: $0) }

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertTrue(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingLocalIdentifiers() {
        setMocksForHappyPath()
        tsAccountManagerMock.localIdentifiersMock = { nil }

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingLocalPni() {
        setMocksForHappyPath()
        let localIdentifiers = tsAccountManagerMock.localIdentifiersMock()!
        tsAccountManagerMock.localIdentifiersMock = {
            LocalIdentifiers(aci: localIdentifiers.aci, pni: nil, phoneNumber: localIdentifiers.phoneNumber)
        }

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingAccountAndDeviceIds() {
        setMocksForHappyPath()
        recipientDatabaseTableMock.recipientTable = [:]

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsRequestIfBuildFailed() {
        setMocksForHappyPath()
        pniDistributionParameterBuilderMock.buildOutcomes = [.failure]

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3]])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testDoesNotSaveIfRequestFailed() {
        setMocksForHappyPath()
        networkManagerMock.requestResult = .error()

        runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3]])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }
}

// MARK: - Mocks

// MARK: NetworkManager

private class NetworkManagerMock: _PniHelloWorldManagerImpl_NetworkManager_Shim {
    var requestResult: ConsumableMockPromise<Void> = .unset

    func makeHelloWorldRequest(pniDistributionParameters _: PniDistribution.Parameters) -> Promise<Void> {
        return requestResult.consumeIntoPromise()
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
        localAci _: Aci,
        localRecipientUniqueId _: String,
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
