//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Manages transforming between username links and plaintext usernames.
///
/// Username links do not directly encode a username. Instead, they encode
/// "entropy data" and a "handle UUID", which can be used (with support from the
/// service) to produce a plaintext username.
///
/// Specifically, the server stores an encrypted form of the user's username
/// which can be retrieved using the handle and decrypted using the entropy.
/// Importantly, the entropy is never made available to the server, and
/// consequently the usernames themselves are not exposed to the server.
///
/// This indirection allows the user to rotate their username link without
/// changing their username, by instead providing the server with a new
/// encrypted username blob derived from new entropy data (which will
/// correspond to a new handle).
///
/// Assuming a given link is not outdated, i.e. the link's creator has not
/// rotated their link, the plaintext username is available by fetching the
/// encrypted username blob from the service using the handle in the link, and
/// decrypting it using the entropy in the link.
public protocol UsernameLinkManager {
    /// Generate the encrypted username.
    ///
    /// To be used in a link, this username should be uploaded to the service in
    /// exchange for a handle.
    ///
    /// - Parameter existingEntropy
    /// Specific entropy to use when encrypting the username. If this is passed,
    /// the `entropy` return value will be equivalent to it.
    func generateEncryptedUsername(
        username: String,
        existingEntropy: Data?
    ) throws -> (entropy: Data, encryptedUsername: Data)

    /// Uses the given link to fetch an encrypted username and decrypt it into a
    /// plaintext username.
    func decryptEncryptedLink(link: Usernames.UsernameLink) -> Promise<String?>
}

public final class UsernameLinkManagerImpl: UsernameLinkManager {
    private let db: DB
    private let apiClient: UsernameApiClient
    private let schedulers: Schedulers

    init(
        db: DB,
        apiClient: UsernameApiClient,
        schedulers: Schedulers
    ) {
        self.db = db
        self.apiClient = apiClient
        self.schedulers = schedulers
    }

    public func generateEncryptedUsername(
        username: String,
        existingEntropy: Data?
    ) throws -> (entropy: Data, encryptedUsername: Data) {
        let lscUsername = try LibSignalClient.Username(username)
        let (entropyBytes, encryptedUsernameBytes) = try lscUsername.createLink(
            previousEntropy: existingEntropy.map { [UInt8]($0) }
        )

        return (
            entropy: Data(entropyBytes),
            encryptedUsername: Data(encryptedUsernameBytes)
        )
    }

    public func decryptEncryptedLink(
        link: Usernames.UsernameLink
    ) -> Promise<String?> {
        return firstly(on: schedulers.sync) { () -> Promise<Data?> in
            return self.apiClient.getUsernameLink(handle: link.handle)
        }.map(on: schedulers.sync) { encryptedUsername throws -> String? in
            guard let encryptedUsername else {
                return nil
            }

            let lscUsername = try LibSignalClient.Username(
                fromLink: encryptedUsername,
                withRandomness: link.entropy
            )

            return lscUsername.value
        }
    }
}
