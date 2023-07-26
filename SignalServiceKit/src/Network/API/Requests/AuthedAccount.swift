//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public class AuthedAccount: NSObject {

    public struct Explicit: Equatable {
        public let aci: UUID
        public let pni: UUID
        public let e164: E164
        public let authPassword: String

        public init(aci: UUID, pni: UUID, e164: E164, authPassword: String) {
            self.aci = aci
            self.pni = pni
            self.e164 = e164
            self.authPassword = authPassword
        }
    }

    public enum Info: Equatable {
        case implicit
        case explicit(Explicit)
    }

    @nonobjc
    public let info: Info

    private init(_ info: Info) {
        self.info = info
        super.init()
    }

    /// Will use info present on TSAccountManager
    @objc
    public static func implicit() -> AuthedAccount {
        return AuthedAccount(.implicit)
    }

    public static func explicit(
        aci: UUID,
        pni: UUID,
        e164: E164,
        authPassword: String
    ) -> AuthedAccount {
        return AuthedAccount(.explicit(Explicit(aci: aci, pni: pni, e164: e164, authPassword: authPassword)))
    }

    public override var hash: Int {
        var hasher = Hasher()
        switch info {
        case .implicit:
            break
        case let .explicit(info):
            hasher.combine(info.aci)
            hasher.combine(info.e164)
            hasher.combine(info.authPassword)
        }
        return hasher.finalize()
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AuthedAccount else {
            return false
        }
        return self.info == other.info
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

    @objc
    public func isAddressForLocalUser(_ address: SignalServiceAddress) -> Bool {
        guard let localAddress = localUserAddress() else {
            return false
        }
        return address.isEqualToAddress(localAddress)
    }

    @objc
    public func localUserAddress() -> SignalServiceAddress? {
        switch info {
        case .implicit:
            return nil
        case let .explicit(info):
            return info.localUserAddress()
        }
    }

    @objc
    public var chatServiceAuth: ChatServiceAuth {
        switch info {
        case .implicit:
            return .implicit()
        case let .explicit(info):
            return info.chatServiceAuth
        }
    }
}

extension AuthedAccount.Explicit {

    public func isAddressForLocalUser(_ address: SignalServiceAddress) -> Bool {
        return address.isEqualToAddress(localUserAddress())
    }

    public func localUserAddress() -> SignalServiceAddress {
        return SignalServiceAddress(uuid: aci, phoneNumber: e164.stringValue)
    }

    public var localIdentifiers: LocalIdentifiers {
        return LocalIdentifiers(aci: Aci(fromUUID: aci), pni: Pni(fromUUID: pni), phoneNumber: e164.stringValue)
    }

    public var chatServiceAuth: ChatServiceAuth {
        return .explicit(aci: aci, password: authPassword)
    }
}
