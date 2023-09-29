//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// TODO: rename to TSAccountManager after removing the original
public protocol TSAccountManagerProtocol {

    /// Temporary method until old TSAccountManager is deleted. While both exist,
    /// each needs to inform the other about account state updates so the other
    /// can update their cache.
    /// Called inside the lock that is shared between both TSAccountManagers. 
    func tmp_loadAccountState(tx: DBReadTransaction)

    func warmCaches()

    // MARK: - Local Identifiers

    var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? { get }

    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers?

    var storedServerUsernameWithMaybeTransaction: String? { get }

    func storedServerUsername(tx: DBReadTransaction) -> String?

    var storedServerAuthTokenWithMaybeTransaction: String? { get }

    func storedServerAuthToken(tx: DBReadTransaction) -> String?

    var storedDeviceIdWithMaybeTransaction: UInt32 { get }

    func storedDeviceId(tx: DBReadTransaction) -> UInt32

    // MARK: - Registration State

    var registrationStateWithMaybeSneakyTransaction: TSRegistrationState { get }

    func registrationState(tx: DBReadTransaction) -> TSRegistrationState

    // MARK: - RegistrationIds

    func getOrGenerateAciRegistrationId(tx: DBWriteTransaction) -> UInt32
    func getOrGeneratePniRegistrationId(tx: DBWriteTransaction) -> UInt32

    /// Set the PNI registration ID.
    ///
    /// This exists as a separate, external setter because we might _learn_ about a
    /// PNI registration ID from PNI events from other devices, already having been
    /// provided to the service, in which case we need to persist the value locally.
    ///
    /// There are no side effects to this setter; the caller is expected to handle those
    /// and have this setter just persist state.
    func setPniRegistrationId(
        _ newRegistrationId: UInt32,
        tx: DBWriteTransaction
    )

    // MARK: - Manual Message Fetch

    func isManualMessageFetchEnabled(tx: DBReadTransaction) -> Bool
    func setIsManualMessageFetchEnabled(_ isEnabled: Bool, tx: DBWriteTransaction)

    // MARK: - Phone Number Discoverability

    func hasDefinedIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool
    func isDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool
}

/// Should only be used in ``PhoneNumberDiscoverabilityManager``, so that necessary
/// side effects can be triggered.
public protocol PhoneNumberDiscoverabilitySetter {

    func setIsDiscoverableByPhoneNumber(_ isDiscoverable: Bool, tx: DBWriteTransaction)
}

/// Should only be used in ``RegistrationStateChangeManager``, so that necessary
/// side effects can be triggered.
public protocol LocalIdentifiersSetter {

    /// Initialize local identifiers state after registration, linking, reregistration, or relinking.
    /// PNI TODO: once all devices are PNI-capable, remove PNI nullability here.
    /// Nil pni only happens with device linking, for registration its already non-optional.
    ///
    /// The old TSAccountManager expects isOnboarded to be set for registration, not just provisioning.
    /// While bridging between the old and new, set it in the new code. Once the old code is removed
    /// and readers stop expecting the value, delete tmp_setIsOnboarded.
    func initializeLocalIdentifiers(
        e164: E164,
        aci: Aci,
        pni: Pni?,
        deviceId: UInt32,
        serverAuthToken: String,
        tmp_setIsOnboarded: Bool,
        tx: DBWriteTransaction
    )

    /// Change local identifiers after a change number operation.
    /// ACI provided for convenience; it should be unchanged.
    /// Server auth token is also assumed to be unchanged.
    func changeLocalNumber(
        newE164: E164,
        aci: Aci,
        pni: Pni?,
        tx: DBWriteTransaction
    )

    func setDidFinishProvisioning(tx: DBWriteTransaction)

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
        tx: DBWriteTransaction
    )

    /// Returns true if value changed, false otherwise.
    func setIsTransferInProgress(_ isTransferInProgress: Bool, tx: DBWriteTransaction) -> Bool

    /// Returns true if value changed, false otherwise.
    func setWasTransferred(_ wasTransferred: Bool, tx: DBWriteTransaction) -> Bool
}
