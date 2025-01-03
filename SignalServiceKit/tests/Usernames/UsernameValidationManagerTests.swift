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
        mockWhoAmIManager.whoamiResponse.ensureUnset()
        mockMessageProcessor.processingResult.ensureUnset()
        mockStorageServiceManager.pendingRestoreResult.ensureUnset()
        mockUsernameLinkManager.decryptLinkResult.ensureUnset()
    }

    func testUnsetValidationSuccessful() async {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .value(.noRemoteUsername)

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNotNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUnsetValidationFailsIfWhoamiFails() async {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .error()

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUnsetValidationFailsIfRemoteUsernamePresent() async {
        mockLocalUsernameManager.startingUsernameState = .unset
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .value(.withRemoteUsername("boba_fett.42"))

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
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernameLinkManager.decryptLinkResult = .value("boba_fett.42")

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
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .error()

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
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .value(.withRemoteUsername("boba_fett.43"))

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
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernameLinkManager.decryptLinkResult = .error()

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
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .value(.withRemoteUsername("boba_fett.42"))
        mockUsernameLinkManager.decryptLinkResult = .value("boba_fett.43")

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationSuccessful() async {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .value(.withRemoteUsername("boba_fett.42"))

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNotNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationFailsIfWhoamiFails() async {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .error()

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testLinkCorruptedValidationFailsIfRemoteUsernameMismatch() async {
        mockLocalUsernameManager.startingUsernameState = .linkCorrupted(username: "boba_fett.42")
        mockMessageProcessor.processingResult = .value(())
        mockStorageServiceManager.pendingRestoreResult = .value(())
        mockWhoAmIManager.whoamiResponse = .value(.withRemoteUsername("boba_fett.43"))

        await validationManager.validateUsernameIfNecessary()

        mockDB.read { tx in
            XCTAssertNil(validationManager.lastValidationDate(tx))
            XCTAssertTrue(mockLocalUsernameManager.didSetCorruptedUsername)
            XCTAssertFalse(mockLocalUsernameManager.didSetCorruptedLink)
        }
    }

    func testUsernameCorruptedValidationSuccessful() async {
        mockLocalUsernameManager.startingUsernameState = .usernameAndLinkCorrupted
        mockMessageProcessor.processingResult = .value(())
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
        mockMessageProcessor.processingResult = .value(())
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
                date: Date().addingTimeInterval(-kDayInterval).addingTimeInterval(-1),
                tx
            )
        }

        mockLocalUsernameManager.startingUsernameState = .usernameAndLinkCorrupted
        mockMessageProcessor.processingResult = .value(())
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

        public func waitForPendingRestores() -> Promise<Void> {
            return pendingRestoreResult.consumeIntoPromise()
        }
    }

    private class MockMessageProcessor: Usernames.Validation.Shims.MessageProcessor {
        var processingResult: ConsumableMockGuarantee<Void> = .unset

        public func waitForFetchingAndProcessing() -> Guarantee<Void> {
            return processingResult.consumeIntoGuarantee()
        }
    }

    private class MockWhoAmIManager: WhoAmIManager {
        var whoamiResponse: ConsumableMockPromise<WhoAmIResponse> = .unset

        func makeWhoAmIRequest() async throws -> WhoAmIResponse {
            return try await whoamiResponse.consumeIntoPromise().awaitable()
        }
    }
}
