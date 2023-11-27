//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import XCTest
@testable import SignalServiceKit

final class PreKeyTaskTests: XCTestCase {

    private var testSchedulers: TestSchedulers!

    private var mockTSAccountManager: MockTSAccountManager!
    private var mockIdentityManager: PreKey.Operation.Mocks.IdentityManager!
    private var mockLinkedDevicePniKeyManager: PreKey.Operation.Mocks.LinkedDevicePniKeyManager!
    private var mockServiceClient: PreKey.Operation.Mocks.AccountServiceClient!
    private var mockDateProvider: PreKey.Operation.Mocks.DateProvider!
    private var context: PreKeyTasks.Context!

    private var mockAciProtocolStore: MockSignalProtocolStore!
    private var mockPniProtocolStore: MockSignalProtocolStore!
    private var mockProtocolStoreManager: SignalProtocolStoreManager!

    override func setUp() {
        super.setUp()
        testSchedulers = TestSchedulers(scheduler: TestScheduler())
        mockTSAccountManager = .init()
        mockIdentityManager = .init()
        mockLinkedDevicePniKeyManager = .init()
        mockServiceClient = .init(schedulers: testSchedulers)
        mockDateProvider = .init()

        mockAciProtocolStore = .init()
        mockPniProtocolStore = .init()
        mockProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: mockAciProtocolStore,
            pniProtocolStore: mockPniProtocolStore
        )

        context = PreKeyTasks.Context(
            dateProvider: mockDateProvider.targetDate,
            db: MockDB(schedulers: testSchedulers),
            identityManager: mockIdentityManager,
            linkedDevicePniKeyManager: mockLinkedDevicePniKeyManager,
            messageProcessor: PreKey.Operation.Mocks.MessageProcessor(),
            protocolStoreManager: mockProtocolStoreManager,
            schedulers: testSchedulers,
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

    func testCreateAll() {
        mockServiceClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        // Validate
        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.identityKey)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.pqLastResortPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertEqual(mockServiceClient.pqPreKeyRecords?.count, 100)
    }

    func testCreateSignedPreKeyOnly() {
        mockServiceClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: .signedPreKey),
            auth: .implicit(),
            context: context
        )

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockSignedPreKeyStore.generatedSignedPreKeys.count, 0)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockServiceClient.identityKey)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.preKeyRecords)
        XCTAssertNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testCreatePreKeyOnly() {
        mockServiceClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: .oneTimePreKey),
            auth: .implicit(),
            context: context
        )

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockSignedPreKeyStore.generatedSignedPreKeys.count, 0)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.identityKey)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertNil(mockServiceClient.pqLastResortPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.preKeyRecords)
    }

    // Test that the IdentityMananger keypair makes it through to the
    // service client
    func testMockPreKeyTaskCreateWithExistingIdentityKey() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertEqual(mockServiceClient.identityKey, mockIdentityManager.aciKeyPair!.keyPair.identityKey)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertEqual(mockServiceClient.pqPreKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testMockCreateSignedPreKeyWithExisting() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: .signedPreKey),
            auth: .implicit(),
            context: context
        )

        let originalSignedPreKey = mockAciProtocolStore.mockSignedPreKeyStore.generateRandomSignedRecord()
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertNil(mockServiceClient.preKeyRecords)
        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.currentSignedPreKey)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.pqLastResortPreKeyRecord)
        XCTAssertNil(mockServiceClient.pqPreKeyRecords)
    }

    func testMockCreatePreKeyOnlyWithExisting() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: .oneTimePreKey),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 100
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testCreatePqKeysOnly() {
        mockServiceClient.setPreKeysResult = .value(())
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: [.lastResortPqPreKey, .oneTimePqPreKey]),
            auth: .implicit(),
            context: context
        )

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.oneTimeRecords.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.lastResortRecords.count, 0)
        XCTAssertNil(mockAciProtocolStore.mockKyberPreKeyStore.currentLastResortPreKey)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockKyberPreKeyStore.oneTimeRecords.count, 100)
        XCTAssertNotNil(mockAciProtocolStore.mockKyberPreKeyStore.currentLastResortPreKey)

        XCTAssertNotNil(mockServiceClient.identityKey)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNil(mockServiceClient.preKeyRecords)
        XCTAssertNotNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertNotNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testIdentityKeyCreated() {
        let task = PreKeyTasks.PreKeyTask(
            action: .createOrRotatePniKeys(targets: []),
            auth: .implicit(),
            context: context
        )

        XCTAssertNil(mockIdentityManager.pniKeyPair)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        // Validate key created
        XCTAssertNotNil(mockIdentityManager.pniKeyPair)
    }

    //
    //
    // MARK: - Refresh Tests
    //
    //

    func testMockPreKeyTaskUpdate() {
        let aciKeyPair = ECKeyPair.generateKeyPair()
        mockIdentityManager.aciKeyPair = aciKeyPair

        let originalSignedPreKey = mockAciProtocolStore.mockSignedPreKeyStore.generateRandomSignedRecord()
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)

        mockServiceClient.setPreKeysResult = .value(())
        mockServiceClient.currentPreKeyCount = 0
        mockServiceClient.currentPqPreKeyCount = 0

        mockDateProvider.currentDate = Date(timeIntervalSinceNow: PreKeyTasks.Constants.SignedPreKeyRotationTime + 1)
        let task = PreKeyTasks.PreKeyTask(
            action: .refresh(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.currentSignedPreKey)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        let sentSignedPreKeyRecord = mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNotNil(sentSignedPreKeyRecord)
        XCTAssertNotEqual(
            sentSignedPreKeyRecord!.generatedAt,
            originalSignedPreKey.generatedAt
        )
    }

    func testMockPreKeyTaskNoUpdate() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .refresh(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        _ = mockAciProtocolStore.mockPreKeyStore.generatePreKeyRecords()

        mockServiceClient.currentPreKeyCount = 50
        mockServiceClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)
        XCTAssertNil(mockServiceClient.preKeyRecords)
    }

    func testMockUpdateFailNoIdentity() {
        let task = PreKeyTasks.PreKeyTask(
            action: .refresh(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        firstly(on: testSchedulers.global()) {
            task.runPreKeyTask()
        }.catch(on: testSchedulers.global()) { error in
            switch error {
            case PreKeyTasks.Error.noIdentityKey:
                XCTAssertNil(self.mockIdentityManager.aciKeyPair)
            default:
                XCTFail("Unexpected error")
            }
        }.done { _ in
            XCTFail("Expected failure, but returned success")
        }.cauterize()

        testSchedulers.scheduler.start()

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 0)
        XCTAssertNil(mockServiceClient.preKeyRecords)
    }

    func testMockUpdateSkipSignedPreKey() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .refresh(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 50
        mockServiceClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 0)
        XCTAssertNil(mockServiceClient.preKeyRecords)
    }

    //
    //
    // MARK: - Force Refresh Tests
    //
    //

    func testRefreshNoUpdatesNeeded() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .refresh(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 100
        mockServiceClient.currentPqPreKeyCount = 100

        let originalSignedPreKey = mockAciProtocolStore.signedPreKeyStore.generateSignedPreKey(signedBy: mockIdentityManager.aciKeyPair!)
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 0)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNil(mockServiceClient.preKeyRecords)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
    }

    func testForceRefreshAll() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 100

        let originalSignedPreKey = mockAciProtocolStore.signedPreKeyStore.generateSignedPreKey(signedBy: mockIdentityManager.aciKeyPair!)
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockServiceClient.preKeyRecords)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
    }

    func testForceRefreshOnlyPreKeys() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .aci, targets: .oneTimePreKey),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 100
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockServiceClient.preKeyRecords)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
    }

    //
    // PNI
    //

    func testMockPreKeyTaskCreate() {
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .createOrRotatePniKeys(targets: .all),
            auth: .implicit(),
            context: context
        )

        // Pre-validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockPniProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        // Validate
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)
        XCTAssertEqual(mockPniProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.identityKey)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
    }

    func test403WhileSettingKeysReportsSuspectedPniIdentityKeyIssue() {
        mockIdentityManager.pniKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .error(OWSHTTPError.forServiceResponse(
            requestUrl: URL(string: "https://example.com")!,
            responseStatus: 403,
            responseHeaders: OWSHttpHeaders(),
            responseError: nil,
            responseData: nil
        ))

        let task = PreKeyTasks.PreKeyTask(
            action: .rotate(identity: .pni, targets: .all),
            auth: .implicit(),
            context: context
        )

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        // Validate
        XCTAssertTrue(mockLinkedDevicePniKeyManager.hasSuspectedIssue)
    }

    //
    // Test validation
    //

    func testSignedPreKeyExpired() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .refresh(identity: .aci, targets: .signedPreKey),
            auth: .implicit(),
            context: context
        )

        let originalSignedPreKey = mockAciProtocolStore
            .signedPreKeyStore
            .generateSignedPreKey(
                signedBy: mockIdentityManager.aciKeyPair!
            )
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)
        mockDateProvider.currentDate = Date().addingTimeInterval(PreKeyTasks.Constants.SignedPreKeyRotationTime + 1)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
    }

    func testRefreshOnlyPreKeysBasedOnCount() {
        mockIdentityManager.aciKeyPair = ECKeyPair.generateKeyPair()
        mockServiceClient.setPreKeysResult = .value(())

        let task = PreKeyTasks.PreKeyTask(
            action: .refresh(identity: .aci, targets: .oneTimePreKey),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 9
        mockServiceClient.currentPqPreKeyCount = 0
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        XCTAssertNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)

        XCTAssertNotNil(mockServiceClient.preKeyRecords)
        XCTAssertNil(mockServiceClient.signedPreKeyRecord)
    }

}
