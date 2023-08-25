//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class LinkedDevicePniKeyManagerTest: XCTestCase {
    private struct TestKVStore {
        private static let hasDecryptionErrorKey = "hasRecordedPniDecryptionError"

        private let db: DB
        private let kvStore: KeyValueStore

        init(db: DB, kvStoreFactory: KeyValueStoreFactory) {
            self.db = db
            self.kvStore = kvStoreFactory.keyValueStore(collection: "LinkedDevicePniKeyManagerImpl")
        }

        func hasDecryptionError() -> Bool {
            return db.read { kvStore.getBool(Self.hasDecryptionErrorKey, defaultValue: false, transaction: $0) }
        }

        func setHasDecryptionError() {
            db.write { kvStore.setBool(true, key: Self.hasDecryptionErrorKey, transaction: $0) }
        }
    }

    private var db: MockDB!
    private var kvStore: TestKVStore!
    private var messageProcessorMock: MessageProcessorMock!
    private var pniIdentityKeyCheckerMock: PniIdentityKeyCheckerMock!
    private var testScheduler: TestScheduler!
    private var tsAccountManagerMock: TSAccountManagerMock!

    private var linkedDevicePniKeyManager: LinkedDevicePniKeyManagerImpl!

    override func setUp() {
        let kvStoreFactory = InMemoryKeyValueStoreFactory()

        testScheduler = TestScheduler()
        let testSchedulers = TestSchedulers(scheduler: testScheduler)

        db = MockDB()
        kvStore = TestKVStore(db: db, kvStoreFactory: kvStoreFactory)
        messageProcessorMock = MessageProcessorMock(schedulers: testSchedulers)
        pniIdentityKeyCheckerMock = PniIdentityKeyCheckerMock()
        tsAccountManagerMock = TSAccountManagerMock()

        linkedDevicePniKeyManager = LinkedDevicePniKeyManagerImpl(
            db: db,
            keyValueStoreFactory: kvStoreFactory,
            messageProcessor: messageProcessorMock,
            pniIdentityKeyChecker: pniIdentityKeyCheckerMock,
            schedulers: testSchedulers,
            tsAccountManager: tsAccountManagerMock
        )
    }

    override func tearDown() {
        messageProcessorMock.fetchProcessResult.ensureUnset()
        pniIdentityKeyCheckerMock.matchResult.ensureUnset()
    }

    private func runRunRun() {
        db.read { tx in
            linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary(tx: tx)
        }

        testScheduler.runUntilIdle()
    }

    func testUnlinkedIfDecryptionErrorAndMissingPni() {
        kvStore.setHasDecryptionError()
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiers = .missingPni

        runRunRun()

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(tsAccountManagerMock.isDeregistered)
    }

    func testUnlinkedIfDecryptionErrorAndMismatchedIdentityKey() {
        kvStore.setHasDecryptionError()
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiers = .mock
        pniIdentityKeyCheckerMock.matchResult = .value(false)

        runRunRun()

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(tsAccountManagerMock.isDeregistered)
    }

    func testNotUnlinkedIfMessageFetchingProcessingFails() {
        kvStore.setHasDecryptionError()
        messageProcessorMock.fetchProcessResult = .error()

        runRunRun()

        XCTAssertTrue(kvStore.hasDecryptionError())
        XCTAssertFalse(tsAccountManagerMock.isDeregistered)
    }

    func testNotUnlinkedIfIdentityKeyCheckingFails() {
        kvStore.setHasDecryptionError()
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiers = .mock
        pniIdentityKeyCheckerMock.matchResult = .error()

        runRunRun()

        XCTAssertTrue(kvStore.hasDecryptionError())
        XCTAssertFalse(tsAccountManagerMock.isDeregistered)
    }

    func testNotUnlinkedIfIdentityKeyMatches() {
        kvStore.setHasDecryptionError()
        messageProcessorMock.fetchProcessResult = .value({})
        tsAccountManagerMock.localIdentifiers = .mock
        pniIdentityKeyCheckerMock.matchResult = .value(true)

        runRunRun()

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(tsAccountManagerMock.isDeregistered)
    }

    func testEarlyExitIfPrimary() {
        tsAccountManagerMock.isPrimaryDevice = true

        // This will fail if it doesn't early-exit, due to missing mocks.
        runRunRun()

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(tsAccountManagerMock.isDeregistered)
    }

    func testEarlyExitIfNoError() {
        messageProcessorMock.fetchProcessResult = .value({})

        // This will fail if it doesn't early-exit, due to missing mocks.
        runRunRun()

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(tsAccountManagerMock.isDeregistered)
    }

    /// It's important that we don't check for the decryption error until
    /// *after* the message queue is cleared, because that's where we'll
    /// register the error.
    func testChecksForDecryptionErrorAfterClearingQueue() {
        messageProcessorMock.fetchProcessResult = .value({ self.kvStore.setHasDecryptionError() })
        tsAccountManagerMock.localIdentifiers = .mock
        pniIdentityKeyCheckerMock.matchResult = .value(false)

        runRunRun()

        // Expect an unlink
        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(tsAccountManagerMock.isDeregistered)
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

private class TSAccountManagerMock: LinkedDevicePniKeyManagerImpl.Shims.TSAccountManager {
    var localIdentifiers: LocalIdentifiers?
    var isPrimaryDevice = false
    var isDeregistered = false

    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return localIdentifiers
    }

    func isPrimaryDevice(tx: DBReadTransaction) -> Bool {
        return isPrimaryDevice
    }

    func setIsDeregistered() {
        isDeregistered = true
    }
}
