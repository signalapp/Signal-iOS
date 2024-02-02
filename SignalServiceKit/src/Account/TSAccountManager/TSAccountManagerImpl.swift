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

    fileprivate static let regStateLogger = PrefixedLogger(prefix: "TSRegistrationState")

    public func warmCaches() {
        // Load account state into the cache and log.
        db.read { tx in
            reloadAccountState(logger: Self.regStateLogger, tx: tx).log(Self.regStateLogger)
        }

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
            Self.regStateLogger.info("local number \(oldNumber ?? "nil") -> \(e164)")
            kvStore.setString(e164.stringValue, key: Keys.localPhoneNumber, transaction: tx)

            let oldAci = Aci.parseFrom(aciString: kvStore.getString(Keys.localAci, transaction: tx))
            Self.regStateLogger.info("local aci \(oldAci?.logString ?? "nil") -> \(aci)")
            kvStore.setString(aci.serviceIdUppercaseString, key: Keys.localAci, transaction: tx)

            let oldPni = Pni.parseFrom(pniString: kvStore.getString(Keys.localPni, transaction: tx))
            Self.regStateLogger.info("local pni \(oldPni?.logString ?? "nil") -> \(pni?.logString ?? "nil")")
            // Encoded without the "PNI:" prefix for backwards compatibility.
            kvStore.setString(pni?.rawUUID.uuidString, key: Keys.localPni, transaction: tx)

            Self.regStateLogger.info("device id is primary? \(deviceId == OWSDevice.primaryDeviceId)")
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
            Self.regStateLogger.info("local number \(oldNumber ?? "nil") -> \(newE164.stringValue)")
            kvStore.setString(newE164.stringValue, key: Keys.localPhoneNumber, transaction: tx)

            let oldAci = kvStore.getString(Keys.localAci, transaction: tx)
            Self.regStateLogger.info("local aci \(oldAci ?? "nil") -> \(aci.serviceIdUppercaseString)")
            kvStore.setString(aci.serviceIdUppercaseString, key: Keys.localAci, transaction: tx)

            let oldPni = kvStore.getString(Keys.localPni, transaction: tx)
            Self.regStateLogger.info("local pni \(oldPni ?? "nil") -> \(pni?.rawUUID.uuidString ?? "nil")")
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
            if isDeregisteredOrDelinked {
                Self.regStateLogger.warn("Deregistered!")
            } else {
                Self.regStateLogger.info("Resetting isDeregistered/Delinked")
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
            Self.regStateLogger.info("Resetting for reregistration, was primary? \(wasPrimaryDevice)")
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
        if isTransferInProgress {
            Self.regStateLogger.warn("Transfer in progress!")
        } else {
            Self.regStateLogger.info("Resetting isTransferInProgress")
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
        if wasTransferred {
            Self.regStateLogger.warn("Marking wasTransferred!")
        } else {
            Self.regStateLogger.info("Resetting wasTransferred")
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
                Self.regStateLogger.info("Transfer was in progress but app relaunched; resetting")
                kvStore.setBool(false, key: Keys.isTransferInProgress, transaction: tx)
            }
        }
    }
}

extension TSAccountManagerImpl: DBChangeDelegate {

    public func dbChangesDidUpdateExternally() {
        self.db.read { tx in
            _ = reloadAccountState(logger: nil, tx: tx)
        }
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

    @discardableResult
    private func reloadAccountState(
        logger: PrefixedLogger?,
        tx: DBReadTransaction
    ) -> AccountState {
        return accountStateLock.withLock {
            return loadAccountState(
                logger: logger,
                tx: tx
            )
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
    private func loadAccountState(
        logger: PrefixedLogger? = nil,
        tx: DBReadTransaction
    ) -> AccountState {
        let accountState = AccountState.init(
            kvStore: kvStore,
            logger: logger,
            tx: tx
        )
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

        /// Logger is optional so we don't log every time we load state (which is a lot),
        /// and can just do so once per app launch.
        init(
            kvStore: KeyValueStore,
            logger: PrefixedLogger?,
            tx: DBReadTransaction
        ) {
            // WARNING: AccountState is loaded before data migrations have run (as well as after).
            // Do not use data migrations to update AccountState data; do it through schema migrations
            // or through normal write transactions. TSAccountManager should be the only code accessing this state anyway.
            let localIdentifiers = Self.loadLocalIdentifiers(
                kvStore: kvStore,
                logger: logger,
                tx: tx
            )
            self.localIdentifiers = localIdentifiers

            let persistedDeviceId = kvStore.getUInt32(
                Keys.deviceId,
                transaction: tx
            )
            // Assume primary, for backwards compatibility.
            self.deviceId = persistedDeviceId ?? OWSDevice.primaryDeviceId

            self.serverAuthToken = kvStore.getString(Keys.serverAuthToken, transaction: tx)

            logger?.info("Has server auth token: \(self.serverAuthToken != nil)")

            let isPrimaryDevice: Bool?
            if let persistedDeviceId {
                isPrimaryDevice = persistedDeviceId == OWSDevice.primaryDeviceId
                logger?.info("Device id loaded, is primary: \(isPrimaryDevice!)")
            } else {
                isPrimaryDevice = nil
                logger?.info("Using default primary device id")
            }

            let isTransferInProgress = kvStore.getBool(Keys.isTransferInProgress, defaultValue: false, transaction: tx)
            self.isTransferInProgress = isTransferInProgress

            self.registrationState = Self.loadRegistrationState(
                localIdentifiers: localIdentifiers,
                isPrimaryDevice: isPrimaryDevice,
                isTransferInProgress: isTransferInProgress,
                kvStore: kvStore,
                logger: logger,
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
            logger: PrefixedLogger?,
            tx: DBReadTransaction
        ) -> LocalIdentifiers? {
            guard
                let localNumber = kvStore.getString(Keys.localPhoneNumber, transaction: tx)
            else {
                logger?.info("No local phone number!")
                return nil
            }
            guard let localAci = Aci.parseFrom(aciString: kvStore.getString(Keys.localAci, transaction: tx)) else {
                logger?.info("No local aci!")
                return nil
            }
            let localPni = Pni.parseFrom(pniString: kvStore.getString(Keys.localPni, transaction: tx))
            logger?.info("Has local pni? \(localPni != nil)")
            return LocalIdentifiers(aci: localAci, pni: localPni, phoneNumber: localNumber)
        }

        private static func loadRegistrationState(
            localIdentifiers: LocalIdentifiers?,
            isPrimaryDevice: Bool?,
            isTransferInProgress: Bool,
            kvStore: KeyValueStore,
            logger: PrefixedLogger?,
            tx: DBReadTransaction
        ) -> TSRegistrationState {
            let reregistrationPhoneNumber = kvStore.getString(
                Keys.reregistrationPhoneNumber,
                transaction: tx
            )
            // TODO: Eventually require reregistrationAci during re-registration.
            let reregistrationAci = Aci.parseFrom(aciString: kvStore.getString(
                Keys.reregistrationAci,
                transaction: tx
            ))

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
                logger?.info("WasTransferred=true; marking as transferred")
                // If we transferred, we are transferred regardless of what else
                // may be going on. Other state might be a mess; doesn't matter.
                return .transferred
            } else if isTransferInProgress {
                // Ditto for a transfer in progress; regardless of whatever
                // else is going on (except being transferred) this takes precedence.
                switch isPrimaryDevice {
                case true:
                    logger?.info("isTransferInProgress=true on primary")
                    return .transferringPrimaryOutgoing
                case false:
                    logger?.info("isTransferInProgress=true on secondary")
                    return .transferringLinkedOutgoing
                default:
                    logger?.info("isTransferInProgress=true on unknown primary state; transfer incoming")
                    // If we never knew primary device state, it must be an
                    // incoming transfer, where we started from a blank state.
                    return .transferringIncoming
                }
            } else if let reregistrationPhoneNumber {
                // If a "reregistrationPhoneNumber" is present, we are reregistering.
                // reregistrationAci is optional (for now, see above TODO).
                // isDeregistered is probably also true; this takes precedence.

                let shouldDefaultToPrimaryDevice = UIDevice.current.userInterfaceIdiom == .phone
                if kvStore.getBool(
                    Keys.reregistrationWasPrimaryDevice,
                    defaultValue: shouldDefaultToPrimaryDevice,
                    transaction: tx
                ) {
                    logger?.info("rereg phone number set, and wasPrimaryDevice true; reregistering")
                    return .reregistering(
                        phoneNumber: reregistrationPhoneNumber,
                        aci: reregistrationAci
                    )
                } else {
                    logger?.info("rereg phone number set, and wasPrimaryDevice false; relinking")
                    return .relinking(
                        phoneNumber: reregistrationPhoneNumber,
                        aci: reregistrationAci
                    )
                }
            } else if isDeregisteredOrDelinked == true {
                // if isDeregistered is true, we may have been registered
                // or not. But its being true means we should be deregistered
                // (or delinked, based on whether this is a primary).
                // isPrimaryDevice should have some value; if we've explicitly
                // set isDeregistered that means we _were_ registered before.
                switch isPrimaryDevice {
                case true:
                    logger?.info("Deregistered")
                    return .deregistered
                case false:
                    logger?.info("Delinked")
                    return .delinked
                default:
                    let logString = "Deregistered, but primary device state unknown!"
                    if let logger {
                        logger.warn(logString)
                    } else {
                        owsAssertDebug(false, logString)
                    }
                    return .delinked
                }
            } else if localIdentifiers == nil {
                // Setting localIdentifiers is what marks us as registered
                // in primary registration. (As long as above conditions don't
                // override that state)
                // For provisioning, we set them before finishing, but the fact
                // that we set them means we linked (but didn't finish yet).
                logger?.info("Not deregistered but local identifiers unavailable; not registered yet")
                return .unregistered
            } else {
                // We have local identifiers, so we are registered/provisioned.
                switch isPrimaryDevice {
                case true:
                    logger?.info("Registered")
                    return .registered
                case false:
                    logger?.info("Provisioned")
                    return .provisioned
                default:
                    logger?.warn("Registered but primary state unknown; marking provisioned")
                    return .provisioned
                }
            }
        }

        func log(_ logger: PrefixedLogger) {
            logger.info("RegistrationState: \(registrationState.logString)")
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
