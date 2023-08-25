//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// A cache of frequently-accessed database state. This class should _only_ be
/// used from ``TSAccountManager``.
///
/// * Instances of TSAccountState are immutable.
/// * None of this state should change often.
/// * Whenever any of this state changes, we reload all of it.
///
/// This cache changes all of its properties in lockstep, which
/// helps ensure consistency.  e.g. isRegistered is true IFF
/// localNumber is non-nil.
class TSAccountState: NSObject {
    let localIdentifiers: LocalIdentifiers?

    @objc
    var localNumber: String? { localIdentifiers?.phoneNumber }

    @objc
    var localAci: AciObjC? {
        guard let localIdentifiers else {
            return nil
        }
        return AciObjC(localIdentifiers.aci)
    }

    @objc
    var localPni: PniObjC? {
        guard let localIdentifiers, let localPni = localIdentifiers.pni else {
            return nil
        }
        return PniObjC(localPni)
    }

    @objc
    let deviceId: UInt32

    let isReregistering: Bool
    let reregistrationPhoneNumber: String?
    let reregistrationAci: Aci?

    var isRegistered: Bool { localIdentifiers != nil }
    let isDeregistered: Bool
    let isOnboarded: Bool
    let registrationDate: Date?
    let serverAuthToken: String?

    let isTransferInProgress: Bool
    let wasTransferred: Bool

    let isDiscoverableByPhoneNumber: Bool
    let hasDefinedIsDiscoverableByPhoneNumber: Bool
    let lastSetIsDiscoverableByPhoneNumberAt: Date

    @objc
    init(
        transaction: SDSAnyReadTransaction,
        keyValueStore: SDSKeyValueStore
    ) {
        func getString(_ key: String) -> String? {
            keyValueStore.getString(key, transaction: transaction)
        }

        func getUuid(_ key: String) -> UUID? {
            if let uuidString = getString(key) {
                return UUID(uuidString: uuidString)
            }

            return nil
        }

        func getDate(_ key: String) -> Date? {
            keyValueStore.getDate(key, transaction: transaction)
        }

        func getBool(_ key: String) -> Bool? {
            keyValueStore.getBool(key, transaction: transaction)
        }

        func getUInt32(_ key: String) -> UInt32? {
            keyValueStore.getUInt32(key, transaction: transaction)
        }

        // WARNING: TSAccountState is loaded before data migrations have run (as well as after).
        // Do not use data migrations to update TSAccountState data; do it through schema migrations
        // or through normal write transactions. TSAccountManager should be the only code accessing this state anyway.

        localIdentifiers = {
            guard let localNumber = getString(TSAccountManager_RegisteredNumberKey) else {
                return nil
            }
            guard let localAci = getUuid(TSAccountManager_RegisteredUUIDKey) else {
                return nil
            }
            return LocalIdentifiers(
                aci: Aci(fromUUID: localAci),
                pni: getUuid(TSAccountManager_RegisteredPNIKey).map { Pni(fromUUID: $0) },
                phoneNumber: localNumber
            )
        }()
        deviceId = getUInt32(TSAccountManager_DeviceIdKey) ?? 1

        reregistrationPhoneNumber = getString(TSAccountManager_ReregisteringPhoneNumberKey)
        // TODO: Eventually require reregistrationAci during re-registration.
        reregistrationAci = getUuid(TSAccountManager_ReregisteringUUIDKey).map { Aci(fromUUID: $0) }
        // TODO: Support re-registration with only reregistrationAci.
        isReregistering = reregistrationPhoneNumber != nil

        isDeregistered = getBool(TSAccountManager_IsDeregisteredKey) ?? false
        isOnboarded = getBool(TSAccountManager_IsOnboardedKey) ?? false
        registrationDate = getDate(TSAccountManager_RegistrationDateKey)

        isTransferInProgress = getBool(TSAccountManager_IsTransferInProgressKey) ?? false
        wasTransferred = getBool(TSAccountManager_WasTransferredKey) ?? false

        serverAuthToken = getString(TSAccountManager_ServerAuthTokenKey)

        do {
            let persistedIsDiscoverable = getBool(TSAccountManager_IsDiscoverableByPhoneNumberKey)
            var isDiscoverableByDefault = true

            // TODO: [Usernames] Confirm default discoverability
            //
            // When we enable the ability to change whether you're discoverable
            // by phone number, new registrations must not be discoverable by
            // default. In order to accommodate this, the default "isDiscoverable"
            // flag will be NO until you have successfully registered (aka defined
            // a local phone number).
            if FeatureFlags.phoneNumberDiscoverability {
                isDiscoverableByDefault = localIdentifiers != nil
            }

            isDiscoverableByPhoneNumber = persistedIsDiscoverable ?? isDiscoverableByDefault
            hasDefinedIsDiscoverableByPhoneNumber = persistedIsDiscoverable != nil

            lastSetIsDiscoverableByPhoneNumberAt = getDate(
                TSAccountManager_LastSetIsDiscoverableByPhoneNumberKey
            ) ?? .distantPast
        }

        super.init()
    }

    func log() {
        Logger.info("isRegistered: \(isRegistered)")
        Logger.info("isDeregistered: \(isDeregistered)")
    }
}
