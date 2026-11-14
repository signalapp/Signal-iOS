//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

final class MockUsernamesService: AuthUsernamesService, UnauthUsernamesService {

    let setUsernameLinkMocks = AtomicValue<[(_ usernameCiphertext: Data, _ keepLinkHandle: Bool) async throws -> UUID]>([], lock: UnfairLock())

    func setUsernameLink(usernameCiphertext: Data, keepLinkHandle: Bool) async throws -> UUID {
        return try await setUsernameLinkMocks.update(block: { $0.removeFirst() })(usernameCiphertext, keepLinkHandle)
    }

    func reserveUsernameHashes(_ usernameHashes: [UsernameHash]) async throws -> UsernameHash { owsFail("Not implemented!") }

    let confirmUsernameMocks = AtomicValue<[(_ username: LibSignalClient.Username, _ usernameCiphertext: Data) async throws -> UUID]>([], lock: UnfairLock())

    func confirmUsername(
        _ username: LibSignalClient.Username,
        usernameCiphertext: Data,
    ) async throws -> UUID {
        return try await confirmUsernameMocks.update(block: { $0.removeFirst() })(username, usernameCiphertext)
    }

    let deleteUsernameHashMocks = AtomicValue<[() async throws -> Void]>([], lock: UnfairLock())

    func deleteUsernameHash() async throws {
        try await deleteUsernameHashMocks.update(block: { $0.removeFirst() })()
    }

    func deleteUsernameLink() async throws {
        owsFail("Not implemented!")
    }

    func lookUpUsernameHash(_ hash: UsernameHash) async throws -> Aci? {
        owsFail("Not implemented!")
    }

    let lookUpUsernameLinkMocks = AtomicValue<[(_ uuid: UUID, _ entropy: Data) async throws -> LibSignalClient.Username?]>([], lock: UnfairLock())

    func lookUpUsernameLink(_ uuid: UUID, entropy: Data) async throws -> LibSignalClient.Username? {
        return try await lookUpUsernameLinkMocks.update(block: { $0.removeFirst() })(uuid, entropy)
    }
}

#endif
