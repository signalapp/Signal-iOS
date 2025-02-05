//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// Credentials to use on a TSRequest to the chat server.
public class ChatServiceAuth: Equatable, Hashable {

    public enum Credentials: Equatable {
        case implicit
        case explicit(username: String, password: String)
    }

    public let credentials: Credentials

    private init(_ credentials: Credentials) {
        self.credentials = credentials
    }

    /// Will use auth credentials present on TSAccountManager
    public static func implicit() -> ChatServiceAuth {
        return ChatServiceAuth(.implicit)
    }

    public typealias DeviceId = AuthedDevice.DeviceId

    public static func explicit(
        aci: Aci,
        deviceId: DeviceId,
        password: String
    ) -> ChatServiceAuth {
        return ChatServiceAuth(.explicit(username: deviceId.authUsername(aci: aci), password: password))
    }

    public func hash(into hasher: inout Hasher) {
        switch credentials {
        case .implicit:
            break
        case let .explicit(username, password):
            hasher.combine(username)
            hasher.combine(password)
        }
    }

    public static func == (lhs: ChatServiceAuth, rhs: ChatServiceAuth) -> Bool {
        lhs.credentials == rhs.credentials
    }

    public func orIfImplicitUse(_ other: ChatServiceAuth) -> ChatServiceAuth {
        switch (self.credentials, other.credentials) {
        case (.explicit, _):
            return self
        case (_, .explicit):
            return other
        case (.implicit, .implicit):
            return other
        }
    }
}

extension TSRequest {
    public func setAuth(_ auth: ChatServiceAuth) {
        switch auth.credentials {
        case .implicit:
            break
        case let .explicit(username, password):
            self.authUsername = username
            self.authPassword = password
        }
    }
}
