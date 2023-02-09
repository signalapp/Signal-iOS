//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension OWSRequestFactory {
    private enum UsernameApiPaths {
        static let reserve = "v1/accounts/username_hash/reserve"
        static let confirm = "v1/accounts/username_hash/confirm"
        static let delete = "v1/accounts/username_hash"
        static func aciLookup(forUsernameHash usernameHash: String) -> String {
            "v1/accounts/username_hash/\(usernameHash)"
        }
    }

    /// Attempt to reserve one of the given username hashes. If successful,
    /// will return the reserved hash.
    ///
    /// A successful reservation is valid for 5 minutes.
    static func reserveUsernameRequest(
        usernameHashes: [String]
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.reserve)!
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
    static func confirmReservedUsernameRequest(
        reservedUsernameHash hashString: String,
        reservedUsernameZKProof proofString: String
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.confirm)!
        let params: [String: Any] = [
            "usernameHash": hashString,
            "zkProof": proofString
        ]

        return TSRequest(
            url: url,
            method: HTTPMethod.put.methodName,
            parameters: params
        )
    }

    /// Delete the user's server-stored username hash.
    static func deleteExistingUsernameRequest() -> TSRequest {
        let url = URL(string: UsernameApiPaths.delete)!

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
}
