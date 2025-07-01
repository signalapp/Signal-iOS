//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import XCTest
@testable import SignalServiceKit

final class PreKeyTaskTests: SSKBaseTest {

    private var mockTSAccountManager: MockTSAccountManager!
    private var mockIdentityManager: PreKey.Mocks.IdentityManager!
    private var mockIdentityKeyMismatchManager: PreKey.Mocks.IdentityKeyMismatchManager!
    private var mockAPIClient: PreKey.Mocks.APIClient!
    private var mockDateProvider: PreKey.Mocks.DateProvider!
    private var mockDb: InMemoryDB!

    private var taskManager: PreKeyTaskManager!

    private var mockAciProtocolStore: MockSignalProtocolStore!
    private var mockPniProtocolStore: MockSignalProtocolStore!
    private var mockProtocolStoreManager: SignalProtocolStoreManager!

    override func setUp() {
        super.setUp()

        let testContext = (CurrentAppContext() as! TestAppContext)
        testContext.shouldProcessIncomingMessages = false

        mockTSAccountManager = .init()
        mockIdentityManager = .init()
        mockIdentityKeyMismatchManager = .init()
        mockAPIClient = .init()
        mockDateProvider = .init()
        mockDb = InMemoryDB()

        mockAciProtocolStore = .init(identity: .aci)
        mockPniProtocolStore = .init(identity: .pni)
        mockProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: mockAciProtocolStore,
            pniProtocolStore: mockPniProtocolStore
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
            tsAccountManager: mockTSAccountManager
        )
    }

    override func tearDown() {
        mockAPIClient.setPreKeysResult.ensureUnset()
        super.tearDown()
    }

    private func aciPreKeyCount() -> Int {
        return mockDb.read { tx in
            return mockAciProtocolStore.mockPreKeyStore.count(tx: tx)
        }
    }

    private func aciSignedPreKeyCount() -> Int {
        return mockDb.read { tx in
            return mockAciProtocolStore.mockSignedPreKeyStore.count(tx: tx)
        }
    }

    private func aciKyberOneTimePreKeyCount() -> Int {
        return mockDb.read { tx in
            return mockAciProtocolStore.mockKyberPreKeyStore.count(isLastResort: false, tx: tx)
        }
    }

    private func aciKyberLastResortPreKeyCount() -> Int {
        return mockDb.read { tx in
            return mockAciProtocolStore.mockKyberPreKeyStore.count(isLastResort: true, tx: tx)
        }
    }

    //
    //
    // MARK: - Create PreKey Tests
    //
    //

    func testCreateAll() async throws {
        mockAPIClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(aciKyberOneTimePreKeyCount(), 0)
        XCTAssertEqual(aciKyberLastResortPreKeyCount(), 0)

        _ = try await taskManager.refresh(
            identity: .aci,
            targets: [.lastResortPqPreKey, .oneTimePqPreKey],
            force: true,
            auth: .implicit()
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
        mockIdentityManager.aciKeyPair = aciKeyPair

        let originalSignedPreKey = SignedPreKeyStoreImpl.generateSignedPreKey(signedBy: aciKeyPair)
        mockDb.write { tx in
            mockAciProtocolStore.mockSignedPreKeyStore.storeSignedPreKey(
                originalSignedPreKey.id,
                signedPreKeyRecord: originalSignedPreKey,
                tx: tx
            )
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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        let records = mockDb.write { tx in
            let records = mockAciProtocolStore.mockPreKeyStore.generatePreKeyRecords(tx: tx)
            mockAciProtocolStore.mockPreKeyStore.storePreKeyRecords(records, tx: tx)
            return records
        }

        mockAPIClient.currentPreKeyCount = 50
        mockAPIClient.currentPqPreKeyCount = 0
        XCTAssertEqual(aciPreKeyCount(), 100)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(aciPreKeyCount(), 100)
        mockDb.read { tx in
            for record in records {
                XCTAssertNotNil(mockAciProtocolStore.mockPreKeyStore.loadPreKey(record.id, transaction: tx))
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
                XCTAssertNil(self.mockIdentityManager.aciKeyPair)
            default:
                XCTFail("Unexpected error")
            }
        }

        XCTAssertEqual(aciPreKeyCount(), 0)
        XCTAssertNil(mockAPIClient.preKeyRecords)
    }

    func testMockUpdateSkipSignedPreKey() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 100
        mockAPIClient.currentPqPreKeyCount = 100
        mockDb.write { tx in
            mockAciProtocolStore.mockSignedPreKeyStore.setLastSuccessfulRotationDate(
                mockDateProvider.currentDate,
                tx: tx
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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 100
        mockDb.write { tx in
            mockAciProtocolStore.mockSignedPreKeyStore.setLastSuccessfulRotationDate(
                mockDateProvider.currentDate,
                tx: tx
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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
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
        mockIdentityManager.pniKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .error(OWSHTTPError.forServiceResponse(
            requestUrl: URL(string: "https://example.com")!,
            responseStatus: 422,
            responseHeaders: HttpHeaders(),
            responseError: nil,
            responseData: nil
        ))
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
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockDateProvider.currentDate = Date().addingTimeInterval(PreKeyTaskManager.Constants.SignedPreKeyRotationTime + 1)

        _ = try await taskManager.refresh(identity: .aci, targets: .signedPreKey, auth: .implicit())

        XCTAssertEqual(aciSignedPreKeyCount(), 1)
        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
    }

    func testRefreshOnlyPreKeysBasedOnCount() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
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
