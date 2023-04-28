//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class LocalIdentifiersObjC: NSObject {
    public let wrappedValue: LocalIdentifiers

    public init(_ wrappedValue: LocalIdentifiers) {
        self.wrappedValue = wrappedValue
    }
}

public class LocalIdentifiers {
    /// The ACI for the current user.
    public let aci: ServiceId

    /// The PNI for the current user.
    ///
    /// - Note: Primary & linked devices may not have access to their PNI. The
    /// primary may need to fetch it from the server, and a linked device may be
    /// waiting to learn about it from the primary.
    public let pni: ServiceId?

    /// The phone number for the current user.
    ///
    /// - Note: This is a `String` because the phone number we've saved to disk
    /// in prior versions of the application may not be a valid E164.
    public let phoneNumber: String

    public init(aci: ServiceId, pni: ServiceId?, phoneNumber: String) {
        self.aci = aci
        self.pni = pni
        self.phoneNumber = phoneNumber
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

    public func isAciAddressEqualToAddress(_ address: SignalServiceAddress) -> Bool {
        if let serviceId = address.serviceId {
            return serviceId == self.aci
        }
        return address.phoneNumber == self.phoneNumber
    }
}

public extension LocalIdentifiers {
    var aciAddress: SignalServiceAddress {
        SignalServiceAddress(uuid: aci.uuidValue, phoneNumber: phoneNumber)
    }
}
