//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public final class LocalIdentifiers {
    /// The ACI for the current user.
    public let aci: Aci

    // TODO: [#less] Use within LocalIdentifiers.
    public struct PhoneNumber: Equatable {
        /// The phone number for the current user.
        public let e164: E164

        /// The PNI for the current user.
        public let pni: Pni

        public init(e164: E164, pni: Pni) {
            self.e164 = e164
            self.pni = pni
        }
    }

    /// The PNI for the current user.
    ///
    /// - Note: Primary & linked devices may not have access to their PNI. The
    /// primary may need to fetch it from the server, and a linked device may be
    /// waiting to learn about it from the primary.
    public let pni: Pni?

    /// The phone number for the current user.
    ///
    /// - Note: This is a `String` because the phone number we've saved to disk
    /// in prior versions of the application may not be a valid E164.
    public let phoneNumber: String

    /// The phone number for the current user, as an optional.
    ///
    /// This is a temporary and will go away when `phoneNumber` is optional.
    public var phoneNumberAsOptional: String? { self.phoneNumber }

    public init(aci: Aci, pni: Pni?, phoneNumber: String) {
        self.aci = aci
        self.pni = pni
        self.phoneNumber = phoneNumber
    }

    public convenience init(aci: Aci, phoneNumber: PhoneNumber) {
        self.init(aci: aci, pni: phoneNumber.pni, phoneNumber: phoneNumber.e164.stringValue)
    }

    /// Checks if `serviceId` refers to ourself.
    ///
    /// Returns true if it's our ACI or our PNI.
    public func contains(serviceId: ServiceId) -> Bool {
        return serviceId == aci || serviceId == pni
    }

    /// Checks if `phoneNumber` refers to ourself.
    public func contains(phoneNumber: E164) -> Bool {
        return contains(phoneNumber: phoneNumber.stringValue)
    }

    /// Checks if `phoneNumber` refers to ourself.
    public func contains(phoneNumber: String) -> Bool {
        return phoneNumber == self.phoneNumber
    }

    /// Checks if `address` refers to ourself.
    ///
    /// This generally means that `address.serviceId` matches our ACI or PNI.
    public func contains(address: SignalServiceAddress) -> Bool {
        // If the address has a ServiceId, then it must match one of our
        // ServiceIds. (If it has some other ServiceId, then it's not us because
        // that's not our ServiceId, even if the phone number matches.)
        if let serviceId = address.serviceId {
            return contains(serviceId: serviceId)
        }
        // Otherwise, it's us if the phone number matches. (This shouldn't happen
        // in production because we populate `SignalServiceAddressCache` with our
        // own identifiers.)
        if let phoneNumber = address.phoneNumber {
            return contains(phoneNumber: phoneNumber)
        }
        return false
    }

    // TODO: [#less] Accept an E164 (when LocalIdentifiers also accepts one).
    public func containsAnyOf(aci: Aci?, phoneNumber: String?, pni: Pni?) -> Bool {
        if let aci, self.aci == aci {
            return true
        }
        if let phoneNumber, self.phoneNumber == phoneNumber {
            return true
        }
        if let pni, self.pni == pni {
            return true
        }
        return false
    }

    public func isAciAddressEqualToAddress(_ address: SignalServiceAddress) -> Bool {
        if let serviceId = address.serviceId {
            return serviceId == self.aci
        }
        return address.phoneNumber == self.phoneNumber
    }
}

public extension LocalIdentifiers {
    var aciAddress: SignalServiceAddress {
        SignalServiceAddress(serviceId: aci, phoneNumber: phoneNumber)
    }
}

// MARK: - Unit Tests

#if TESTABLE_BUILD

extension LocalIdentifiers {
    static var forUnitTests: LocalIdentifiers {
        return LocalIdentifiers(
            aci: Aci.constantForTesting("00000000-0000-4000-8000-000000000AAA"),
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-000000000BBB"),
            phoneNumber: "+16505550100",
        )
    }

    func withoutPni() -> Self {
        return Self(aci: self.aci, pni: nil, phoneNumber: self.phoneNumber)
    }
}

#endif
