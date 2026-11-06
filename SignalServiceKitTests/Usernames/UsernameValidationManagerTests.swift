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
    private var mockUsernamesService: MockUsernamesService!
    private var mockWhoAmIManager: MockWhoAmIManager!

    private var validationManager: UsernameValidationManagerImpl!

    override func setUp() {
        mockDB = InMemoryDB()
        mockLocalUsernameManager = MockLocalUsernameManager()
        mockMessageProcessor = MockMessageProcessor()
        mockStorageServiceManager = MockStorageServiceManager()
        mockUsernamesService = MockUsernamesService()
        mockWhoAmIManager = MockWhoAmIManager()

        validationManager = UsernameValidationManagerImpl(context: .init(
            database: mockDB,
            localUsernameManager: mockLocalUsernameManager,
            messageProcessor: mockMessageProcessor,
            serviceProvider: MockServiceProvider(mockServices: [mockUsernamesService!]),
            storageServiceManager: mockStorageServiceManager,
            whoAmIManager: mockWhoAmIManager,
        ))
    }

    override func tearDown() {
        mockWhoAmIManager.whoAmIResponse.ensureUnset()
        owsPrecondition(!mockMessageProcessor.canWait)
        mockStorageServiceManager.pendingRestoreResult.ensureUnset()
        owsPrecondition(mockUsernamesService.lookUpUsernameLinkMocks.get().isEmpty)
    }

    func testUnsetValidationSuccessful() async throws {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.noRemoteUsername)

        let isValid = try await validationManager.validateUsername()
        XCTAssertTrue(isValid)

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUnsetValidationFailsIfWhoamiFails() async {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .error()

        let isValid = await Result(catching: { try await validationManager.validateUsername() })
        XCTAssertThrowsError(try isValid.get())

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUnsetValidationFailsIfRemoteUsernamePresent() async throws {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))

        let isValid = try await validationManager.validateUsername()
        XCTAssertFalse(isValid)

        mockDB.read { tx in
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationSuccessful() async throws {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked,
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernamesService.lookUpUsernameLinkMocks.set([{ _, _ in try! LibSignalClient.Username("boba_fett.42") }])

        let isValid = try await validationManager.validateUsername()
        XCTAssertTrue(isValid)

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationFailsIfWhoamiFails() async {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked,
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .error()

        let isValid = await Result(catching: { try await validationManager.validateUsername() })
        XCTAssertThrowsError(try isValid.get())

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationFailsIfRemoteUsernameMismatch() async throws {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked,
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.43"))

        let isValid = try await validationManager.validateUsername()
        XCTAssertFalse(isValid)

        mockDB.read { tx in
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationFailsIfLinkDecryptFails() async {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked,
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernamesService.lookUpUsernameLinkMocks.set([{ _, _ in throw OWSGenericError("") }])

        let isValid = await Result(catching: { try await validationManager.validateUsername() })
        XCTAssertThrowsError(try isValid.get())

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testAvailableValidationFailsIfUsernameLinkMismatch() async throws {
        mockLocalUsernameManager.startingUsernameState = .available(
            username: "boba_fett.42",
            usernameLink: .mocked,
        )
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernamesService.lookUpUsernameLinkMocks.set([{ _, _ in try! LibSignalClient.Username("boba_fett.43") }])

        let isValid = try await validationManager.validateUsername()
        XCTAssertFalse(isValid)

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationSuccessful() async throws {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.42"))

        let isValid = try await validationManager.validateUsername()
        XCTAssertTrue(isValid)

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationFailsIfWhoamiFails() async {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .error()

        let isValid = await Result(catching: { try await validationManager.validateUsername() })
        XCTAssertThrowsError(try isValid.get())

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationFailsIfRemoteUsernameMismatch() async throws {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoAmIResponse = .value(.withRemoteUsername("boba_fett.43"))

        let isValid = try await validationManager.validateUsername()
        XCTAssertFalse(isValid)

        mockDB.read { tx in
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUsernameCorruptedValidationSuccessful() async throws {
        mockLocalUsernameManager.startingUsernameState = .usernameAndLinkCorrupted
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .value(())

        let isValid = try await validationManager.validateUsername()
        XCTAssertFalse(isValid)

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testValidationFailsIfStorageServiceRestoreFails() async {
        mockLocalUsernameManager.startingUsernameState = .usernameAndLinkCorrupted
        mockMessageProcessor.canWait = true
        mockStorageServiceManager.pendingRestoreResult = .error()

        let isValid = await Result(catching: { try await validationManager.validateUsername() })
        XCTAssertThrowsError(try isValid.get())

        mockDB.read { tx in
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }
}

private extension AccountIdentityResponse {
    static let noRemoteUsername = AccountIdentityResponse(localIdentifiers: .forUnitTests)

    static func withRemoteUsername(_ remoteUsername: String) -> AccountIdentityResponse {
        return AccountIdentityResponse(
            localIdentifiers: .forUnitTests,
            usernameHash: try! LibSignalClient.Username(remoteUsername).hash,
        )
    }
}

private extension Usernames.UsernameLink {
    static var mocked: UsernameLink {
        return UsernameLink(
            handle: UUID(),
            entropy: try! UsernameLink.Entropy(rawValue: Data(repeating: 5, count: 32)),
        )
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

        func waitForFetchingAndProcessing() async throws(CancellationError) {
            owsPrecondition(canWait)
            canWait = false
        }
    }
}
