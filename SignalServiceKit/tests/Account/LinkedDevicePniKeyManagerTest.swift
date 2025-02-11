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
    private var kvStore: TestKVStore!
    private var messageProcessorMock: MessageProcessorMock!
    private var pniIdentityKeyCheckerMock: PniIdentityKeyCheckerMock!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var tsAccountManagerMock: MockTSAccountManager!

    private var linkedDevicePniKeyManager: LinkedDevicePniKeyManagerImpl!

    private var isMarkedDeregistered: Bool = false

    override func setUp() {
        db = InMemoryDB()
        kvStore = TestKVStore(db: db)
        messageProcessorMock = MessageProcessorMock()
        pniIdentityKeyCheckerMock = PniIdentityKeyCheckerMock()
        registrationStateChangeManagerMock = .init()
        tsAccountManagerMock = .init()

        registrationStateChangeManagerMock.setIsDeregisteredOrDelinkedMock = { [weak self] isDeregistered in
            self?.isMarkedDeregistered = isDeregistered
        }

        tsAccountManagerMock.registrationStateMock = { .provisioned }

        linkedDevicePniKeyManager = LinkedDevicePniKeyManagerImpl(
            db: db,
            messageProcessor: messageProcessorMock,
            pniIdentityKeyChecker: pniIdentityKeyCheckerMock,
            registrationStateChangeManager: registrationStateChangeManagerMock,
            tsAccountManager: tsAccountManagerMock
        )
    }

    private func runRunRun(recordIssue: Bool) async {
        if recordIssue {
            await db.awaitableWrite { tx in
                linkedDevicePniKeyManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
            }
        }
        await linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary()
    }

    func testDoesntRecordIfPrimaryDevice() async {
        tsAccountManagerMock.registrationStateMock = { .registered }

        await db.awaitableWrite { tx in
            return linkedDevicePniKeyManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
        }
        await linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary()

        XCTAssertFalse(kvStore.hasDecryptionError())
    }

    func testUnlinkedIfDecryptionErrorAndMissingPni() async {
        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        tsAccountManagerMock.localIdentifiersMock = { .missingPni }

        await runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
    }

    func testUnlinkedIfDecryptionErrorAndMismatchedIdentityKey() async {
        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        var serverHasSameKeyResponses = [false]
        pniIdentityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _ in serverHasSameKeyResponses.popFirst()! }

        await runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
        XCTAssertEqual(serverHasSameKeyResponses, [])
    }

    func testNotUnlinkedIfIdentityKeyCheckingFails() async {
        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        var serverHasSameKeyResponses = [OWSGenericError("")]
        pniIdentityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _ in throw serverHasSameKeyResponses.popFirst()! }

        await runRunRun(recordIssue: true)

        XCTAssertTrue(kvStore.hasDecryptionError())
        XCTAssertFalse(self.isMarkedDeregistered)
        XCTAssertTrue(serverHasSameKeyResponses.isEmpty)
    }

    func testNotUnlinkedIfIdentityKeyMatches() async {
        messageProcessorMock.waitForFetchingAndProcessingMock = {}
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        var serverHasSameKeyResponses = [true]
        pniIdentityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _ in serverHasSameKeyResponses.popFirst()! }

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
        messageProcessorMock.waitForFetchingAndProcessingMock = { [db, linkedDevicePniKeyManager] in
            await db!.awaitableWrite { tx in
                linkedDevicePniKeyManager!.recordSuspectedIssueWithPniIdentityKey(tx: tx)
            }
        }
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        var serverHasSameKeyResponses = [false]
        pniIdentityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _ in serverHasSameKeyResponses.popFirst()! }

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
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        var serverHasSameKeyResponses = [true]
        pniIdentityKeyCheckerMock.serverHasSameKeyAsLocalMock = { _ in serverHasSameKeyResponses.popFirst()! }

        await db.awaitableWrite { tx in
            linkedDevicePniKeyManager.recordSuspectedIssueWithPniIdentityKey(tx: tx)
        }
        await withTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                await self.linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary()
            }
            taskGroup.addTask {
                await self.linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary()
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
        tsAccountManagerMock.localIdentifiersMock = { .mock }
        serverHasSameKeyResponses = [false]

        await runRunRun(recordIssue: true)

        XCTAssertFalse(kvStore.hasDecryptionError())
        XCTAssertTrue(self.isMarkedDeregistered)
        XCTAssertEqual(serverHasSameKeyResponses, [])
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
    var waitForFetchingAndProcessingMock: (() async -> Void)!

    func waitForFetchingAndProcessing() async {
        await waitForFetchingAndProcessingMock!()
    }
}

private class PniIdentityKeyCheckerMock: PniIdentityKeyChecker {
    var serverHasSameKeyAsLocalMock: ((_ localPni: Pni) async throws -> Bool)!

    func serverHasSameKeyAsLocal(localPni: Pni) async throws -> Bool {
        return try await serverHasSameKeyAsLocalMock!(localPni)
    }
}
