//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class IdentityKeyMismatchManagerTest: XCTestCase {
    private struct TestKVStore {
        private static let hasSuspectedIssueKey = "hasSuspectedIssue"

        private let db: any DB
        private let kvStore: KeyValueStore

        init(db: any DB) {
            self.db = db
            self.kvStore = KeyValueStore(collection: "LinkedDevicePniKeyManagerImpl")
        }

        func hasDecryptionError() -> Bool {
            return db.read { kvStore.getBool(Self.hasSuspectedIssueKey, defaultValue: false, transaction: $0) }
        }
    }

    private var db: InMemoryDB!
    private var identityKeyCheckerMock: IdentityKeyCheckerMock!
    private var kvStore: TestKVStore!
    private var messageProcessorMock: MessageProcessorMock!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var tsAccountManagerMock: MockTSAccountManager!
    private var whoAmIManagerMock: MockWhoAmIManager!

    private var identityKeyMismatchManager: IdentityKeyMismatchManagerImpl!

    private var isMarkedDeregistered: Bool = false

    override func setUp() {
        db = InMemoryDB()
        identityKeyCheckerMock = IdentityKeyCheckerMock()
        kvStore = TestKVStore(db: db)
        messageProcessorMock = MessageProcessorMock()
        registrationStateChangeManagerMock = .init()
        tsAccountManagerMock = .init()
        whoAmIManagerMock = MockWhoAmIManager()

        registrationStateChangeManagerMock.setIsDeregisteredOrDelinkedMock = { [weak self] isDeregistered in
            self?.isMarkedDeregistered = isDeregistered
        }

        tsAccountManagerMock.registrationStateMock = { .provisioned }

        identityKeyMismatchManager = IdentityKeyMismatchManagerImpl(
            db: db,
            identityKeyChecker: identityKeyCheckerMock,
            messageProcessor: messageProcessorMock,
            registrationStateChangeManager: registrationStateChangeManagerMock,
            tsAccountManager: tsAccountManagerMock,
            whoAmIManager: whoAmIManagerMock,
        )
    }

    private func runRunRun(recordIssue: Bool) async {
        if recordIssue {
            await db.awaitableWrite { tx in
                identityKeyMismatchManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
            }
        }
        await identityKeyMismatchManager.validateLocalPniIdentityKeyIfNecessary()
    }

    func testDoesntRecordIfPrimaryDevice() async {
        tsAccountManagerMock.registrationStateMock = { .registered }

        await db.awaitableWrite { tx in
            return identityKeyMismatchManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
        }
        await identityKeyMismatchManager.validateLocalPniIdentityKeyIfNecessary()

        XCTAssertFalse(kvStore.hasDecryptionError())
    }

    func testUnlinkedIfDecryptionErrorAndMissingPni() async {
        let localIdentifiers = LocalIdentifiers.mock
        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        whoAmIManagerMock.whoAmIResponse = .value(.forUnitTest(localIdentifiers: localIdentifiers))
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers.withoutPni() }

        await runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
    }

    func testUnlinkedIfDecryptionErrorAndMismatchedIdentityKey() async {
        let localIdentifiers = LocalIdentifiers.mock
        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        whoAmIManagerMock.whoAmIResponse = .value(.forUnitTest(localIdentifiers: localIdentifiers))
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers }
        var serverHasSameKeyResponses = [false]
        identityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _, _ in serverHasSameKeyResponses.popFirst()! }

        await runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
        XCTAssertEqual(serverHasSameKeyResponses, [])
    }

    func testNotUnlinkedIfIdentityKeyCheckingFails() async {
        let localIdentifiers = LocalIdentifiers.mock
        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        whoAmIManagerMock.whoAmIResponse = .value(.forUnitTest(localIdentifiers: localIdentifiers))
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers }
        var serverHasSameKeyResponses = [OWSGenericError("")]
        identityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _, _ in throw serverHasSameKeyResponses.popFirst()! }

        await runRunRun(recordIssue: true)

        XCTAssertTrue(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
        XCTAssertTrue(serverHasSameKeyResponses.isEmpty)
    }

    func testNotUnlinkedIfIdentityKeyMatches() async {
        let localIdentifiers = LocalIdentifiers.mock
        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        whoAmIManagerMock.whoAmIResponse = .value(.forUnitTest(localIdentifiers: localIdentifiers))
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers }
        var serverHasSameKeyResponses = [true]
        identityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _, _ in serverHasSameKeyResponses.popFirst()! }

        await runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
        XCTAssertEqual(serverHasSameKeyResponses, [])
    }

    func testEarlyExitIfPrimary() async {
        tsAccountManagerMock.registrationStateMock = { .registered }

        // This will fail if it doesn't early-exit, due to missing mocks.
        await runRunRun(recordIssue: false)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
    }

    func testEarlyExitIfNoError() async {
        messageProcessorMock.waitForFetchingAndProcessingMock = {}

        // This will fail if it doesn't early-exit, due to missing mocks.
        await runRunRun(recordIssue: false)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
    }

    /// It's important that we don't check for the decryption error until
    /// *after* the message queue is cleared, because that's where we'll
    /// register the error.
    func testChecksForDecryptionErrorAfterClearingQueue() async {
        messageProcessorMock.waitForFetchingAndProcessingMock = { [db, identityKeyMismatchManager] in
            await db!.awaitableWrite { tx in
                identityKeyMismatchManager!.recordSuspectedIssueWithPniIdentityKey(tx: tx)
            }
        }
        let localIdentifiers = LocalIdentifiers.mock
        whoAmIManagerMock.whoAmIResponse = .value(.forUnitTest(localIdentifiers: localIdentifiers))
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers }
        var serverHasSameKeyResponses = [false]
        identityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _, _ in serverHasSameKeyResponses.popFirst()! }

        await runRunRun(recordIssue: false)

        // Expect an unlink
        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
        XCTAssertEqual(serverHasSameKeyResponses, [])
    }

    /// Checks that multiple overlapping validation attempts are collapsed into
    /// one. Also checks that a subsequent validation runs.
    func testMultipleCallsResultInOneRun() async {
        let fetchingAndProcessing = CancellableContinuation<Void>()
        messageProcessorMock.waitForFetchingAndProcessingMock = { try! await fetchingAndProcessing.wait() }
        let localIdentifiers = LocalIdentifiers.mock
        whoAmIManagerMock.whoAmIResponse = .value(.forUnitTest(localIdentifiers: localIdentifiers))
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers }
        var serverHasSameKeyResponses = [true]
        identityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _, _ in serverHasSameKeyResponses.popFirst()! }

        await db.awaitableWrite { tx in
            identityKeyMismatchManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
        }
        await withTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                await self.identityKeyMismatchManager.validateLocalPniIdentityKeyIfNecessary()
            }
            taskGroup.addTask {
                await self.identityKeyMismatchManager.validateLocalPniIdentityKeyIfNecessary()
            }
            // One of the two Tasks should be able to complete immediately.
            _ = await taskGroup.next()
            // Once it does, we can let the other one complete as well.
            fetchingAndProcessing.resume(with: .success(()))
            _ = await taskGroup.next()
        }

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
        XCTAssertEqual(serverHasSameKeyResponses, [])

        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        whoAmIManagerMock.whoAmIResponse = .value(.forUnitTest(localIdentifiers: localIdentifiers))
        tsAccountManagerMock.localIdentifiersMock = { localIdentifiers }
        serverHasSameKeyResponses = [false]

        await runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
        XCTAssertEqual(serverHasSameKeyResponses, [])
    }
}

// MARK: - Mocks

private extension LocalIdentifiers {
    static let mock: LocalIdentifiers = .forUnitTests
}

private class MessageProcessorMock: IdentityKeyMismatchManagerImpl.Shims.MessageProcessor {
    var waitForFetchingAndProcessingMock: (() async throws(CancellationError) -> Void)!

    func waitForFetchingAndProcessing() async throws(CancellationError) {
        try await waitForFetchingAndProcessingMock!()
    }
}

private class IdentityKeyCheckerMock: IdentityKeyChecker {
    var serverHasSameKeyAsLocalMock: ((_ identity: OWSIdentity, _ localIdentifier: ServiceId) async throws -> Bool)!

    func serverHasSameKeyAsLocal(for identity: OWSIdentity, localIdentifier: ServiceId) async throws -> Bool {
        return try await serverHasSameKeyAsLocalMock!(identity, localIdentifier)
    }
}
