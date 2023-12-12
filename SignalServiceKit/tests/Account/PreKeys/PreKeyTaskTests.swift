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
    private var mockServiceClient: PreKey.Mocks.AccountServiceClient!
    private var mockDateProvider: PreKey.Mocks.DateProvider!

    private var taskManager: PreKeyTaskManager!

    private var mockAciProtocolStore: MockSignalProtocolStore!
    private var mockPniProtocolStore: MockSignalProtocolStore!
    private var mockProtocolStoreManager: SignalProtocolStoreManager!

    override func setUp() {
        super.setUp()
        mockTSAccountManager = .init()
        mockIdentityManager = .init()
        mockLinkedDevicePniKeyManager = .init()
        mockServiceClient = .init()
        mockDateProvider = .init()

        mockAciProtocolStore = .init()
        mockPniProtocolStore = .init()
        mockProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: mockAciProtocolStore,
            pniProtocolStore: mockPniProtocolStore
        )

        taskManager = PreKeyTaskManager(
            dateProvider: mockDateProvider.targetDate,
            db: MockDB(),
            identityManager: mockIdentityManager,
            linkedDevicePniKeyManager: mockLinkedDevicePniKeyManager,
            messageProcessor: PreKey.Mocks.MessageProcessor(),
            protocolStoreManager: mockProtocolStoreManager,
            serviceClient: mockServiceClient,
            tsAccountManager: mockTSAccountManager
        )
    }

    override func tearDown() {
        mockServiceClient.setPreKeysResult.ensureUnset()
    }

    //
    //
    // MARK: - Create PreKey Tests
    //
    //

    func testCreateAll() async throws {
        mockServiceClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .all, auth: .implicit())

        // Validate
        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.pqLastResortPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertEqual(mockServiceClient.pqPreKeyRecords?.count, 100)
    }

    func testCreateSignedPreKeyOnly() async throws {
        mockServiceClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockSignedPreKeyStore.generatedSignedPreKeys.count, 0)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        _ = try await taskManager.rotate(identity: .aci, targets: .signedPreKey, auth: .implicit())

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.preKeyRecords)
        XCTAssertNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testCreatePreKeyOnly() async throws {
        mockServiceClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockSignedPreKeyStore.generatedSignedPreKeys.count, 0)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        _ = try await taskManager.rotate(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertNil(mockServiceClient.pqLastResortPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.preKeyRecords)
    }

    // Test that the IdentityMananger keypair makes it through to the
    // service client
    func testMockPreKeyTaskCreateWithExistingIdentityKey() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertEqual(mockServiceClient.pqPreKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testMockCreateSignedPreKeyWithExisting() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let originalSignedPreKey = mockAciProtocolStore.mockSignedPreKeyStore.generateRandomSignedRecord()
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .signedPreKey, auth: .implicit())

        XCTAssertNil(mockServiceClient.preKeyRecords)
        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.currentSignedPreKey)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.pqLastResortPreKeyRecord)
        XCTAssertNil(mockServiceClient.pqPreKeyRecords)
    }

    func testMockCreatePreKeyOnlyWithExisting() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        mockServiceClient.currentPreKeyCount = 100
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testCreatePqKeysOnly() async throws {
        mockServiceClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.oneTimeRecords.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.lastResortRecords.count, 0)
        XCTAssertNil(mockAciProtocolStore.mockKyberPreKeyStore.currentLastResortPreKey)

        _ = try await taskManager.rotate(
            identity: .aci,
            targets: [.lastResortPqPreKey, .oneTimePqPreKey],
            auth: .implicit()
        )

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.oneTimeRecords.count, 100)
        XCTAssertNotNil(mockAciProtocolStore.mockKyberPreKeyStore.currentLastResortPreKey)

        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.preKeyRecords)
        XCTAssertNotNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertNotNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testIdentityKeyCreated() async throws {
        XCTAssertNil(mockIdentityManager.pniKeyPair)

        _ = try await taskManager.createOrRotatePniKeys(targets: [], auth: .implicit())

        // Validate key created
        XCTAssertNotNil(mockIdentityManager.pniKeyPair)
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
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)

        mockServiceClient.setPreKeysResult = .value(())
        mockServiceClient.currentPreKeyCount = 0
        mockServiceClient.currentPqPreKeyCount = 0

        mockDateProvider.currentDate = Date(timeIntervalSinceNow: PreKeyTaskManager.Constants.SignedPreKeyRotationTime + 1)

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.currentSignedPreKey)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        let sentSignedPreKeyRecord = mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNotNil(sentSignedPreKeyRecord)
        XCTAssertNotEqual(
            sentSignedPreKeyRecord!.generatedAt,
            originalSignedPreKey.generatedAt
        )
    }

    func testMockPreKeyTaskNoUpdate() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        _ = mockAciProtocolStore.mockPreKeyStore.generatePreKeyRecords()

        mockServiceClient.currentPreKeyCount = 50
        mockServiceClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)
        XCTAssertNil(mockServiceClient.preKeyRecords)
    }

    func testMockUpdateFailNoIdentity() async throws {
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        mockServiceClient.currentPreKeyCount = 0
        mockServiceClient.currentPqPreKeyCount = 0

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
        XCTAssertNil(mockServiceClient.preKeyRecords)
    }

    func testMockUpdateSkipSignedPreKey() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        mockServiceClient.currentPreKeyCount = 50
        mockServiceClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 0)
        XCTAssertNil(mockServiceClient.preKeyRecords)
    }

    //
    //
    // MARK: - Force Refresh Tests
    //
    //

    func testRefreshNoUpdatesNeeded() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        mockServiceClient.currentPreKeyCount = 100
        mockServiceClient.currentPqPreKeyCount = 100

        let originalSignedPreKey = mockAciProtocolStore.signedPreKeyStore.generateSignedPreKey(signedBy: mockIdentityManager.aciKeyPair!)
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 0)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNil(mockServiceClient.preKeyRecords)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
    }

    func testForceRefreshAll() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        mockServiceClient.currentPreKeyCount = 100

        let originalSignedPreKey = mockAciProtocolStore.signedPreKeyStore.generateSignedPreKey(signedBy: mockIdentityManager.aciKeyPair!)
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .all, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockServiceClient.preKeyRecords)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
    }

    func testForceRefreshOnlyPreKeys() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        mockServiceClient.currentPreKeyCount = 100
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.rotate(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockServiceClient.preKeyRecords)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
    }

    //
    // PNI
    //

    func testMockPreKeyTaskCreate() async throws {
        mockServiceClient.setPreKeysResult = .value(())

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockPniProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.createOrRotatePniKeys(targets: .all, auth: .implicit())

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockPniProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
    }

    func test403WhileSettingKeysReportsSuspectedPniIdentityKeyIssue() async throws {
        mockIdentityManager.pniKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .error(OWSHTTPError.forServiceResponse(
            requestUrl: URL(string: "https://example.com")!,
            responseStatus: 403,
            responseHeaders: OWSHttpHeaders(),
            responseError: nil,
            responseData: nil
        ))

        _ = try await taskManager.rotate(identity: .pni, targets: .all, auth: .implicit())

        // Validate
        XCTAssertTrue(mockLinkedDevicePniKeyManager.hasSuspectedIssue)
    }

    //
    // Test validation
    //

    func testSignedPreKeyExpired() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let originalSignedPreKey = mockAciProtocolStore
            .signedPreKeyStore
            .generateSignedPreKey(
                signedBy: mockIdentityManager.aciKeyPair!
            )
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)
        mockDateProvider.currentDate = Date().addingTimeInterval(PreKeyTaskManager.Constants.SignedPreKeyRotationTime + 1)

        _ = try await taskManager.refresh(identity: .aci, targets: .signedPreKey, auth: .implicit())

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
    }

    func testRefreshOnlyPreKeysBasedOnCount() async throws {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        mockServiceClient.currentPreKeyCount = 9
        mockServiceClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = try await taskManager.refresh(identity: .aci, targets: .oneTimePreKey, auth: .implicit())

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockServiceClient.preKeyRecords)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
    }

}
