//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class IdentityKeyCheckerTest: XCTestCase {
    private var db: InMemoryDB!
    private var identityKeyChecker: IdentityKeyCheckerImpl!
    private var identityManagerMock: MockIdentityManager!
    private var profileFetcherMock: ProfileFetcherMock!

    private var identityKey1: ECKeyPair!
    private var identityKey2: ECKeyPair!

    override func setUp() {
        db = InMemoryDB()
        let recipientDbTable = RecipientDatabaseTable()
        let recipientFetcher = RecipientFetcher(
            recipientDatabaseTable: recipientDbTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let recipientIdFinder = RecipientIdFinder(
            recipientDatabaseTable: recipientDbTable,
            recipientFetcher: recipientFetcher,
        )
        identityManagerMock = .init(recipientIdFinder: recipientIdFinder)
        profileFetcherMock = ProfileFetcherMock()
        identityKeyChecker = IdentityKeyCheckerImpl(
            db: db,
            identityManager: identityManagerMock,
            profileFetcher: profileFetcherMock,
        )
        identityKey1 = ECKeyPair.generateKeyPair()
        identityKey2 = ECKeyPair.generateKeyPair()
    }

    override func tearDown() {
        profileFetcherMock.profileFetchResult.ensureUnset()
    }

    /// Runs the identity key checker.
    /// - Returns
    /// Whether or not the checker found a match. Throws if there was an error
    /// while running the checker.
    private func checkForMatch() async throws -> Bool {
        return try await identityKeyChecker.serverHasSameKeyAsLocal(for: .pni, localIdentifier: Pni.randomForTesting())
    }

    func testErrorMatchingIfProfileFetchFails() async {
        identityManagerMock.identityKeyPairs[.pni] = identityKey1
        profileFetcherMock.profileFetchResult = .error()

        let result = await Result { try await checkForMatch() }
        XCTAssertThrowsError(try result.get())
    }

    func testDoesNotMatchIfRemotePniIdentityKeyDiffers() async throws {
        identityManagerMock.identityKeyPairs[.pni] = identityKey1
        profileFetcherMock.profileFetchResult = .value(identityKey2.identityKeyPair.identityKey)

        let result = try await checkForMatch()
        XCTAssertFalse(result)
    }

    func testMatchesIfRemotePniIdentityKeyMatches() async throws {
        identityManagerMock.identityKeyPairs[.pni] = identityKey1
        profileFetcherMock.profileFetchResult = .value(identityKey1.identityKeyPair.identityKey)

        let result = try await checkForMatch()
        XCTAssertTrue(result)
    }
}

// MARK: - Mocks

// MARK: ProfileFetcher

private class ProfileFetcherMock: IdentityKeyCheckerImpl.Shims.ProfileFetcher {
    var profileFetchResult: ConsumableMockPromise<IdentityKey> = .unset

    func fetchIdentityPublicKey(serviceId: ServiceId) async throws -> IdentityKey {
        return try await profileFetchResult.consumeIntoPromise().awaitable()
    }
}
