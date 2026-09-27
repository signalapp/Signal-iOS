//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum AuthedAccount {
    /// Will use info present on TSAccountManager
    case implicit
    case explicit(Explicit)

    public struct Explicit {
        public let aci: Aci
        public let phoneNumber: LocalIdentifiers.PhoneNumber
        public let deviceId: DeviceId
        public var isPrimaryDevice: Bool { self.deviceId == .primary }
        public let authPassword: String

        public init(
            aci: Aci,
            phoneNumber: LocalIdentifiers.PhoneNumber,
            deviceId: DeviceId,
            authPassword: String,
        ) {
            self.aci = aci
            self.phoneNumber = phoneNumber
            self.deviceId = deviceId
            self.authPassword = authPassword
        }
    }

    public func orIfImplicitUse(_ other: AuthedAccount) -> AuthedAccount {
        switch (self, other) {
        case (.explicit, _):
            return self
        case (_, .explicit):
            return other
        case (.implicit, .implicit):
            return other
        }
    }

    public func isAddressForLocalUser(_ address: SignalServiceAddress) -> Bool {
        switch self {
        case .implicit:
            return false
        case let .explicit(info):
            return info.isAddressForLocalUser(address)
        }
    }

    public var chatServiceAuth: ChatServiceAuth {
        switch self {
        case .implicit:
            return .implicit()
        case let .explicit(info):
            return info.chatServiceAuth
        }
    }
}

extension AuthedAccount.Explicit {

    public func isAddressForLocalUser(_ address: SignalServiceAddress) -> Bool {
        return localIdentifiers.contains(address: address)
    }

    public var localIdentifiers: LocalIdentifiers {
        return LocalIdentifiers(aci: aci, phoneNumber: phoneNumber)
    }

    public var chatServiceAuth: ChatServiceAuth {
        return .explicit(aci: aci, deviceId: deviceId, password: authPassword)
    }
}
