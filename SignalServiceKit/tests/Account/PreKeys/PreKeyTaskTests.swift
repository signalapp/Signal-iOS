//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import XCTest
@testable import SignalServiceKit

final class PreKeyTaskTests: XCTestCase {

    private var testSchedulers: TestSchedulers!

    private var mockAccountManager: PreKey.Operation.Mocks.AccountManager!
    private var mockIdentityManager: PreKey.Operation.Mocks.IdentityManager!
    private var mockServiceClient: PreKey.Operation.Mocks.AccountServiceClient!
    private var mockDateProvider: PreKey.Operation.Mocks.DateProvider!
    private var context: PreKeyTasks.Context!

    private var mockAciProtocolStore: MockSignalProtocolStore!
    private var mockPniProtocolStore: MockSignalProtocolStore!
    private var mockProtocolStoreManager: SignalProtocolStoreManager!

    override func setUp() {
        super.setUp()
        testSchedulers = TestSchedulers(scheduler: TestScheduler())
        mockAccountManager = .init()
        mockServiceClient = .init()
        mockDateProvider = .init()
        mockIdentityManager = .init()

        mockAciProtocolStore = .init()
        mockPniProtocolStore = .init()
        mockProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: mockAciProtocolStore,
            pniProtocolStore: mockPniProtocolStore
        )

        context = PreKeyTasks.Context(
            accountManager: mockAccountManager,
            dateProvider: mockDateProvider.targetDate,
            db: MockDB(schedulers: testSchedulers),
            identityManager: mockIdentityManager,
            messageProcessor: PreKey.Operation.Mocks.MessageProcessor(),
            protocolStoreManager: mockProtocolStoreManager,
            schedulers: testSchedulers,
            serviceClient: mockServiceClient
        )
    }

    //
    //
    // MARK: - Create PreKey Tests
    //
    //

    func testCreateAll() {
        let task = PreKeyTasks.PreKeyTask(
            action: .legacy_create(identity: .aci, targets: .all),
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
        let task = PreKeyTasks.PreKeyTask(
            action: .legacy_create(identity: .aci, targets: .signedPreKey),
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
        let task = PreKeyTasks.PreKeyTask(
            action: .legacy_create(identity: .aci, targets: .oneTimePreKey),
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
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
        let task = PreKeyTasks.PreKeyTask(
            action: .legacy_create(identity: .aci, targets: .all),
            auth: .implicit(),
            context: context
        )

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockServiceClient.preKeyRecords?.count, 100)
        XCTAssertEqual(mockServiceClient.identityKey, mockIdentityManager.aciKeyPair!.publicKey)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.pqPreKeyRecords)
        XCTAssertEqual(mockServiceClient.pqPreKeyRecords?.count, 100)
        XCTAssertNotNil(mockServiceClient.pqLastResortPreKeyRecord)
    }

    func testMockCreateSignedPreKeyWithExisting() {
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
        let task = PreKeyTasks.PreKeyTask(
            action: .legacy_create(identity: .aci, targets: .signedPreKey),
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
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
        let task = PreKeyTasks.PreKeyTask(
            action: .legacy_create(identity: .aci, targets: .oneTimePreKey),
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
        let task = PreKeyTasks.PreKeyTask(
            action: .legacy_create(identity: .aci, targets: [.lastResortPqPreKey, .oneTimePqPreKey]),
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
            action: .legacy_create(identity: .aci, targets: []),
            auth: .implicit(),
            context: context
        )

        XCTAssertNil(mockIdentityManager.aciKeyPair)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        // Validate key created
        XCTAssertNotNil(mockIdentityManager.aciKeyPair)
    }

    //
    //
    // MARK: - Refresh Tests
    //
    //

    func testMockPreKeyTaskUpdate() {
        let aciKeyPair = Curve25519.generateKeyPair()
        mockIdentityManager.aciKeyPair = aciKeyPair

        let originalSignedPreKey = mockAciProtocolStore.mockSignedPreKeyStore.generateRandomSignedRecord()
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)

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
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
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
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
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
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
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
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
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
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
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

    //
    // Test validation
    //

    func testSignedPreKeyExpired() {
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
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
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
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
