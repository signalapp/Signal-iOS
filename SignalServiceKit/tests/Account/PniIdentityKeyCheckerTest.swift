//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class PniIdentityKeyCheckerTest: XCTestCase {
    private var db: InMemoryDB!
    private var identityManagerMock: IdentityManagerMock!
    private var profileFetcherMock: ProfileFetcherMock!
    private var pniIdentityKeyChecker: PniIdentityKeyCheckerImpl!

    override func setUp() {
        db = InMemoryDB()
        identityManagerMock = IdentityManagerMock()
        profileFetcherMock = ProfileFetcherMock()
        pniIdentityKeyChecker = PniIdentityKeyCheckerImpl(
            db: db,
            identityManager: identityManagerMock,
            profileFetcher: profileFetcherMock,
            schedulers: DispatchQueueSchedulers()
        )
    }

    override func tearDown() {
        profileFetcherMock.profileFetchResult.ensureUnset()
    }

    /// Runs the identity key checker.
    /// - Returns
    /// Whether or not the checker found a match. Throws if there was an error
    /// while running the checker.
    private func checkForMatch() async throws -> Bool {
        let promise = db.read { tx -> Promise<Bool> in
            return pniIdentityKeyChecker.serverHasSameKeyAsLocal(
                localPni: Pni.randomForTesting(),
                tx: tx
            )
        }
        return try await promise.awaitable()
    }

    func testDoesNotMatchIfLocalPniIdentityKeyMissing() async throws {
        let result = try await checkForMatch()
        XCTAssertFalse(result)
    }

    func testErrorMatchingIfProfileFetchFails() async {
        identityManagerMock.pniIdentityKey = try! IdentityKey(bytes: [0x05] + Data(repeating: 0, count: 32))
        profileFetcherMock.profileFetchResult = .error()

        let result = await Result { try await checkForMatch() }
        XCTAssertThrowsError(try result.get())
    }

    func testDoesNotMatchIfRemotePniIdentityKeyMissing() async throws {
        identityManagerMock.pniIdentityKey = try! IdentityKey(bytes: [0x05] + Data(repeating: 0, count: 32))
        profileFetcherMock.profileFetchResult = .value(nil)

        let result = try await checkForMatch()
        XCTAssertFalse(result)
    }

    func testDoesNotMatchIfRemotePniIdentityKeyDiffers() async throws {
        identityManagerMock.pniIdentityKey = try! IdentityKey(bytes: [0x05] + Data(repeating: 0, count: 32))
        profileFetcherMock.profileFetchResult = .value(try! IdentityKey(bytes: [0x05] + Data(repeating: 1, count: 32)))

        let result = try await checkForMatch()
        XCTAssertFalse(result)
    }

    func testMatchesIfRemotePniIdentityKeyMatches() async throws {
        identityManagerMock.pniIdentityKey = try! IdentityKey(bytes: [0x05] + Data(repeating: 0, count: 32))
        profileFetcherMock.profileFetchResult = .value(try! IdentityKey(bytes: [0x05] + Data(repeating: 0, count: 32)))

        let result = try await checkForMatch()
        XCTAssertTrue(result)
    }
}

// MARK: - Mocks

// MARK: IdentityManager

private class IdentityManagerMock: PniIdentityKeyCheckerImpl.Shims.IdentityManager {
    var pniIdentityKey: IdentityKey?

    func pniIdentityKey(tx _: DBReadTransaction) -> IdentityKey? {
        return pniIdentityKey
    }
}

// MARK: ProfileFetcher

private class ProfileFetcherMock: PniIdentityKeyCheckerImpl.Shims.ProfileFetcher {
    var profileFetchResult: ConsumableMockPromise<IdentityKey?> = .unset

    func fetchPniIdentityPublicKey(localPni: Pni) async throws -> IdentityKey? {
        return try await profileFetchResult.consumeIntoPromise().awaitable()
    }
}
