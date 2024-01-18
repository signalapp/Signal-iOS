//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

#if TESTABLE_BUILD

class MockUsernameApiClient: UsernameApiClient {

    // MARK: Confirm

    var confirmationResult: ConsumableMockPromise<Usernames.ApiClientConfirmationResult> = .unset
    var confirmReservedUsernameMock: ((
        _ reservedUsername: Usernames.HashedUsername,
        _ encryptedUsernameForLink: Data,
        _ chatServiceAuth: ChatServiceAuth
    ) -> Promise<Usernames.ApiClientConfirmationResult>)?

    func confirmReservedUsername(
        reservedUsername: Usernames.HashedUsername,
        encryptedUsernameForLink: Data,
        chatServiceAuth: ChatServiceAuth
    ) -> Promise<Usernames.ApiClientConfirmationResult> {
        if let methodMock = confirmReservedUsernameMock {
            return methodMock(reservedUsername, encryptedUsernameForLink, chatServiceAuth)
        }

        return confirmationResult.consumeIntoPromise()
    }

    // MARK: Delete

    var deletionResult: ConsumableMockPromise<Void> = .unset
    func deleteCurrentUsername() -> Promise<Void> {
        return deletionResult.consumeIntoPromise()
    }

    // MARK: Set link

    var setLinkResult: ConsumableMockPromise<UUID> = .unset
    func setUsernameLink(encryptedUsername: Data) -> Promise<UUID> {
        return setLinkResult.consumeIntoPromise()
    }

    // MARK: Unimplemented

    func reserveUsernameCandidates(usernameCandidates: Usernames.HashedUsername.GeneratedCandidates) -> Promise<Usernames.ApiClientReservationResult> { owsFail("Not implemented!") }
    func lookupAci(forHashedUsername hashedUsername: Usernames.HashedUsername) -> Promise<Aci?> { owsFail("Not implemented!") }
    func getUsernameLink(handle: UUID) -> Promise<Data?> { owsFail("Not implemented!") }
}

#endif
