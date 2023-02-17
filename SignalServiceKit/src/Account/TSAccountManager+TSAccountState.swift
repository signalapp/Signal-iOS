//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
@objcMembers
class TSAccountState: NSObject {
    let localNumber: String?
    let localUuid: UUID?
    let localPni: UUID?
    let registrationDate: Date?

    let reregistrationPhoneNumber: String?
    let reregistrationUUID: UUID?

    let isRegistered: Bool
    let isReregistering: Bool

    let isDeregistered: Bool
    let isOnboarded: Bool

    let isTransferInProgress: Bool
    let wasTransferred: Bool

    let serverSignalingKey: String?
    let serverAuthToken: String?

    let deviceName: String?
    let deviceId: UInt32

    let isDiscoverableByPhoneNumber: Bool
    let hasDefinedIsDiscoverableByPhoneNumber: Bool
    let lastSetIsDiscoverableByPhoneNumberAt: Date

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

        localNumber = getString(TSAccountManager_RegisteredNumberKey)
        registrationDate = getDate(TSAccountManager_RegistrationDateKey)
        localUuid = getUuid(TSAccountManager_RegisteredUUIDKey)
        localPni = getUuid(TSAccountManager_RegisteredPNIKey)

        reregistrationPhoneNumber = getString(TSAccountManager_ReregisteringPhoneNumberKey)
        reregistrationUUID = getUuid(TSAccountManager_ReregisteringUUIDKey)

        isRegistered = localNumber != nil
        // TODO: Support re-registration with only reregistrationUUID.
        // TODO: Eventually require reregistrationUUID during re-registration.
        isReregistering = reregistrationPhoneNumber != nil

        isDeregistered = getBool(TSAccountManager_IsDeregisteredKey) ?? false
        isOnboarded = getBool(TSAccountManager_IsOnboardedKey) ?? false

        isTransferInProgress = getBool(TSAccountManager_IsTransferInProgressKey) ?? false
        wasTransferred = getBool(TSAccountManager_WasTransferredKey) ?? false

        serverSignalingKey = getString(TSAccountManager_ServerSignalingKey)
        serverAuthToken = getString(TSAccountManager_ServerAuthTokenKey)

        deviceName = getString(TSAccountManager_DeviceNameKey)
        deviceId = getUInt32(TSAccountManager_DeviceIdKey) ?? 1

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
                isDiscoverableByDefault = isRegistered
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
