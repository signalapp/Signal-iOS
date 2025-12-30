//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

#if TESTABLE_BUILD

class MockUsernameApiClient: UsernameApiClient {

    // MARK: Confirm

    var confirmReservedUsernameMocks = [(
        reservedUsername: Usernames.HashedUsername,
        encryptedUsernameForLink: Data,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> Usernames.ApiClientConfirmationResult]()

    func confirmReservedUsername(
        reservedUsername: Usernames.HashedUsername,
        encryptedUsernameForLink: Data,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> Usernames.ApiClientConfirmationResult {
        return try await confirmReservedUsernameMocks.removeFirst()(reservedUsername, encryptedUsernameForLink, chatServiceAuth)
    }

    // MARK: Delete

    var deleteCurrentUsernameMocks = [() async throws -> Void]()
    func deleteCurrentUsername() async throws {
        try await deleteCurrentUsernameMocks.removeFirst()()
    }

    // MARK: Set link

    var setUsernameLinkMocks = [(
        encryptedUsername: Data,
        keepLinkHandle: Bool,
    ) async throws -> UUID]()

    func setUsernameLink(encryptedUsername: Data, keepLinkHandle: Bool) async throws -> UUID {
        return try await setUsernameLinkMocks.removeFirst()(encryptedUsername, keepLinkHandle)
    }

    // MARK: Unimplemented

    func reserveUsernameCandidates(usernameCandidates: Usernames.HashedUsername.GeneratedCandidates) async throws -> Usernames.ApiClientReservationResult { owsFail("Not implemented!") }
    func lookupAci(forHashedUsername hashedUsername: Usernames.HashedUsername) async throws -> Aci? { owsFail("Not implemented!") }
    func getUsernameLink(handle: UUID) async throws -> Data? { owsFail("Not implemented!") }
}

#endif
