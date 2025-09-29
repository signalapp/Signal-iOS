//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

final public class AuthedAccount: Hashable, Equatable {

    public struct Explicit: Equatable {
        public let aci: Aci
        public let pni: Pni
        public let e164: E164
        public let deviceId: DeviceId
        public let authPassword: String

        public init(
            aci: Aci,
            pni: Pni,
            e164: E164,
            deviceId: DeviceId,
            authPassword: String
        ) {
            self.aci = aci
            self.pni = pni
            self.e164 = e164
            self.deviceId = deviceId
            self.authPassword = authPassword
        }
    }

    public enum Info: Equatable {
        case implicit
        case explicit(Explicit)
    }

    public let info: Info

    private init(_ info: Info) {
        self.info = info
    }

    /// Will use info present on TSAccountManager
    public static func implicit() -> AuthedAccount {
        return AuthedAccount(.implicit)
    }

    public static func explicit(
        aci: Aci,
        pni: Pni,
        e164: E164,
        deviceId: DeviceId,
        authPassword: String
    ) -> AuthedAccount {
        return AuthedAccount(.explicit(Explicit(
            aci: aci,
            pni: pni,
            e164: e164,
            deviceId: deviceId,
            authPassword: authPassword
        )))
    }

    public func hash(into hasher: inout Hasher) {
        switch info {
        case .implicit:
            break
        case let .explicit(info):
            hasher.combine(info.aci)
            hasher.combine(info.e164)
            hasher.combine(info.authPassword)
        }
    }

    public static func == (lhs: AuthedAccount, rhs: AuthedAccount) -> Bool {
        return lhs.info == rhs.info
    }

    public func orIfImplicitUse(_ other: AuthedAccount) -> AuthedAccount {
        switch (self.info, other.info) {
        case (.explicit, _):
            return self
        case (_, .explicit):
            return other
        case (.implicit, .implicit):
            return other
        }
    }

    public func isAddressForLocalUser(_ address: SignalServiceAddress) -> Bool {
        switch info {
        case .implicit:
            return false
        case let .explicit(info):
            return info.isAddressForLocalUser(address)
        }
    }

    public var chatServiceAuth: ChatServiceAuth {
        switch info {
        case .implicit:
            return .implicit()
        case let .explicit(info):
            return info.chatServiceAuth
        }
    }

    public func authedDevice(isPrimaryDevice: Bool) -> AuthedDevice {
        switch info {
        case .implicit:
            return .implicit
        case let .explicit(info):
            return .explicit(AuthedDevice.Explicit(
                aci: info.aci,
                phoneNumber: info.e164,
                pni: info.pni,
                deviceId: info.deviceId,
                authPassword: info.authPassword
            ))
        }
    }
}

extension AuthedAccount.Explicit {

    public func isAddressForLocalUser(_ address: SignalServiceAddress) -> Bool {
        return localIdentifiers.contains(address: address)
    }

    public var localIdentifiers: LocalIdentifiers {
        return LocalIdentifiers(aci: aci, pni: pni, phoneNumber: e164.stringValue)
    }

    public var chatServiceAuth: ChatServiceAuth {
        return .explicit(aci: aci, deviceId: deviceId, password: authPassword)
    }
}
