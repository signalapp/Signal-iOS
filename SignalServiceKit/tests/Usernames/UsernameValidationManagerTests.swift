//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class UsernameValidationManagerTest: XCTestCase {
    typealias Username = String

    private var mockContext: UsernameValidationManagerImpl.Context!
    private var mockDB: (any DB)!
    private var mockLocalUsernameManager: MockLocalUsernameManager!
    private var mockMessageProcessor: MockMessageProcessor!
    private var mockStorageServiceManager: MockStorageServiceManager!
    private var mockUsernameLinkManager: MockUsernameLinkManager!
    private var mockWhoAmIManager: MockWhoAmIManager!

    private var validationManager: UsernameValidationManagerImpl!

    override func setUp() {
        mockDB = InMemoryDB()
        mockLocalUsernameManager = MockLocalUsernameManager()
        mockMessageProcessor = MockMessageProcessor()
        mockStorageServiceManager = MockStorageServiceManager()
        mockUsernameLinkManager = MockUsernameLinkManager()
        mockWhoAmIManager = MockWhoAmIManager()

        validationManager = UsernameValidationManagerImpl(context: .init(
            database: mockDB,
            localUsernameManager: mockLocalUsernameManager,
            messageProcessor: mockMessageProcessor,
            storageServiceManager: mockStorageServiceManager,
            usernameLinkManager: mockUsernameLinkManager,
            whoAmIManager: mockWhoAmIManager
        ))
    }

    override func tearDown() {
        mockWhoAmIManager.whoAmIResponse.ensureUnset()
        owsPrecondition(!mockMessageProcessor.canWait)
        mockStorageServiceManager.pendingRestoreResult.ensureUnset()
        owsPrecondition(mockUsernameLinkManager.decryptEncryptedLinkMocks.isEmpty)
    }

    func testUnsetValidationSuccessful() async {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.noRemoteUsername)

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNotNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUnsetValidationFailsIfWhoamiFails() async {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .error()

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUnsetValidationFailsIfRemoteUsernamePresent() async {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationSuccessful() async {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernameLinkManager.decryptEncryptedLinkMocks = [{ _ in "boba_fett.42" }]

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNotNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationFailsIfWhoamiFails() async {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .error()

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationFailsIfRemoteUsernameMismatch() async {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.43"))

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationFailsIfLinkDecryptFails() async {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernameLinkManager.decryptEncryptedLinkMocks = [{ _ in throw OWSGenericError("") }]

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationFailsIfUsernameLinkMismatch() async {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernameLinkManager.decryptEncryptedLinkMocks = [{ _ in "boba_fett.43" }]

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationSuccessful() async {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNotNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationFailsIfWhoamiFails() async {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .error()

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationFailsIfRemoteUsernameMismatch() async {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.43"))

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUsernameCorruptedValidationSuccessful() async {
        mockLocalUsernameManager.startingUsernameState = .usernameAndLinkCorrupted
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNotNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testValidationFailsIfStorageServiceRestoreFails() async {
        mockLocalUsernameManager.startingUsernameState = .usernameAndLinkCorrupted
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .error()

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testValidationSkippedIfValidatedRecently() async {
        mockDB.write { tx in
            validationManager.setLastValidation(
                date: Date().addingTimeInterval(-100),
                tx
            )
        }

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNotNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testValidationFiresIfValidatedAWhileAgo() async {
        mockDB.write { tx in
            validationManager.setLastValidation(
                date: Date().addingTimeInterval(-.day).addingTimeInterval(-1),
                tx
            )
        }

        mockLocalUsernameManager.startingUsernameState = .usernameAndLinkCorrupted
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNotNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }
}

private extension WhoAmIManager.WhoAmIResponse {
    static let noRemoteUsername: Self = .init(
        aci: Aci.randomForTesting(),
        pni: Pni.randomForTesting(),
        e164: E164("+16125550101")!,
        usernameHash: nil,
        entitlements: Entitlements(backup: nil, badges: [])
    )

    static func withRemoteUsername(_ remoteUsername: String) -> Self {
        return .init(
            aci: Aci.randomForTesting(),
            pni: Pni.randomForTesting(),
            e164: E164("+16125550101")!,
            usernameHash: try! Usernames.HashedUsername(forUsername: remoteUsername).hashString,
            entitlements: Entitlements(backup: nil, badges: [])
        )
    }
}

private extension Usernames.UsernameLink {
    static var mocked: Usernames.UsernameLink {
        return Usernames.UsernameLink(
            handle: UUID(),
            entropy: Data(repeating: 5, count: 32)
        )!
    }
}

// MARK: - Mocks

extension UsernameValidationManagerTest {
    private class MockStorageServiceManager: Usernames.Validation.Shims.StorageServiceManager {
        var pendingRestoreResult: ConsumableMockPromise<Void> = .unset

        func waitForPendingRestores() async throws {
            return try await pendingRestoreResult.consumeIntoPromise().awaitable()
        }
    }

    private class MockMessageProcessor: Usernames.Validation.Shims.MessageProcessor {
        var canWait = false

        public func waitForFetchingAndProcessing() async throws(CancellationError) {
            owsPrecondition(canWait)
            canWait = false
        }
    }
}
