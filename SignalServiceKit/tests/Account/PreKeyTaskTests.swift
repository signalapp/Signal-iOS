//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import XCTest
@testable import SignalServiceKit

final class PreKeyTaskTests: XCTestCase {

    private var testSchedulers: TestSchedulers!

    private var mockAccountManager: PreKey.Mocks.AccountManager!
    private var mockIdentityManager: PreKey.Mocks.IdentityManager!
    private var mockServiceClient: PreKey.Mocks.AccountServiceClient!
    private var mockDateProvider: PreKey.Mocks.DateProvider!
    private var context: PreKeyTask.Context!

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

        context = PreKeyTask.Context(
            accountManager: mockAccountManager,
            dateProvider: mockDateProvider.targetDate,
            db: MockDB(schedulers: testSchedulers),
            identityManager: mockIdentityManager,
            messageProcessor: PreKey.Mocks.MessageProcessor(),
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
        let task = PreKeyTask(
            for: .aci,
            action: .create(.all),
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

    func testCreateFailsOnLinkedDevice() {
        mockAccountManager.isPrimaryDevice = false
        let task = PreKeyTask(
            for: .aci,
            action: .create(.signedPreKey),
            auth: .implicit(),
            context: context
        )

        firstly(on: testSchedulers.global()) {
            task.runPreKeyTask()
        }.catch(on: testSchedulers.global()) { error in
            switch error {
            case PreKeyTask.Error.noIdentityKey:
                XCTAssertNil(self.mockIdentityManager.aciKeyPair)
            default:
                XCTFail("Unexpected error")
            }
        }.done { _ in
            XCTFail("Expected failure, but returned success")
        }.cauterize()

        testSchedulers.scheduler.start()
    }

    func testCreateSignedPreKeyOnly() {
        let task = PreKeyTask(
            for: .aci,
            action: .create(.signedPreKey),
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
        let task = PreKeyTask(
            for: .aci,
            action: .create(.oneTimePreKey),
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
        let task = PreKeyTask(
            for: .aci,
            action: .create(.all),
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
        let task = PreKeyTask(
            for: .aci,
            action: .create(.signedPreKey),
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
        let task = PreKeyTask(
            for: .aci,
            action: .create(.oneTimePreKey),
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
        let task = PreKeyTask(
            for: .aci,
            action: .create([.lastResortPqPreKey, .oneTimePqPreKey]),
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
        let task = PreKeyTask(
            for: .aci,
            action: .create([]),
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

        mockDateProvider.currentDate = Date(timeIntervalSinceNow: PreKeyTask.Constants.SignedPreKeyRotationTime + 1)
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.all, forceRefresh: false),
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
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.all, forceRefresh: false),
            auth: .implicit(),
            context: context
        )

        _ = mockAciProtocolStore.mockPreKeyStore.generatePreKeyRecords()

        mockServiceClient.currentPreKeyCount = 50
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 100)
        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.preKeyId, 100)
        XCTAssertNil(mockServiceClient.preKeyRecords)
    }

    func testMockUpdateFailNoIdentity() {
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.all, forceRefresh: false),
            auth: .implicit(),
            context: context
        )

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        firstly(on: testSchedulers.global()) {
            task.runPreKeyTask()
        }.catch(on: testSchedulers.global()) { error in
            switch error {
            case PreKeyTask.Error.noIdentityKey:
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

    func testMockUpdateFailNotRegistered() {
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
        mockAccountManager.isRegisteredAndReady = false
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.all, forceRefresh: false),
            auth: .implicit(),
            context: context
        )

        XCTAssertEqual(mockAciProtocolStore.mockPreKeyStore.records.count, 0)

        firstly(on: testSchedulers.global()) {
            task.runPreKeyTask()
        }.catch(on: testSchedulers.global()) { error in
            switch error {
            case PreKeyTask.Error.notRegistered:
                break
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
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.all, forceRefresh: false),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 50
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
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.all, forceRefresh: false),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 100

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
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.all, forceRefresh: true),
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
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.oneTimePreKey, forceRefresh: true),
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
        let task = PreKeyTask(
            for: .pni,
            action: .create(.all),
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
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.signedPreKey, forceRefresh: false),
            auth: .implicit(),
            context: context
        )

        let originalSignedPreKey = mockAciProtocolStore
            .signedPreKeyStore
            .generateSignedPreKey(
                signedBy: mockIdentityManager.aciKeyPair!
            )
        mockAciProtocolStore.mockSignedPreKeyStore.setCurrentSignedPreKey(originalSignedPreKey)
        mockDateProvider.currentDate = Date().addingTimeInterval(PreKeyTask.Constants.SignedPreKeyRotationTime + 1)

        _ = task.runPreKeyTask()
        testSchedulers.scheduler.start()

        XCTAssertNotNil(mockAciProtocolStore.mockSignedPreKeyStore.storedSignedPreKeyRecord)
        XCTAssertNotNil(mockServiceClient.signedPreKeyRecord)
    }

    func testRefreshOnlyPreKeysBasedOnCount() {
        mockIdentityManager.aciKeyPair = Curve25519.generateKeyPair()
        let task = PreKeyTask(
            for: .aci,
            action: .refresh(.oneTimePreKey, forceRefresh: false),
            auth: .implicit(),
            context: context
        )

        mockServiceClient.currentPreKeyCount = 9
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
