//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class LinkedDevicePniKeyManagerTest: XCTestCase {
    private struct TestKVStore {
        private static let hasSuspectedIssueKey = "hasSuspectedIssue"

        private let db: DB
        private let kvStore: KeyValueStore

        init(db: DB, kvStoreFactory: KeyValueStoreFactory) {
            self.db = db
            self.kvStore = kvStoreFactory.keyValueStore(collection: "LinkedDevicePniKeyManagerImpl")
        }

        func hasDecryptionError() -> Bool {
            return db.read { kvStore.getBool(Self.hasSuspectedIssueKey, defaultValue: false, transaction: $0) }
        }
    }

    private var db: MockDB!
    private var kvStore: TestKVStore!
    private var messageProcessorMock: MessageProcessorMock!
    private var pniIdentityKeyCheckerMock: PniIdentityKeyCheckerMock!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var testScheduler: TestScheduler!
    private var tsAccountManagerMock: MockTSAccountManager!

    private var linkedDevicePniKeyManager: LinkedDevicePniKeyManagerImpl!

    private var isMarkedDeregistered: Bool = false

    override func setUp() {
        let kvStoreFactory = InMemoryKeyValueStoreFactory()

        testScheduler = TestScheduler()
        let testSchedulers = TestSchedulers(scheduler: testScheduler)

        db = MockDB()
        kvStore = TestKVStore(db: db, kvStoreFactory: kvStoreFactory)
        messageProcessorMock = MessageProcessorMock(schedulers: testSchedulers)
        pniIdentityKeyCheckerMock = PniIdentityKeyCheckerMock()
        registrationStateChangeManagerMock = .init()
        tsAccountManagerMock = .init()

        registrationStateChangeManagerMock.setIsDeregisteredOrDelinkedMock = { [weak self] isDeregistered in
            self?.isMarkedDeregistered = isDeregistered
        }

        tsAccountManagerMock.registrationStateMock = { .provisioned }

        linkedDevicePniKeyManager = LinkedDevicePniKeyManagerImpl(
            db: db,
            keyValueStoreFactory: kvStoreFactory,
            messageProcessor: messageProcessorMock,
            pniIdentityKeyChecker: pniIdentityKeyCheckerMock,
            registrationStateChangeManager: registrationStateChangeManagerMock,
            schedulers: testSchedulers,
            tsAccountManager: tsAccountManagerMock
        )
    }

    override func tearDown() {
        messageProcessorMock.fetchProcessResult.ensureUnset()
        pniIdentityKeyCheckerMock.matchResult.ensureUnset()
    }

    private func runRunRun(recordIssue: Bool) {
        db.write { tx in
            if recordIssue {
                linkedDevicePniKeyManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
            } else {
                linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary(tx: tx)
            }
        }

        testScheduler.runUntilIdle()
    }

    func testDoesntRecordIfPrimaryDevice() {
        tsAccountManagerMock.registrationStateMock = { .registered }

        db.write { tx in
            linkedDevicePniKeyManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
        }

        testScheduler.runUntilIdle()

        XCTAssertFalse(kvStore.hasDecryptionError())
    }

    func testUnlinkedIfDecryptionErrorAndMissingPni() {
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiersMock = { .missingPni }

        runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
    }

    func testUnlinkedIfDecryptionErrorAndMismatchedIdentityKey() {
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        pniIdentityKeyCheckerMock.matchResult = .value(false)

        runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
    }

    func testNotUnlinkedIfMessageFetchingProcessingFails() {
        messageProcessorMock.fetchProcessResult = .error()

        runRunRun(recordIssue: true)

        XCTAssertTrue(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
    }

    func testNotUnlinkedIfIdentityKeyCheckingFails() {
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        pniIdentityKeyCheckerMock.matchResult = .error()

        runRunRun(recordIssue: true)

        XCTAssertTrue(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
    }

    func testNotUnlinkedIfIdentityKeyMatches() {
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        pniIdentityKeyCheckerMock.matchResult = .value(true)

        runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
    }

    func testEarlyExitIfPrimary() {
        tsAccountManagerMock.registrationStateMock = { .registered }

        // This will fail if it doesn't early-exit, due to missing mocks.
        runRunRun(recordIssue: false)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
    }

    func testEarlyExitIfNoError() {
        messageProcessorMock.fetchProcessResult = .value({})

        // This will fail if it doesn't early-exit, due to missing mocks.
        runRunRun(recordIssue: false)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
    }

    /// It's important that we don't check for the decryption error until
    /// *after* the message queue is cleared, because that's where we'll
    /// register the error.
    func testChecksForDecryptionErrorAfterClearingQueue() {
        messageProcessorMock.fetchProcessResult = .value({ self.runRunRun(recordIssue: true) })
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        pniIdentityKeyCheckerMock.matchResult = .value(false)

        runRunRun(recordIssue: false)

        // Expect an unlink
        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
    }

    /// Checks that multiple overlapping validation attempts are collapsed into
    /// one. Also checks that a subsequent validation runs.
    func testMultipleCallsResultInOneRun() {
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        pniIdentityKeyCheckerMock.matchResult = .value(true)

        db.write { tx in
            linkedDevicePniKeyManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
            linkedDevicePniKeyManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
        }
        testScheduler.runUntilIdle()

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)

        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        pniIdentityKeyCheckerMock.matchResult = .value(false)

        db.write { tx in
            linkedDevicePniKeyManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
        }
        testScheduler.runUntilIdle()

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
    }
}

// MARK: - Mocks

private extension LocalIdentifiers {
    static let mock = LocalIdentifiers(
        aci: Aci.randomForTesting(),
        pni: Pni.randomForTesting(),
        e164: E164("+17735550155")!
    )

    static let missingPni = LocalIdentifiers(
        aci: Aci.randomForTesting(),
        pni: nil,
        e164: E164("+17735550155")!
    )
}

private class MessageProcessorMock: LinkedDevicePniKeyManagerImpl.Shims.MessageProcessor {
    var fetchProcessResult: ConsumableMockPromise<() -> Void> = .unset

    private let schedulers: Schedulers

    init(schedulers: Schedulers) {
        self.schedulers = schedulers
    }

    func fetchingAndProcessingCompletePromise() -> Promise<Void> {
        return fetchProcessResult.consumeIntoPromise().map(on: schedulers.sync) { $0() }
    }
}

private class PniIdentityKeyCheckerMock: PniIdentityKeyChecker {
    var matchResult: ConsumableMockPromise<Bool> = .unset

    func serverHasSameKeyAsLocal(localPni: Pni, tx: DBReadTransaction) -> Promise<Bool> {
        return matchResult.consumeIntoPromise()
    }
}
