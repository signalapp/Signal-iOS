//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension TSAccountManagerImpl {

    internal class AccountStateManager {

        private typealias Keys = AccountState.Keys

        private let dateProvider: DateProvider
        private let db: DB
        private let kvStore: KeyValueStore

        private let lock = UnfairLock()
        private var cachedAccountState: AccountState?

        init(
            dateProvider: @escaping DateProvider,
            db: DB,
            kvStore: KeyValueStore
        ) {
            self.dateProvider = dateProvider
            self.db = db
            self.kvStore = kvStore
        }

        // MARK: - External methods (acquire the lock)

        func getOrLoadAccountStateWithMaybeTransaction() -> AccountState {
            return lock.withLock {
                if let accountState = self.cachedAccountState {
                    return accountState
                }
                return db.read { tx in
                    return self.loadAccountState(tx: tx)
                }
            }
        }

        func getOrLoadAccountState(tx: DBReadTransaction) -> AccountState {
            return lock.withLock {
                if let accountState = self.cachedAccountState {
                    return accountState
                }
                return loadAccountState(tx: tx)
            }
        }

        // MARK: Mutations

        func setDeviceId(
            _ id: UInt32,
            serverAuthToken: String,
            tx: DBWriteTransaction
        ) {
            mutateWithLock(tx: tx) {
                kvStore.setUInt32(id, key: Keys.deviceId, transaction: tx)
                kvStore.setString(serverAuthToken, key: Keys.serverAuthToken, transaction: tx)
            }
        }

        func setLocalIdentifiers(
            _ number: E164?,
            _ aci: Aci?,
            _ pni: Pni?,
            tx: DBWriteTransaction
        ) {
            mutateWithLock(tx: tx) {
                let oldNumber = kvStore.getString(Keys.localPhoneNumber, transaction: tx)
                Logger.info("local number \(oldNumber ?? "nil") -> \(number?.stringValue ?? "nil")")
                kvStore.setString(number?.stringValue, key: Keys.localPhoneNumber, transaction: tx)

                let oldAci = kvStore.getString(Keys.localAci, transaction: tx)
                Logger.info("local aci \(oldAci ?? "nil") -> \(aci?.serviceIdUppercaseString ?? "nil")")
                kvStore.setString(aci?.serviceIdUppercaseString, key: Keys.localAci, transaction: tx)

                let oldPni = kvStore.getString(Keys.localPni, transaction: tx)
                Logger.info("local number \(oldPni ?? "nil") -> \(pni?.rawUUID.uuidString ?? "nil")")
                // Encoded without the "PNI:" prefix for backwards compatibility.
                kvStore.setString(pni?.rawUUID.uuidString, key: Keys.localPni, transaction: tx)

                kvStore.setDate(dateProvider(), key: Keys.registrationDate, transaction: tx)
                kvStore.removeValues(
                    forKeys: [
                        Keys.isDeregistered,
                        Keys.reregistrationPhoneNumber,
                        Keys.reregistrationAci
                    ],
                    transaction: tx
                )
            }
        }

        func setIsDiscoverableByPhoneNumber(_ isDiscoverable: Bool, tx: DBWriteTransaction) {
            mutateWithLock(tx: tx) {
                kvStore.setBool(
                    isDiscoverable,
                    key: Keys.isDiscoverableByPhoneNumber,
                    transaction: tx
                )

                kvStore.setDate(
                    dateProvider(),
                    key: Keys.lastSetIsDiscoverableByPhoneNumber,
                    transaction: tx
                )
            }
        }

        func setManualMessageFetchEnabled(_ enabled: Bool, tx: DBWriteTransaction) {
            mutateWithLock(tx: tx) {
                kvStore.setBool(enabled, key: Keys.isManualMessageFetchEnabled, transaction: tx)
            }
        }

        private func mutateWithLock(tx: DBWriteTransaction, _ block: () -> Void) {
            lock.withLock {
                block()
                // Reload to repopulate the cache; the mutations will
                // write to disk and not actually modify the cached value.
                loadAccountState(tx: tx)
            }
        }

        // MARK: - Internal methods (must have lock)

        /// Must be called within the lock
        @discardableResult
        private func loadAccountState(tx: DBReadTransaction) -> AccountState {
            let accountState = AccountState.init(kvStore: kvStore, tx: tx)
            self.cachedAccountState = accountState
            return accountState
        }
    }

    /// A cache of frequently-accessed database state.
    ///
    /// * Instances of AccountState are immutable.
    /// * None of this state should change often.
    /// * Whenever any of this state changes, we reload all of it.
    ///
    /// This cache changes all of its properties in lockstep, which
    /// helps ensure consistency.
    internal struct AccountState {

        let localIdentifiers: LocalIdentifiers?

        let deviceId: UInt32

        let serverAuthToken: String?

        let registrationState: TSRegistrationState
        let registrationDate: Date?

        let isDiscoverableByPhoneNumber: Bool
        let hasDefinedIsDiscoverableByPhoneNumber: Bool
        let lastSetIsDiscoverableByPhoneNumberAt: Date

        let isManualMessageFetchEnabled: Bool

        init(
            kvStore: KeyValueStore,
            tx: DBReadTransaction
        ) {
            // WARNING: AccountState is loaded before data migrations have run (as well as after).
            // Do not use data migrations to update AccountState data; do it through schema migrations
            // or through normal write transactions. TSAccountManager should be the only code accessing this state anyway.
            let localIdentifiers = Self.loadLocalIdentifiers(kvStore: kvStore, tx: tx)
            self.localIdentifiers = localIdentifiers

            let persistedDeviceId = kvStore.getUInt32(
                Keys.deviceId,
                transaction: tx
            )
            // Assume primary, for backwards compatibility.
            self.deviceId = persistedDeviceId ?? OWSDevice.primaryDeviceId

            self.serverAuthToken = kvStore.getString(Keys.serverAuthToken, transaction: tx)

            let isPrimaryDevice: Bool?
            if let persistedDeviceId {
                isPrimaryDevice = persistedDeviceId == OWSDevice.primaryDeviceId
            } else {
                isPrimaryDevice = nil
            }

            self.registrationState = Self.loadRegistrationState(
                localIdentifiers: localIdentifiers,
                isPrimaryDevice: isPrimaryDevice,
                kvStore: kvStore,
                tx: tx
            )
            self.registrationDate = kvStore.getDate(Keys.registrationDate, transaction: tx)

            let persistedIsDiscoverable = kvStore.getBool(Keys.isDiscoverableByPhoneNumber, transaction: tx)
            var isDiscoverableByDefault = true

            // TODO: [Usernames] Confirm default discoverability
            //
            // When we enable the ability to change whether you're discoverable
            // by phone number, new registrations must not be discoverable by
            // default. In order to accommodate this, the default "isDiscoverable"
            // flag will be NO until you have successfully registered (aka defined
            // a local phone number).
            if FeatureFlags.phoneNumberDiscoverability {
                switch registrationState {
                case .unregistered, .linkedButUnprovisioned:
                    isDiscoverableByDefault = false
                case
                        .registered, .provisioned,
                        .deregistered, .delinked,
                        .reregistering,
                        .transferringPrimaryOutgoing, .transferringLinkedOutgoing,
                        .transferred, .transferringIncoming:
                    break
                }
            }

            self.isDiscoverableByPhoneNumber = persistedIsDiscoverable ?? isDiscoverableByDefault
            self.hasDefinedIsDiscoverableByPhoneNumber = persistedIsDiscoverable != nil
            self.lastSetIsDiscoverableByPhoneNumberAt = kvStore.getDate(
                Keys.lastSetIsDiscoverableByPhoneNumber,
                transaction: tx
            ) ?? .distantPast

            self.isManualMessageFetchEnabled = kvStore.getBool(
                Keys.isManualMessageFetchEnabled,
                defaultValue: false,
                transaction: tx
            )
        }

        private static func loadLocalIdentifiers(
            kvStore: KeyValueStore,
            tx: DBReadTransaction
        ) -> LocalIdentifiers? {
            guard
                let localNumber = kvStore.getString(Keys.localPhoneNumber, transaction: tx)
            else {
                return nil
            }
            guard let localAci = kvStore.getUuid(Keys.localAci, transaction: tx) else {
                return nil
            }
            let pni = kvStore.getUuid(Keys.localPni, transaction: tx).map(Pni.init(fromUUID:))
            return LocalIdentifiers(
                aci: Aci(fromUUID: localAci),
                pni: pni,
                phoneNumber: localNumber
            )
        }

        private static func loadRegistrationState(
            localIdentifiers: LocalIdentifiers?,
            isPrimaryDevice: Bool?,
            kvStore: KeyValueStore,
            tx: DBReadTransaction
        ) -> TSRegistrationState {
            let reregistrationPhoneNumber = kvStore.getString(
                Keys.reregistrationPhoneNumber,
                transaction: tx
            )
            // TODO: Eventually require reregistrationAci during re-registration.
            let reregistrationAci = kvStore.getUuid(
                Keys.reregistrationAci,
                transaction: tx
            ).map(Aci.init(fromUUID:))

            let isFinishedProvisioning = kvStore.getBool(
                Keys.isFinishedProvisioning,
                defaultValue: false,
                transaction: tx
            )

            let isDeregistered = kvStore.getBool(
                Keys.isDeregistered,
                transaction: tx
            )

            let isTransferInProgress = kvStore.getBool(
                Keys.isTransferInProgress,
                defaultValue: false,
                transaction: tx
            )
            let wasTransferred = kvStore.getBool(
                Keys.wasTransferred,
                defaultValue: false,
                transaction: tx
            )

            // Go in semi-reverse order; with higher priority stuff going first.
            if wasTransferred {
                // If we transferred, we are transferred regardless of what else
                // may be going on. Other state might be a mess; doesn't matter.
                return .transferred
            } else if isTransferInProgress {
                // Ditto for a transfer in progress; regardless of whatever
                // else is going on (except being transferred) this takes precedence.
                if let isPrimaryDevice {
                    return isPrimaryDevice
                        ? .transferringPrimaryOutgoing
                        : .transferringLinkedOutgoing
                } else {
                    // If we never knew primary device state, it must be an
                    // incoming transfer, where we started from a blank state.
                    return .transferringIncoming
                }
            } else if let reregistrationPhoneNumber {
                // If a "reregistrationPhoneNumber" is present, we are reregistering.
                // reregistrationAci is optional (for now, see above TODO).
                // isDeregistered is probably also true; this takes precedence.
                return .reregistering(
                    phoneNumber: reregistrationPhoneNumber,
                    aci: reregistrationAci
                )
            } else if isDeregistered == true {
                // if isDeregistered is true, we may have been registered
                // or not. But its being true means we should be deregistered
                // (or delinked, based on whether this is a primary).
                // isPrimaryDevice should have some value; if we've explicit
                // set isDeregistered that means we _were_ registered before.
                owsAssertDebug(isPrimaryDevice != nil)
                return isPrimaryDevice == true ? .deregistered : .delinked
            } else if localIdentifiers == nil {
                // Setting localIdentifiers is what marks us as registered
                // in primary registration. (As long as above conditions don't
                // override that state)
                // For provisioning, we set them before finishing, but the fact
                // that we set them means we linked (but didn't finish yet).
                return .unregistered
            } else {
                // We have local identifiers, so we are either done
                // or in the middle of provisioning.
                if !isFinishedProvisioning && isPrimaryDevice == false {
                    return .linkedButUnprovisioned
                }
                return isPrimaryDevice == true ? .registered : .provisioned
            }
        }

        func log() {
            Logger.info("RegistrationState: \(registrationState.logString)")
        }

        fileprivate enum Keys {
            static let deviceId = "TSAccountManager_DeviceId"
            static let serverAuthToken = "TSStorageServerAuthToken"

            static let localPhoneNumber = "TSStorageRegisteredNumberKey"
            static let localAci = "TSStorageRegisteredUUIDKey"
            static let localPni = "TSAccountManager_RegisteredPNIKey"

            static let registrationDate = "TSAccountManager_RegistrationDateKey"
            static let isDeregistered = "TSAccountManager_IsDeregisteredKey"

            static let reregistrationPhoneNumber = "TSAccountManager_ReregisteringPhoneNumberKey"
            static let reregistrationAci = "TSAccountManager_ReregisteringUUIDKey"

            // Some historical context: "isOnboarded" used to be used during registration
            // as well as provisioning, with different meanings for each.
            // In registration, isRegistered would be true after the account was created,
            // but isOnboarded would be true only after setting up the profile.
            // In provisioning, isRegistered would be true after linking completed,
            // but isOnboarded would be true only after doing an initial storage service
            // sync, among other syncs.
            // The concept is now dead in registration, but at time of writing not in
            // provisioning. So the key remains the same, but the in-code name refers
            // to its exclusive usage during provisioning to mark the time between
            // linking and syncing.
            static let isFinishedProvisioning = "TSAccountManager_IsOnboardedKey"

            static let isTransferInProgress = "TSAccountManager_IsTransferInProgressKey"
            static let wasTransferred = "TSAccountManager_WasTransferredKey"

            static let isDiscoverableByPhoneNumber = "TSAccountManager_IsDiscoverableByPhoneNumber"
            static let lastSetIsDiscoverableByPhoneNumber = "TSAccountManager_LastSetIsDiscoverableByPhoneNumberKey"

            static let isManualMessageFetchEnabled = "TSAccountManager_ManualMessageFetchKey"
        }
    }

}

extension KeyValueStore {

    func getUuid(_ key: String, transaction: DBReadTransaction) -> UUID? {
        guard let raw = getString(key, transaction: transaction) else {
            return nil
        }
        return UUID(uuidString: raw)
    }
}
