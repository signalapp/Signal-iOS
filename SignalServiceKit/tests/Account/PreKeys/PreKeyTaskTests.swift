//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import XCTest
@testable import SignalServiceKit

final class PreKeyTaskTests: SSKBaseTest {

    private var mockTSAccountManager: MockTSAccountManager!
    private var mockIdentityManager: MockIdentityManager!
    private var mockIdentityKeyMismatchManager: PreKeyTaskManager.Mocks.IdentityKeyMismatchManager!
    private var mockAPIClient: PreKeyTaskManager.Mocks.APIClient!
    private var mockDateProvider: PreKeyTaskManager.Mocks.DateProvider!
    private var mockDb: InMemoryDB!

    private var taskManager: PreKeyTaskManager!

    private var mockAciProtocolStore: SignalProtocolStore!
    private var mockPniProtocolStore: SignalProtocolStore!
    private var mockProtocolStoreManager: SignalProtocolStoreManager!
    private var mockPreKeyStore: SignalServiceKit.PreKeyStore!

    override func setUp() {
        super.setUp()

        let testContext = (CurrentAppContext() as! TestAppContext)
        testContext.shouldProcessIncomingMessages = false

        let recipientDbTable = RecipientDatabaseTable()
        let recipientFetcher = RecipientFetcher(
            recipientDatabaseTable: recipientDbTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let recipientIdFinder = RecipientIdFinder(
            recipientDatabaseTable: recipientDbTable,
            recipientFetcher: recipientFetcher,
        )
        mockIdentityManager = .init(recipientIdFinder: recipientIdFinder)
        mockTSAccountManager = .init()
        mockIdentityKeyMismatchManager = .init()
        mockAPIClient = .init()
        mockDateProvider = .init()
        mockDb = InMemoryDB()
        let sessionStore = SignalServiceKit.SessionStore()

        mockPreKeyStore = PreKeyStore()
        mockAciProtocolStore = .build(
            dateProvider: mockDateProvider.targetDate,
            identity: .aci,
            preKeyStore: mockPreKeyStore,
            recipientIdFinder: recipientIdFinder,
            sessionStore: sessionStore,
        )
        mockPniProtocolStore = .build(
            dateProvider: mockDateProvider.targetDate,
            identity: .pni,
            preKeyStore: mockPreKeyStore,
            recipientIdFinder: recipientIdFinder,
            sessionStore: sessionStore,
        )
        mockProtocolStoreManager = SignalProtocolStoreManager(
            aciProtocolStore: mockAciProtocolStore,
            pniProtocolStore: mockPniProtocolStore,
            preKeyStore: mockPreKeyStore,
            sessionStore: sessionStore,
        )

        taskManager = PreKeyTaskManager(
            apiClient: mockAPIClient,
            dateProvider: mockDateProvider.targetDate,
            db: mockDb,
            identityKeyMismatchManager: mockIdentityKeyMismatchManager,
            identityManager: mockIdentityManager,
            messageProcessor: SSKEnvironment.shared.messageProcessorRef,
            protocolStoreManager: mockProtocolStoreManager,
            remoteConfigProvider: MockRemoteConfigProvider(),
            tsAccountManager: mockTSAccountManager,
        )
    }

    override func tearDown() {
        mockAPIClient.setPreKeysResult.ensureUnset()
        super.tearDown()
    }

    private func aciPreKeyCount() -> Int {
        return mockDb.read { tx in
            return try! mockPreKeyStore.aciStore.fetchCount(in: .oneTime, isOneTime: true, tx: tx)
        }
    }

    private func aciSignedPreKeyCount() -> Int {
        return mockDb.read { tx in
            return try! mockPreKeyStore.aciStore.fetchCount(in: .signed, isOneTime: false, tx: tx)
        }
    }

    private func aciKyberOneTimePreKeyCount() -> Int {
        return mockDb.read { tx in
            return try! mockPreKeyStore.aciStore.fetchCount(in: .kyber, isOneTime: true, tx: tx)
        }
    }

    private func aciKyberLastResortPreKeyCount() -> Int {
        return mockDb.read { tx in
            return try! mockPreKeyStore.aciStore.fetchCount(in: .kyber, isOneTime: false, tx: tx)
        }
    }

    //
    //
    // MARK: - Create PreKey Tests

    //
    //

    func testCreateAll() async throws {
        mockAPIClient.setPreKeysResult = .value(())
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()

        _ = try await taskManager.refresh(identity: .aci, targets: .all, force: true, auth: .implicit())

        // Validate
        XCTAssertEqual(mockAPIClient.preKeyRecords?.count, 100)
        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNotNil(mockAPIClient.pqLastResortPreKeyRecord)
        XCTAssertNotNil(mockAPIClient.pqPreKeyRecords)
        XCTAssertEqual(mockAPIClient.pqPreKeyRecords?.count, 100)
    }

    func testCreateSignedPreKeyOnly() async throws {
        mockAPIClient.setPreKeysResult = .value(())
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(aciPreKeyCount(), 0)
        XCTAssertEqual(aciSignedPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .signedPreKey, force: true, auth: .implicit())

        // Validate
        XCTAssertEqual(aciPreKeyCount(), 0)
        XCTAssertEqual(aciSignedPreKeyCount(), 1)

        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNil(mockAPIClient.preKeyRecords)
        XCTAssertNil(mockAPIClient.pqPreKeyRecords)
        XCTAssertNil(mockAPIClient.pqLastResortPreKeyRecord)
    }

    func testCreatePreKeyOnly() async throws {
        mockAPIClient.setPreKeysResult = .value(())
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(aciPreKeyCount(), 0)
        XCTAssertEqual(aciSignedPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .oneTimePreKey, force: true, auth: .implicit())

        // Validate
        XCTAssertEqual(aciPreKeyCount(), 100)
        XCTAssertEqual(aciSignedPreKeyCount(), 0)

        XCTAssertEqual(mockAPIClient.preKeyRecords?.count, 100)
        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNil(mockAPIClient.pqPreKeyRecords)
        XCTAssertNil(mockAPIClient.pqLastResortPreKeyRecord)
        XCTAssertNotNil(mockAPIClient.preKeyRecords)
    }

    // Test that the IdentityMananger keypair makes it through to the
    // service client
    func testMockPreKeyTaskCreateWithExistingIdentityKey() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        XCTAssertEqual(aciPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, force: true, auth: .implicit())

        XCTAssertEqual(mockAPIClient.preKeyRecords?.count, 100)
        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNotNil(mockAPIClient.pqPreKeyRecords)
        XCTAssertEqual(mockAPIClient.pqPreKeyRecords?.count, 100)
        XCTAssertNotNil(mockAPIClient.pqLastResortPreKeyRecord)
    }

    func testMockCreatePreKeyOnlyWithExisting() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 100
        XCTAssertEqual(aciPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .oneTimePreKey, force: true, auth: .implicit())

        XCTAssertEqual(mockAPIClient.preKeyRecords?.count, 100)
        XCTAssertEqual(aciSignedPreKeyCount(), 0)
        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNil(mockAPIClient.pqPreKeyRecords)
        XCTAssertNil(mockAPIClient.pqLastResortPreKeyRecord)
    }

    func testCreatePqKeysOnly() async throws {
        mockAPIClient.setPreKeysResult = .value(())
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(aciKyberOneTimePreKeyCount(), 0)
        XCTAssertEqual(aciKyberLastResortPreKeyCount(), 0)

        _ = try await taskManager.refresh(
            identity: .aci,
            targets: [.lastResortPqPreKey, .oneTimePqPreKey],
            force: true,
            auth: .implicit(),
        )

        // Validate
        XCTAssertEqual(aciKyberOneTimePreKeyCount(), 100)
        XCTAssertEqual(aciKyberLastResortPreKeyCount(), 1)

        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNil(mockAPIClient.preKeyRecords)
        XCTAssertNotNil(mockAPIClient.pqPreKeyRecords)
        XCTAssertNotNil(mockAPIClient.pqLastResortPreKeyRecord)
    }

    //
    //
    // MARK: - Refresh Tests

    //
    //

    func testMockPreKeyTaskUpdate() async throws {
        let aciKeyPair = ECKeyPair.generateKeyPair()
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()

        let originalSignedPreKey = SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: aciKeyPair.keyPair.privateKey)
        mockDb.write { tx in
            mockAciProtocolStore.signedPreKeyStore.storeSignedPreKey(originalSignedPreKey, tx: tx)
        }

        mockAPIClient.setPreKeysResult = .value(())
        mockAPIClient.currentPreKeyCount = 0
        mockAPIClient.currentPqPreKeyCount = 0

        mockDateProvider.currentDate = Date(timeIntervalSinceNow: PreKeyTaskManager.Constants.SignedPreKeyRotationTime + 1)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertEqual(aciSignedPreKeyCount(), 2)
    }

    func testMockPreKeyTaskNoUpdate() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        let records = mockDb.write { tx in
            let preKeyIds = mockAciProtocolStore.preKeyStore.allocatePreKeyIds(tx: tx)
            let records = PreKeyStoreImpl.generatePreKeyRecords(forPreKeyIds: preKeyIds)
            mockAciProtocolStore.preKeyStore.storePreKeyRecords(records, tx: tx)
            return records
        }

        mockAPIClient.currentPreKeyCount = 50
        mockAPIClient.currentPqPreKeyCount = 0
        XCTAssertEqual(aciPreKeyCount(), 100)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(aciPreKeyCount(), 100)
        mockDb.read { tx in
            for record in records {
                XCTAssertNotNil(mockPreKeyStore.aciStore.fetchPreKey(in: .oneTime, for: record.id, tx: tx))
            }
        }
        XCTAssertNil(mockAPIClient.preKeyRecords)
    }

    func testMockUpdateFailNoIdentity() async throws {
        XCTAssertEqual(aciPreKeyCount(), 0)
        mockAPIClient.currentPreKeyCount = 0
        mockAPIClient.currentPqPreKeyCount = 0

        do {
            try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())
            XCTFail("Expected failure, but returned success")
        } catch let error {
            switch error {
            case PreKeyTaskManager.Error.noIdentityKey:
                XCTAssertNil(self.mockIdentityManager.identityKeyPairs[.aci])
            default:
                XCTFail("Unexpected error")
            }
        }

        XCTAssertEqual(aciPreKeyCount(), 0)
        XCTAssertNil(mockAPIClient.preKeyRecords)
    }

    func testMockUpdateSkipSignedPreKey() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 50
        mockAPIClient.currentPqPreKeyCount = 0
        XCTAssertEqual(aciPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(aciPreKeyCount(), 0)
        XCTAssertNil(mockAPIClient.preKeyRecords)
    }

    //
    //
    // MARK: - Force Refresh Tests

    //
    //

    func testRefreshNoUpdatesNeeded() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 100
        mockAPIClient.currentPqPreKeyCount = 100
        mockDb.write { tx in
            mockAciProtocolStore.signedPreKeyStore.setLastSuccessfulRotationDate(
                mockDateProvider.currentDate,
                tx: tx,
            )
        }

        XCTAssertEqual(aciPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(aciPreKeyCount(), 0)
        XCTAssertEqual(aciSignedPreKeyCount(), 0)

        XCTAssertNil(mockAPIClient.preKeyRecords)
        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
    }

    func testForceRefreshAll() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 100
        mockDb.write { tx in
            mockAciProtocolStore.signedPreKeyStore.setLastSuccessfulRotationDate(
                mockDateProvider.currentDate,
                tx: tx,
            )
        }

        XCTAssertEqual(aciPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, force: true, auth: .implicit())

        XCTAssertEqual(aciPreKeyCount(), 100)
        XCTAssertEqual(aciSignedPreKeyCount(), 1)

        XCTAssertNotNil(mockAPIClient.preKeyRecords)
        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
    }

    func testForceRefreshOnlyPreKeys() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 100
        XCTAssertEqual(aciPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .oneTimePreKey, force: true, auth: .implicit())

        XCTAssertEqual(aciPreKeyCount(), 100)
        XCTAssertEqual(aciSignedPreKeyCount(), 0)

        XCTAssertNotNil(mockAPIClient.preKeyRecords)
        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
    }

    //
    // PNI
    //

    func test422WhileSettingKeysReportsSuspectedPniIdentityKeyIssue() async {
        mockTSAccountManager.registrationStateMock = { .provisioned }
        mockIdentityManager.identityKeyPairs[.pni] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .error(OWSHTTPError.serviceResponse(.init(
            requestUrl: URL(string: "https://example.com")!,
            responseStatus: 422,
            responseHeaders: HttpHeaders(),
            responseData: nil,
        )))
        var didValidateIdentityKey = false
        mockIdentityKeyMismatchManager.validateIdentityKeyMock = { _ in
            didValidateIdentityKey = true
        }

        _ = try? await taskManager.refresh(identity: .pni, targets: .all, force: true, auth: .implicit())

        // Validate
        XCTAssertTrue(didValidateIdentityKey)
    }

    //
    // Test validation
    //

    func testSignedPreKeyExpired() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockDateProvider.currentDate = Date().addingTimeInterval(PreKeyTaskManager.Constants.SignedPreKeyRotationTime + 1)

        _ = try await taskManager.refresh(identity: .aci, targets: .signedPreKey, auth: .implicit())

        XCTAssertEqual(aciSignedPreKeyCount(), 1)
        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
    }

    func testRefreshOnlyPreKeysBasedOnCount() async throws {
        mockIdentityManager.identityKeyPairs[.aci] = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 9
        mockAPIClient.currentPqPreKeyCount = 0
        XCTAssertEqual(aciPreKeyCount(), 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        XCTAssertEqual(aciPreKeyCount(), 100)
        XCTAssertEqual(aciSignedPreKeyCount(), 0)

        XCTAssertNotNil(mockAPIClient.preKeyRecords)
        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
    }

}
