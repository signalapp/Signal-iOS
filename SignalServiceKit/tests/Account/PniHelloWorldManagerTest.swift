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

        pniHelloWorldManager = PniHelloWorldManagerImpl(
            db: db,
            identityManager: identityManagerMock,
            networkManager: networkManagerMock,
            pniDistributionParameterBuilder: pniDistributionParameterBuilderMock,
            pniSignedPreKeyStore: pniSignedPreKeyStoreMock,
            pniKyberPreKeyStore: pniKyberPreKeyStoreMock,
            recipientDatabaseTable: recipientDatabaseTableMock,
            tsAccountManager: tsAccountManagerMock
        )
    }

    private func runRunRun() async throws {
        try await pniHelloWorldManager.sayHelloWorldIfNecessary()
    }

    private func setMocksForHappyPath() async {
        let localIdentifiers = LocalIdentifiers.forUnitTests
        tsAccountManagerMock.registrationStateMock = { .registered }
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers }
        await db.awaitableWrite { tx in
            recipientDatabaseTableMock.insertRecipient(SignalRecipient(
                aci: localIdentifiers.aci,
                pni: localIdentifiers.pni,
                phoneNumber: E164(localIdentifiers.phoneNumber)!,
                deviceIds: [1, 2, 3].map(DeviceId.init(rawValue:))
            ), transaction: tx)
        }

        let keyPair = ECKeyPair.generateKeyPair()
        identityManagerMock.identityKeyPairs[.pni] = keyPair

        pniDistributionParameterBuilderMock.buildOutcomes = [.success]
    }

    func testHappyPath() async throws {
        await setMocksForHappyPath()
        var didMakeNetworkRequest = false
        networkManagerMock.makeHelloWorldRequestMock = { _ in didMakeNetworkRequest = true }

        try await runRunRun()

        XCTAssert(didMakeNetworkRequest)
        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3].map(DeviceId.init(rawValue:))])
        XCTAssertTrue(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testGeneratesIfMissingPniIdentityKey() async throws {
        await setMocksForHappyPath()
        var didMakeNetworkRequest = false
        networkManagerMock.makeHelloWorldRequestMock = { _ in didMakeNetworkRequest = true }
        identityManagerMock.identityKeyPairs[.pni] = nil

        try await runRunRun()

        XCTAssert(didMakeNetworkRequest)
        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3].map(DeviceId.init(rawValue:))])
        XCTAssertTrue(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfLinkedDevice() async throws {
        await setMocksForHappyPath()
        tsAccountManagerMock.registrationStateMock = { .provisioned }

        try await runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfAlreadyCompleted() async throws {
        await setMocksForHappyPath()
        db.write { kvStore.setHasSaidHelloWorld(tx: $0) }

        try await runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertTrue(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingLocalIdentifiers() async {
        await setMocksForHappyPath()
        tsAccountManagerMock.localIdentifiersMock = { nil }

        try? await runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingLocalPni() async {
        await setMocksForHappyPath()
        let localIdentifiers = tsAccountManagerMock.localIdentifiersMock()!
        tsAccountManagerMock.localIdentifiersMock = {
            LocalIdentifiers(aci: localIdentifiers.aci, pni: nil, phoneNumber: localIdentifiers.phoneNumber)
        }

        try? await runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsIfMissingAccountAndDeviceIds() async {
        await setMocksForHappyPath()
        recipientDatabaseTableMock.recipientTable = [:]

        try? await runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testSkipsRequestIfBuildFailed() async {
        await setMocksForHappyPath()
        pniDistributionParameterBuilderMock.buildOutcomes = [.failure]

        try? await runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3].map(DeviceId.init(rawValue:))])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }

    func testDoesNotSaveIfRequestFailed() async {
        await setMocksForHappyPath()
        networkManagerMock.makeHelloWorldRequestMock = { _ in throw OWSGenericError("") }

        try? await runRunRun()

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedDeviceIds, [[1, 2, 3].map(DeviceId.init(rawValue:))])
        XCTAssertFalse(db.read { kvStore.hasSaidHelloWorld(tx: $0) })
    }
}

// MARK: - Mocks

// MARK: NetworkManager

private class NetworkManagerMock: _PniHelloWorldManagerImpl_NetworkManager_Shim {
    var makeHelloWorldRequestMock: ((_ pniDistributionParameters: PniDistribution.Parameters) async throws -> Void)!

    func makeHelloWorldRequest(pniDistributionParameters: PniDistribution.Parameters) async throws {
        return try await makeHelloWorldRequestMock!(pniDistributionParameters)
    }
}

// MARK: PniDistributionParameterBuilder

private class PniDistributionParamaterBuilderMock: PniDistributionParamaterBuilder {
    enum BuildOutcome {
        case success
        case failure
    }

    var buildOutcomes: [BuildOutcome] = []
    var buildRequestedDeviceIds: [[DeviceId]] = []

    func buildPniDistributionParameters(
        localAci _: Aci,
        localRecipientUniqueId _: String,
        localDeviceId: DeviceId,
        localUserAllDeviceIds: [DeviceId],
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: SignalServiceKit.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) async throws -> PniDistribution.Parameters {
        let buildOutcome = buildOutcomes.first!
        buildOutcomes = Array(buildOutcomes.dropFirst())

        buildRequestedDeviceIds.append(localUserAllDeviceIds)

        switch buildOutcome {
        case .success:
            return .mock(
                pniIdentityKeyPair: localPniIdentityKeyPair,
                localDeviceId: localDeviceId,
                localDevicePniSignedPreKey: localDevicePniSignedPreKey,
                localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKey,
                localDevicePniRegistrationId: localDevicePniRegistrationId
            )
        case .failure:
            throw OWSGenericError("")
        }
    }
}
