//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import XCTest
@testable import SignalServiceKit

final class PreKeyTaskTests: XCTestCase {

    private var mockTSAccountManager: MockTSAccountManager!
    private var mockIdentityManager: PreKey.Mocks.IdentityManager!
    private var mockLinkedDevicePniKeyManager: PreKey.Mocks.LinkedDevicePniKeyManager!
    private var mockAPIClient: PreKey.Mocks.APIClient!
    private var mockDateProvider: PreKey.Mocks.DateProvider!
    private var mockDb: InMemoryDB!
    private var scheduler: TestScheduler!

    private var taskManager: PreKeyTaskManager!

    private var mockAciProtocolStore: MockSignalProtocolStore!
    private var mockPniProtocolStore: MockSignalProtocolStore!
    private var mockProtocolStoreManager: SignalProtocolStoreManager!

    override func setUp() {
        super.setUp()
        mockTSAccountManager = .init()
        mockIdentityManager = .init()
        mockLinkedDevicePniKeyManager = .init()
        mockAPIClient = .init()
        mockDateProvider = .init()
        scheduler = TestScheduler()
        mockDb = InMemoryDB(schedulers: TestSchedulers(scheduler: scheduler))

        mockAciProtocolStore = .init()
        mockPniProtocolStore = .init()
        mockProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: mockAciProtocolStore,
            pniProtocolStore: mockPniProtocolStore
        )

        taskManager = PreKeyTaskManager(
            apiClient: mockAPIClient,
            dateProvider: mockDateProvider.targetDate,
            db: mockDb,
            identityManager: mockIdentityManager,
            linkedDevicePniKeyManager: mockLinkedDevicePniKeyManager,
            messageProcessor: PreKey.Mocks.MessageProcessor(),
            protocolStoreManager: mockProtocolStoreManager,
            tsAccountManager: mockTSAccountManager
        )
    }

    override func tearDown() {
        mockAPIClient.setPreKeysResult.ensureUnset()
    }

    //
    //
    // MARK: - Create PreKey Tests
    //
    //

    func testCreateAll() async throws {
        mockAPIClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .all, auth: .implicit())

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
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockSignedPreKeyStore.generatedSignedPreKeys.count, 0)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        _ = try await taskManager.rotate(identity: .aci, targets: .signedPreKey, auth: .implicit())

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNil(mockAPIClient.preKeyRecords)
        XCTAssertNil(mockAPIClient.pqPreKeyRecords)
        XCTAssertNil(mockAPIClient.pqLastResortPreKeyRecord)
    }

    func testCreatePreKeyOnly() async throws {
        mockAPIClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockSignedPreKeyStore.generatedSignedPreKeys.count, 0)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        _ = try await taskManager.rotate(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

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

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .all, auth: .implicit())

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
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        XCTAssertEqual(mockAPIClient.preKeyRecords?.count, 100)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)
        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNil(mockAPIClient.pqPreKeyRecords)
        XCTAssertNil(mockAPIClient.pqLastResortPreKeyRecord)
    }

    func testCreatePqKeysOnly() async throws {
        mockAPIClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.oneTimeRecords.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.lastResortRecords.count, 0)

        _ = try await taskManager.rotate(
            identity: .aci,
            targets: [.lastResortPqPreKey, .oneTimePqPreKey],
            auth: .implicit()
        )

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.oneTimeRecords.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.lastResortRecords.count, 1)

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

        let originalSignedPreKey = mockAciProtocolStore.mockSignedPreKeyStore.generateRandomSignedRecord()
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

        let sentSignedPreKeyRecord = mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord
        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
        XCTAssertNotNil(sentSignedPreKeyRecord)
        XCTAssertNotEqual(sentSignedPreKeyRecord!.id, originalSignedPreKey.id)
    }

    func testMockPreKeyTaskNoUpdate() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        _ = mockAciProtocolStore.mockPreKeyStore.generatePreKeyRecords()

        mockAPIClient.currentPreKeyCount = 50
        mockAPIClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)
        XCTAssertNil(mockAPIClient.preKeyRecords)
    }

    func testMockUpdateFailNoIdentity() async throws {
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
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

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 0)
        XCTAssertNil(mockAPIClient.preKeyRecords)
    }

    func testMockUpdateSkipSignedPreKey() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 50
        mockAPIClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 0)
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

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 0)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

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

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockAPIClient.preKeyRecords)
        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
    }

    func testForceRefreshOnlyPreKeys() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 100
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockAPIClient.preKeyRecords)
        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
    }

    //
    // PNI
    //

    func test403WhileSettingKeysReportsSuspectedPniIdentityKeyIssue() async throws {
        mockIdentityManager.pniKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .error(OWSHTTPError.forServiceResponse(
            requestUrl: URL(string: "https://example.com")!,
            responseStatus: 403,
            responseHeaders: OWSHttpHeaders(),
            responseError: nil,
            responseData: nil
        ))

        _ = try await taskManager.rotate(identity: .pni, targets: .all, auth: .implicit())

        scheduler.runUntilIdle()

        // Validate
        XCTAssertTrue(mockLinkedDevicePniKeyManager.hasSuspectedIssue)
    }

    //
    // Test validation
    //

    func testSignedPreKeyExpired() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockDateProvider.currentDate = Date().addingTimeInterval(PreKeyTaskManager.Constants.SignedPreKeyRotationTime + 1)

        _ = try await taskManager.refresh(identity: .aci, targets: .signedPreKey, auth: .implicit())

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)
        XCTAssertNotNil(mockAPIClient.signedPreKeyRecord)
    }

    func testRefreshOnlyPreKeysBasedOnCount() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockAPIClient.setPreKeysResult = .value(())

        mockAPIClient.currentPreKeyCount = 9
        mockAPIClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockAPIClient.preKeyRecords)
        XCTAssertNil(mockAPIClient.signedPreKeyRecord)
    }

}
