//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class TSAccountManagerImpl: TSAccountManager {

    private let appReadiness: Shims.AppReadiness
    private let dateProvider: DateProvider
    private let db: DB
    private let schedulers: Schedulers

    private let kvStore: KeyValueStore

    private let accountStateLock = UnfairLock()
    private var cachedAccountState: AccountState?

    public init(
        appReadiness: Shims.AppReadiness,
        dateProvider: @escaping DateProvider,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        schedulers: Schedulers
    ) {
        self.appReadiness = appReadiness
        self.dateProvider = dateProvider
        self.db = db
        self.schedulers = schedulers

        let kvStore = keyValueStoreFactory.keyValueStore(
            collection: "TSStorageUserAccountCollection"
        )
        self.kvStore = kvStore

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            if !self.appReadiness.isMainApp {
                self.db.appendDbChangeDelegate(self)
            }
        }
    }

    public func warmCaches() {
        // Load account state into the cache and log.
        getOrLoadAccountStateWithMaybeTransaction().log()
    }

    // MARK: - Local Identifiers

    public var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? {
        return getOrLoadAccountStateWithMaybeTransaction().localIdentifiers
    }

    public func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return getOrLoadAccountState(tx: tx).localIdentifiers
    }

    // MARK: - Registration State

    public var registrationStateWithMaybeSneakyTransaction: TSRegistrationState {
        return getOrLoadAccountStateWithMaybeTransaction().registrationState
    }

    public func registrationState(tx: DBReadTransaction) -> TSRegistrationState {
        return getOrLoadAccountState(tx: tx).registrationState
    }

    public func registrationDate(tx: DBReadTransaction) -> Date? {
        return getOrLoadAccountState(tx: tx).registrationDate
    }

    public var storedServerUsernameWithMaybeTransaction: String? {
        return getOrLoadAccountStateWithMaybeTransaction().serverUsername
    }

    public func storedServerUsername(tx: DBReadTransaction) -> String? {
        return getOrLoadAccountState(tx: tx).serverUsername
    }

    public var storedServerAuthTokenWithMaybeTransaction: String? {
        return getOrLoadAccountStateWithMaybeTransaction().serverAuthToken
    }

    public func storedServerAuthToken(tx: DBReadTransaction) -> String? {
        return getOrLoadAccountState(tx: tx).serverAuthToken
    }

    public var storedDeviceIdWithMaybeTransaction: UInt32 {
        return getOrLoadAccountStateWithMaybeTransaction().deviceId
    }

    public func storedDeviceId(tx: DBReadTransaction) -> UInt32 {
        return getOrLoadAccountState(tx: tx).deviceId
    }

    // MARK: - Registration IDs

    private static var aciRegistrationIdKey: String = "TSStorageLocalRegistrationId"
    private static var pniRegistrationIdKey: String = "TSStorageLocalPniRegistrationId"

    public func getOrGenerateAciRegistrationId(tx: DBWriteTransaction) -> UInt32 {
        getOrGenerateRegistrationId(
            forStorageKey: Self.aciRegistrationIdKey,
            nounForLogging: "ACI registration ID",
            tx: tx
        )
    }

    public func getOrGeneratePniRegistrationId(tx: DBWriteTransaction) -> UInt32 {
        getOrGenerateRegistrationId(
            forStorageKey: Self.pniRegistrationIdKey,
            nounForLogging: "PNI registration ID",
            tx: tx
        )
    }

    public func setPniRegistrationId(_ newRegistrationId: UInt32, tx: DBWriteTransaction) {
        kvStore.setUInt32(newRegistrationId, key: Self.pniRegistrationIdKey, transaction: tx)
    }

    private func getOrGenerateRegistrationId(
        forStorageKey key: String,
        nounForLogging: String,
        tx: DBWriteTransaction
    ) -> UInt32 {
        guard
            let storedId = kvStore.getUInt32(key, transaction: tx),
            storedId != 0
        else {
            let result = RegistrationIdGenerator.generate()
            Logger.info("Generated a new \(nounForLogging): \(result)")
            kvStore.setUInt32(result, key: key, transaction: tx)
            return result
        }
        return storedId
    }

    // MARK: - Manual Message Fetch

    public func isManualMessageFetchEnabled(tx: DBReadTransaction) -> Bool {
        return getOrLoadAccountState(tx: tx).isManualMessageFetchEnabled
    }

    public func setIsManualMessageFetchEnabled(_ isEnabled: Bool, tx: DBWriteTransaction) {
        mutateWithLock(tx: tx) {
            kvStore.setBool(isEnabled, key: Keys.isManualMessageFetchEnabled, transaction: tx)
        }
    }

    // MARK: - Phone Number Discoverability

    public func phoneNumberDiscoverability(tx: DBReadTransaction) -> PhoneNumberDiscoverability? {
        return getOrLoadAccountState(tx: tx).phoneNumberDiscoverability
    }

    public func lastSetIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Date {
        return getOrLoadAccountState(tx: tx).lastSetIsDiscoverableByPhoneNumberAt
    }
}

extension TSAccountManagerImpl: PhoneNumberDiscoverabilitySetter {

    public func setPhoneNumberDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability, tx: DBWriteTransaction) {
        mutateWithLock(tx: tx) {
            kvStore.setBool(
                phoneNumberDiscoverability == .everybody,
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
}

extension TSAccountManagerImpl: LocalIdentifiersSetter {

    public func initializeLocalIdentifiers(
        e164: E164,
        aci: Aci,
        pni: Pni?,
        deviceId: UInt32,
        serverAuthToken: String,
        tx: DBWriteTransaction
    ) {
        mutateWithLock(tx: tx) {
            let oldNumber = kvStore.getString(Keys.localPhoneNumber, transaction: tx)
            Logger.info("local number \(oldNumber ?? "nil") -> \(e164.stringValue)")
            kvStore.setString(e164.stringValue, key: Keys.localPhoneNumber, transaction: tx)

            let oldAci = kvStore.getString(Keys.localAci, transaction: tx)
            Logger.info("local aci \(oldAci ?? "nil") -> \(aci.serviceIdUppercaseString)")
            kvStore.setString(aci.serviceIdUppercaseString, key: Keys.localAci, transaction: tx)

            let oldPni = kvStore.getString(Keys.localPni, transaction: tx)
            Logger.info("local pni \(oldPni ?? "nil") -> \(pni?.rawUUID.uuidString ?? "nil")")
            // Encoded without the "PNI:" prefix for backwards compatibility.
            kvStore.setString(pni?.rawUUID.uuidString, key: Keys.localPni, transaction: tx)

            kvStore.setUInt32(deviceId, key: Keys.deviceId, transaction: tx)
            kvStore.setString(serverAuthToken, key: Keys.serverAuthToken, transaction: tx)

            kvStore.setDate(dateProvider(), key: Keys.registrationDate, transaction: tx)
            kvStore.removeValues(
                forKeys: [
                    Keys.isDeregisteredOrDelinked,
                    Keys.reregistrationPhoneNumber,
                    Keys.reregistrationAci
                ],
                transaction: tx
            )
        }
    }

    public func changeLocalNumber(
        newE164: E164,
        aci: Aci,
        pni: Pni?,
        tx: DBWriteTransaction
    ) {
        mutateWithLock(tx: tx) {
            let oldNumber = kvStore.getString(Keys.localPhoneNumber, transaction: tx)
            Logger.info("local number \(oldNumber ?? "nil") -> \(newE164.stringValue)")
            kvStore.setString(newE164.stringValue, key: Keys.localPhoneNumber, transaction: tx)

            let oldAci = kvStore.getString(Keys.localAci, transaction: tx)
            Logger.info("local aci \(oldAci ?? "nil") -> \(aci.serviceIdUppercaseString)")
            kvStore.setString(aci.serviceIdUppercaseString, key: Keys.localAci, transaction: tx)

            let oldPni = kvStore.getString(Keys.localPni, transaction: tx)
            Logger.info("local pni \(oldPni ?? "nil") -> \(pni?.rawUUID.uuidString ?? "nil")")
            // Encoded without the "PNI:" prefix for backwards compatibility.
            kvStore.setString(pni?.rawUUID.uuidString, key: Keys.localPni, transaction: tx)
        }
    }

    public func setIsDeregisteredOrDelinked(_ isDeregisteredOrDelinked: Bool, tx: DBWriteTransaction) -> Bool {
        return mutateWithLock(tx: tx) {
            let oldValue = kvStore.getBool(Keys.isDeregisteredOrDelinked, defaultValue: false, transaction: tx)
            guard oldValue != isDeregisteredOrDelinked else {
                return false
            }
            kvStore.setBool(isDeregisteredOrDelinked, key: Keys.isDeregisteredOrDelinked, transaction: tx)
            return true
        }
    }

    public func resetForReregistration(
        localNumber: E164,
        localAci: Aci,
        wasPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) {
        mutateWithLock(tx: tx) {
            kvStore.removeAll(transaction: tx)

            kvStore.setString(localNumber.stringValue, key: Keys.reregistrationPhoneNumber, transaction: tx)
            kvStore.setString(localAci.serviceIdUppercaseString, key: Keys.reregistrationAci, transaction: tx)
            kvStore.setBool(wasPrimaryDevice, key: Keys.reregistrationWasPrimaryDevice, transaction: tx)
        }
    }

    public func setIsTransferInProgress(_ isTransferInProgress: Bool, tx: DBWriteTransaction) -> Bool {
        let oldValue = kvStore.getBool(Keys.isTransferInProgress, transaction: tx)
        guard oldValue != isTransferInProgress else {
            return false
        }
        mutateWithLock(tx: tx) {
            kvStore.setBool(isTransferInProgress, key: Keys.isTransferInProgress, transaction: tx)
        }
        return true
    }

    public func setWasTransferred(_ wasTransferred: Bool, tx: DBWriteTransaction) -> Bool {
        let oldValue = kvStore.getBool(Keys.wasTransferred, transaction: tx)
        guard oldValue != wasTransferred else {
            return false
        }
        mutateWithLock(tx: tx) {
            kvStore.setBool(wasTransferred, key: Keys.wasTransferred, transaction: tx)
        }
        return true
    }

    public func cleanUpTransferStateOnAppLaunchIfNeeded() {
        guard getOrLoadAccountStateWithMaybeTransaction().isTransferInProgress else {
            // No need for cleanup if transfer wasn't already in progress.
            return
        }
        db.write { tx in
            mutateWithLock(tx: tx) {
                guard kvStore.getBool(Keys.isTransferInProgress, defaultValue: false, transaction: tx) else {
                    return
                }
                kvStore.setBool(false, key: Keys.isTransferInProgress, transaction: tx)
            }
        }
    }
}

extension TSAccountManagerImpl: DBChangeDelegate {

    public func dbChangesDidUpdateExternally() {
        self.db.read(block: reloadAccountState(tx:))
    }
}

extension TSAccountManagerImpl {

    private typealias Keys = AccountState.Keys

    // MARK: - External methods (acquire the lock)

    private func getOrLoadAccountStateWithMaybeTransaction() -> AccountState {
        return accountStateLock.withLock {
            if let accountState = self.cachedAccountState {
                return accountState
            }
            return db.read { tx in
                return self.loadAccountState(tx: tx)
            }
        }
    }

    private func getOrLoadAccountState(tx: DBReadTransaction) -> AccountState {
        return accountStateLock.withLock {
            if let accountState = self.cachedAccountState {
                return accountState
            }
            return loadAccountState(tx: tx)
        }
    }

    private func reloadAccountState(tx: DBReadTransaction) {
        accountStateLock.withLock {
            _ = loadAccountState(tx: tx)
        }
    }

    // MARK: Mutations

    private func mutateWithLock<T>(tx: DBWriteTransaction, _ block: () -> T) -> T {
        return accountStateLock.withLock {
            let returnValue = block()
            // Reload to repopulate the cache; the mutations will
            // write to disk and not actually modify the cached value.
            loadAccountState(tx: tx)

            return returnValue
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

    /// A cache of frequently-accessed database state.
    ///
    /// * Instances of AccountState are immutable.
    /// * None of this state should change often.
    /// * Whenever any of this state changes, we reload all of it.
    ///
    /// This cache changes all of its properties in lockstep, which
    /// helps ensure consistency.
    private struct AccountState {

        let localIdentifiers: LocalIdentifiers?

        let deviceId: UInt32

        let serverAuthToken: String?

        let registrationState: TSRegistrationState
        let registrationDate: Date?

        fileprivate let isTransferInProgress: Bool

        let phoneNumberDiscoverability: PhoneNumberDiscoverability?
        let lastSetIsDiscoverableByPhoneNumberAt: Date

        let isManualMessageFetchEnabled: Bool

        var serverUsername: String? {
            guard let aciString = self.localIdentifiers?.aci.serviceIdString else {
                return nil
            }
            return registrationState.isRegisteredPrimaryDevice ? aciString : "\(aciString).\(deviceId)"
        }

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

            let isTransferInProgress = kvStore.getBool(Keys.isTransferInProgress, defaultValue: false, transaction: tx)
            self.isTransferInProgress = isTransferInProgress

            self.registrationState = Self.loadRegistrationState(
                localIdentifiers: localIdentifiers,
                isPrimaryDevice: isPrimaryDevice,
                isTransferInProgress: isTransferInProgress,
                kvStore: kvStore,
                tx: tx
            )
            self.registrationDate = kvStore.getDate(Keys.registrationDate, transaction: tx)

            self.phoneNumberDiscoverability = kvStore.getBool(Keys.isDiscoverableByPhoneNumber, transaction: tx).map {
                return $0 ? .everybody : .nobody
            }
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
            isTransferInProgress: Bool,
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

            let isDeregisteredOrDelinked = kvStore.getBool(
                Keys.isDeregisteredOrDelinked,
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

                if kvStore.getBool(Keys.reregistrationWasPrimaryDevice, defaultValue: true, transaction: tx) {
                    return .reregistering(
                        phoneNumber: reregistrationPhoneNumber,
                        aci: reregistrationAci
                    )
                } else {
                    return .relinking(
                        phoneNumber: reregistrationPhoneNumber,
                        aci: reregistrationAci
                    )
                }
            } else if isDeregisteredOrDelinked == true {
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
                // We have local identifiers, so we are registered/provisioned.
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
            static let isDeregisteredOrDelinked = "TSAccountManager_IsDeregisteredKey"

            static let reregistrationPhoneNumber = "TSAccountManager_ReregisteringPhoneNumberKey"
            static let reregistrationAci = "TSAccountManager_ReregisteringUUIDKey"
            static let reregistrationWasPrimaryDevice = "TSAccountManager_ReregisteringWasPrimaryDeviceKey"

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
