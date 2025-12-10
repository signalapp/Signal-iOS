//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol TSAccountManager {

    func warmCaches(tx: DBReadTransaction)

    // MARK: - Local Identifiers

    var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? { get }

    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers?

    var storedServerUsernameWithMaybeTransaction: String? { get }

    func storedServerUsername(tx: DBReadTransaction) -> String?

    var storedServerAuthTokenWithMaybeTransaction: String? { get }

    func storedServerAuthToken(tx: DBReadTransaction) -> String?

    var storedDeviceIdWithMaybeTransaction: LocalDeviceId { get }

    func storedDeviceId(tx: DBReadTransaction) -> LocalDeviceId

    // MARK: - Registration State

    var registrationStateWithMaybeSneakyTransaction: TSRegistrationState { get }

    func registrationState(tx: DBReadTransaction) -> TSRegistrationState

    func registrationDate(tx: DBReadTransaction) -> Date?

    // MARK: - RegistrationIds

    /// Set the registration ID.
    ///
    /// This exists as a separate, external setter because we might _learn_ about a
    /// PNI registration ID from PNI events from other devices, already having been
    /// provided to the service, in which case we need to persist the value locally.
    ///
    /// There are no side effects to this setter; the caller is expected to handle those
    /// and have this setter just persist state.
    func setRegistrationId(
        _ newRegistrationId: UInt32,
        for identity: OWSIdentity,
        tx: DBWriteTransaction
    )
    func getRegistrationId(for identity: OWSIdentity, tx: DBReadTransaction) -> UInt32?
    func clearRegistrationIds(tx: DBWriteTransaction)

    // MARK: - Manual Message Fetch

    func isManualMessageFetchEnabled(tx: DBReadTransaction) -> Bool
    func setIsManualMessageFetchEnabled(_ isEnabled: Bool, tx: DBWriteTransaction)

    // MARK: - Phone Number Discoverability

    func phoneNumberDiscoverability(tx: DBReadTransaction) -> PhoneNumberDiscoverability?
    func lastSetIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Date
}

public struct NotRegisteredError: Error, IsRetryableProvider {
    public let isRetryableProvider: Bool = false
}

/// It's *possible* (but implausible) that the local user's "device ID"
/// isn't valid. These "device IDs" aren't supported on the server, so these
/// users consider themselves "deregistered" (or, if they don't, they will
/// as soon as they try to authenticate).
public enum LocalDeviceId: CustomStringConvertible {
    case valid(DeviceId)
    case invalid

    public var ifValid: DeviceId? {
        switch self {
        case .valid(let deviceId):
            return deviceId
        case .invalid:
            return nil
        }
    }

    /// Checks if the LocalDeviceId matches an arbitrary DeviceId.
    ///
    /// All DeviceIds are valid, so if the LocalDeviceId isn't valid, it can't
    /// possibly match a DeviceId.
    public func equals(_ otherDeviceId: DeviceId?) -> Bool {
        switch self {
        case .valid(let deviceId):
            return deviceId == otherDeviceId
        case .invalid:
            return false
        }
    }

    public var description: String {
        switch self {
        case .valid(let deviceId):
            return "\(deviceId)"
        case .invalid:
            // If the device ID isn't valid, represent it as an artibrary invalid device ID.
            return "0"
        }
    }
}

extension TSAccountManager {
    public func registeredStateWithMaybeSneakyTransaction() throws(NotRegisteredError) -> RegisteredState {
        return try RegisteredState(
            registrationState: self.registrationStateWithMaybeSneakyTransaction,
            localIdentifiers: self.localIdentifiersWithMaybeSneakyTransaction,
        )
    }

    public func registeredState(tx: DBReadTransaction) throws(NotRegisteredError) -> RegisteredState {
        return try RegisteredState(
            registrationState: self.registrationState(tx: tx),
            localIdentifiers: self.localIdentifiers(tx: tx),
        )
    }

    public func localIdentifiersWithMaybeSneakyTransaction(authedAccount: AuthedAccount) throws -> LocalIdentifiers {
        switch authedAccount.info {
        case .explicit(let info):
            return info.localIdentifiers
        case .implicit:
            guard let localIdentifiers = localIdentifiersWithMaybeSneakyTransaction else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }
            return localIdentifiers
        }
    }

    public func localIdentifiers(authedAccount: AuthedAccount, tx: DBReadTransaction) throws -> LocalIdentifiers {
        switch authedAccount.info {
        case .explicit(let info):
            return info.localIdentifiers
        case .implicit:
            guard let localIdentifiers = localIdentifiers(tx: tx) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }
            return localIdentifiers
        }
    }
}

/// Should only be used in ``PhoneNumberDiscoverabilityManager``, so that necessary
/// side effects can be triggered.
public protocol PhoneNumberDiscoverabilitySetter {

    func setPhoneNumberDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability, tx: DBWriteTransaction)
}

/// Should only be used in ``RegistrationStateChangeManager``, so that necessary
/// side effects can be triggered.
public protocol LocalIdentifiersSetter {

    /// Initialize local identifiers state after registration, linking, reregistration, or relinking.
    func initializeLocalIdentifiers(
        e164: E164,
        aci: Aci,
        pni: Pni,
        deviceId: DeviceId,
        serverAuthToken: String,
        tx: DBWriteTransaction
    )

    /// Change local identifiers after a change number operation.
    /// ACI provided for convenience; it should be unchanged.
    /// Server auth token is also assumed to be unchanged.
    func changeLocalNumber(
        newE164: E164,
        aci: Aci,
        pni: Pni,
        tx: DBWriteTransaction
    )

    /// Returns true if successful. Not successful iff the old value is the same as new value (no-op).
    ///
    /// Note that the old value is NOT equivalent to ``TSRegistrationState.deregistered``
    /// or ``TSRegistrationState.delinked``; you can be deregistered AND reregistering,
    /// in which case state would be ``TSRegistrationState.reregistering`` (and remain so)
    /// but this method could still mutate underlying state which would take effect _after_ the
    /// reregistration state was also cleared.
    func setIsDeregisteredOrDelinked(_ isDeregisteredOrDelinked: Bool, tx: DBWriteTransaction) -> Bool

    func resetForReregistration(
        localNumber: E164,
        localAci: Aci,
        discoverability: PhoneNumberDiscoverability?,
        wasPrimaryDevice: Bool,
        tx: DBWriteTransaction
    )

    /// Returns true if value changed, false otherwise.
    func setIsTransferInProgress(_ isTransferInProgress: Bool, tx: DBWriteTransaction) -> Bool

    /// Returns true if value changed, false otherwise.
    func setWasTransferred(_ wasTransferred: Bool, tx: DBWriteTransaction) -> Bool

    /**
     * After we succesully transfer, we need to do some cleanup the next time
     * the app launches.
     *
     * We clean up all transfer in progress state (set isTransferInProgress to false).
     * This will also run if the transfer did not finish; thats fine because transfers
     * don't survice the app being killed, so its ok to do so on fresh app launch.
     *
     * This is especially important after a successful transfer; because the db,
     * having been copied from the old device's state at the time of transfer,
     * will have a transfer in progress, which needs to be cleaned up.
     */
    func cleanUpTransferStateOnAppLaunchIfNeeded()
}
