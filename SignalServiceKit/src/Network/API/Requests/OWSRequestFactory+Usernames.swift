//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension OWSRequestFactory {
    private enum UsernameApiPaths {
        static let reserveUsername = "v1/accounts/username_hash/reserve"
        static let confirmReservedUsername = "v1/accounts/username_hash/confirm"
        static let deleteUsername = "v1/accounts/username_hash"
        static func aciLookup(forUsernameHash usernameHash: String) -> String {
            "v1/accounts/username_hash/\(usernameHash)"
        }

        static let setUsernameLink = "v1/accounts/username_link"
        static func usernameLinkLookup(handle: UUID) -> String {
            "v1/accounts/username_link/\(handle.uuidString)"
        }
    }

    /// Attempt to reserve one of the given username hashes. If successful,
    /// will return the reserved hash.
    ///
    /// A successful reservation is valid for 5 minutes.
    static func reserveUsernameRequest(
        usernameHashes: [String]
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.reserveUsername)!
        let params: [String: Any] = [
            "usernameHashes": usernameHashes
        ]

        return TSRequest(
            url: url,
            method: HTTPMethod.put.methodName,
            parameters: params
        )
    }

    /// Confirm a previously-reserved username hash.
    ///
    /// - Parameter reservedUsernameHash
    /// The hash string from a hashed username returned by a prior call to
    /// reserve a desired nickname.
    /// - Parameter reservedUsernameZKProof
    /// The zkproof string from a hashed username returned by a prior call to
    /// reserve a desired nickname.
    /// - Parameter encryptedUsernameForLink
    /// An encrypted form of the reserved username to be used in a username
    /// link.
    static func confirmReservedUsernameRequest(
        reservedUsernameHash hashString: String,
        reservedUsernameZKProof proofString: String,
        encryptedUsernameForLink: Data
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.confirmReservedUsername)!
        let params: [String: String] = [
            "usernameHash": hashString,
            "zkProof": proofString,
            "encryptedUsername": encryptedUsernameForLink.asBase64Url
        ]

        return TSRequest(
            url: url,
            method: HTTPMethod.put.methodName,
            parameters: params
        )
    }

    /// Delete the user's server-stored username hash.
    static func deleteExistingUsernameRequest() -> TSRequest {
        let url = URL(string: UsernameApiPaths.deleteUsername)!

        return TSRequest(
            url: url,
            method: HTTPMethod.delete.methodName,
            parameters: nil
        )
    }

    /// Look up the ACI for the given username hash.
    static func lookupAciUsernameRequest(
        usernameHashToLookup usernameHash: String
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.aciLookup(
            forUsernameHash: usernameHash
        ))!

        let request = TSRequest(
            url: url,
            method: HTTPMethod.get.methodName,
            parameters: nil
        )

        request.shouldHaveAuthorizationHeaders = false

        return request
    }

    /// Store the given encrypted username for use in the authenticated user's
    /// username link.
    ///
    /// - SeeAlso
    /// ``Usernames.UsernameLink`` and ``UsernameLinkManager``.
    static func setUsernameLinkRequest(
        encryptedUsername: Data
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.setUsernameLink)!
        let params: [String: String] = [
            "usernameLinkEncryptedValue": encryptedUsername.asBase64Url
        ]

        let request = TSRequest(
            url: url,
            method: HTTPMethod.put.methodName,
            parameters: params
        )

        return request
    }

    /// Look up the encrypted username for the given username link handle.
    static func lookupUsernameLinkRequest(handle: UUID) -> TSRequest {
        let url = URL(string: UsernameApiPaths.usernameLinkLookup(
            handle: handle
        ))!

        let request = TSRequest(
            url: url,
            method: HTTPMethod.get.methodName,
            parameters: nil
        )

        request.shouldHaveAuthorizationHeaders = false

        return request
    }
}
