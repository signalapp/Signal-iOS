//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum TSRegistrationState {
    /// We are unregistered and never have been.
    /// Depending on the device, the user might register as a primary
    /// or provision as a linked device.
    /// Registration or provisioning may already be underway; in progress
    /// state is not maintained here.
    case unregistered

    /// Re-registering after becoming deregistered.
    case reregistering(ReregisteringLocalIdentifiers)
    /// Re-linking after becoming delinked.
    case relinking(ReregisteringLocalIdentifiers)

    /// Registered as a primary device. "Normal" state.
    case registered(LocalIdentifiers)
    /// Provisioned as a linked device. "Normal" state.
    case provisioned(LocalIdentifiers)

    /// Deregistered after having been registered, typically due
    /// to an error in a server response informing us we've been
    /// deregistered. Applies to primary devices only.
    case deregistered(DeregisteredLocalIdentifiers)
    /// Delinked after having been provisioned, typically due
    /// to an error in a server response informing us we've been
    /// delinked. Applies to linked devices only.
    case delinked(DeregisteredLocalIdentifiers)

    /// The user has initiated an incoming device transfer.
    /// isPrimary state will be determined based on the final transferred database.
    /// Most things should behave as if unregistered.
    case transferringIncoming

    /// The user has initiated an outgoing device transfer.
    /// Most things should behave as if unregistered.
    case transferringPrimaryOutgoing
    /// The user has initiated an outgoing device transfer.
    /// Most things should behave as if unregistered.
    case transferringLinkedOutgoing

    /// An _outgoing_ transfer has been completed, leaving this
    /// device unuseable until cleanup can be completed, at which
    /// point it becomes `unregistered` and behaves like a fresh
    /// install.
    case transferred
}

extension TSRegistrationState {

    public func registeredState() throws(NotRegisteredError) -> RegisteredState {
        return try RegisteredState(registrationState: self)
    }

    public var isRegistered: Bool {
        return (try? registeredState()) != nil
    }

    public var wasEverRegistered: Bool {
        switch self {
        case .unregistered, .transferringIncoming:
            return false
        case
            .registered, .provisioned,
            .reregistering, .relinking,
            .deregistered, .delinked,
            .transferringPrimaryOutgoing, .transferringLinkedOutgoing,
            .transferred:
            return true
        }
    }

    public var deviceType: DeviceType? {
        switch self {
        case .unregistered, .transferringIncoming:
            // We don't yet know if this will be a primary
            // or a linked device. The user can change.
            return nil
        case .transferred:
            // Irrelevant what this was, return nil.
            return nil
        case .registered, .deregistered, .reregistering, .transferringPrimaryOutgoing:
            return .primary
        case .provisioned, .delinked, .relinking, .transferringLinkedOutgoing:
            return .linked
        }
    }

    public var isPrimaryDevice: Bool? {
        switch self.deviceType {
        case .primary: true
        case .linked: false
        case .none: nil
        }
    }

    public var isRegisteredPrimaryDevice: Bool {
        return (try? self.registeredState())?.isPrimary == true
    }

    public var isDeregistered: Bool {
        return self.deregisteredState != nil
    }

    public var deregisteredState: DeregisteredState? {
        return DeregisteredState(registrationState: self)
    }

    public var logString: String {
        switch self {
        case .unregistered:
            return "unregistered"
        case .transferringPrimaryOutgoing:
            return "transferringPrimaryOutgoing"
        case .transferringLinkedOutgoing:
            return "transferringLinkedOutgoing"
        case .transferringIncoming:
            return "transferringIncoming"
        case .registered:
            return "registered"
        case .provisioned:
            return "provisioned"
        case .deregistered:
            return "deregistered"
        case .delinked:
            return "delinked"
        case .transferred:
            return "transferred"
        case .reregistering:
            return "reregistering"
        case .relinking:
            return "relinking"
        }
    }
}
