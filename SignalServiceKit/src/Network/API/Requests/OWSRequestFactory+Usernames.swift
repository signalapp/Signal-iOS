//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension OWSRequestFactory {
    private enum UsernameApiPaths {
        static let reserve = "v1/accounts/username/reserved"
        static let confirm = "v1/accounts/username/confirm"
        static let delete = "v1/accounts/username"
        static func aciLookup(forUsername username: String) -> String {
            "v1/accounts/username/\(username)"
        }
    }

    /// Attempt to reserve the given username. If successful, will return the
    /// username plus a numeric discriminator, along with a reservation token
    /// which can be subsequently used to confirm the reservation.
    ///
    /// A successful reservation is valid for 5 minutes.
    static func reserveUsernameRequest(
        desiredNickname: String
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.reserve)!
        let params: [String: Any] = [
            "nickname": desiredNickname
        ]

        return TSRequest(
            url: url,
            method: HTTPMethod.put.methodName,
            parameters: params
        )
    }

    /// Confirm the given previously-reserved username.
    ///
    /// - Parameter previouslyReservedUsername
    /// A username returned by a prior call to reserve a desired username,
    /// which should include a numeric discriminator.
    /// - Parameter reservationToken
    /// A token returned by a prior call to reserve a username.
    static func confirmReservedUsernameRequest(
        previouslyReservedUsername reservedUsername: String,
        reservationToken: String
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.confirm)!
        let params: [String: Any] = [
            "usernameToConfirm": reservedUsername,
            "reservationToken": reservationToken
        ]

        return TSRequest(
            url: url,
            method: HTTPMethod.put.methodName,
            parameters: params
        )
    }

    /// Delete the user's existing username.
    static func deleteExistingUsernameRequest() -> TSRequest {
        let url = URL(string: UsernameApiPaths.delete)!

        return TSRequest(
            url: url,
            method: HTTPMethod.delete.methodName,
            parameters: nil
        )
    }

    static func lookupAciUsernameRequest(
        usernameToLookup username: String
    ) -> TSRequest {
        let url = URL(string: UsernameApiPaths.aciLookup(forUsername: username))!

        return TSRequest(
            url: url,
            method: HTTPMethod.get.methodName,
            parameters: nil
        )
    }
}
