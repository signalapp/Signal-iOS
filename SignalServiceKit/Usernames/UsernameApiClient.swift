//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

/// Manages usernames-related API calls.
public protocol UsernameApiClient {

    // MARK: Selection

    /// Reserves one of the given username candidates.
    ///
    /// - Parameter usernameCandidates
    /// Candidate usernames to reserve.
    /// - Parameter attemptId
    /// An ID for this attempt, to later disambiguate between multiple
    /// potentially-overlapping attempts.
    func reserveUsernameCandidates(
        usernameCandidates: Usernames.HashedUsername.GeneratedCandidates
    ) -> Promise<Usernames.ApiClientReservationResult>

    /// Confirms the given username, which must have previously been reserved.
    ///
    /// - Parameter encryptedUsernameForLink
    /// An encrypted form of this username for use in a username link.
    func confirmReservedUsername(
        reservedUsername: Usernames.HashedUsername,
        encryptedUsernameForLink: Data
    ) -> Promise<Usernames.ApiClientConfirmationResult>

    // MARK: Deletion

    /// Delete the username and username link for the current user.
    func deleteCurrentUsername() -> Promise<Void>

    // MARK: Lookup

    /// Looks up the ACI corresponding to the given username, if one exists.
    func lookupAci(
        forHashedUsername hashedUsername: Usernames.HashedUsername
    ) -> Promise<FutureAci?>

    // MARK: Links

    /// Set the encrypted username for the local user's username link.
    ///
    /// - SeeAlso
    /// ``Usernames.UsernameLink`` and ``UsernameLinkManager``.
    ///
    /// - Returns
    /// The handle for the local user's encrypted username.
    func setUsernameLink(encryptedUsername: Data) -> Promise<UUID>

    /// Gets the encrypted username for the given handle, if any.
    ///
    /// - SeeAlso
    /// ``Usernames.UsernameLink`` and ``UsernameLinkManager``.
    func getUsernameLink(handle: UUID) -> Promise<Data?>
}

public extension Usernames {
    enum ApiClientReservationResult {
        case successful(
            username: Usernames.ParsedUsername,
            hashedUsername: Usernames.HashedUsername
        )
        case rejected
        case rateLimited
    }

    enum ApiClientConfirmationResult {
        /// The reservation was successfully confirmed.
        case success(usernameLinkHandle: UUID)
        /// The reservation was rejected. This may be because we no longer hold
        /// the reservation, the reservation lapsed, or something about the
        /// reservation was invalid.
        case rejected
        /// The reservation failed because we have been rate-limited.
        case rateLimited
    }
}
