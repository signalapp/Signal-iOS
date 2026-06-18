//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class TSAccountManagerImpl: TSAccountManager {

    private let appReadiness: AppReadiness
    private let dateProvider: DateProvider
    private let db: any DB

    private let kvStore: NewKeyValueStore

    private let accountStateLock = UnfairLock()
    private var cachedAccountState: AccountState?

    public init(
        appReadiness: AppReadiness,
        dateProvider: @escaping DateProvider,
        databaseChangeObserver: DatabaseChangeObserver,
        db: any DB,
    ) {
        self.appReadiness = appReadiness
        self.dateProvider = dateProvider
        self.db = db

        let kvStore = NewKeyValueStore(
            collection: "TSStorageUserAccountCollection",
        )
        self.kvStore = kvStore

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            databaseChangeObserver.appendDatabaseChangeDelegate(self)
        }
    }

    fileprivate static let regStateLogger = PrefixedLogger(prefix: "[Account]")

    public func warmCaches(tx: DBReadTransaction) {
        // Load account state into the cache and log.
        reloadAccountState(tx: tx).log(Self.regStateLogger)
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

    public var storedDeviceIdWithMaybeTransaction: LocalDeviceId {
        return getOrLoadAccountStateWithMaybeTransaction().deviceId
    }

    public func storedDeviceId(tx: DBReadTransaction) -> LocalDeviceId {
        return getOrLoadAccountState(tx: tx).deviceId
    }

    // MARK: - Registration IDs

    private static var aciRegistrationIdKey: String = "TSStorageLocalRegistrationId"
    private static var pniRegistrationIdKey: String = "TSStorageLocalPniRegistrationId"

    public func getRegistrationId(for identity: OWSIdentity, tx: DBReadTransaction) -> UInt32? {
        let key = switch identity {
        case .aci: Self.aciRegistrationIdKey
        case .pni: Self.pniRegistrationIdKey
        }
        return kvStore.fetchValue(Int64.self, forKey: key, tx: tx).map(UInt32.init(truncatingIfNeeded:))
    }

    public func setRegistrationId(_ newRegistrationId: UInt32, for identity: OWSIdentity, tx: DBWriteTransaction) {
        let key = switch identity {
        case .aci: Self.aciRegistrationIdKey
        case .pni: Self.pniRegistrationIdKey
        }
        kvStore.writeValue(Int64(newRegistrationId), forKey: key, tx: tx)
    }

    public func clearRegistrationIds(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Self.aciRegistrationIdKey, tx: tx)
        kvStore.removeValue(forKey: Self.pniRegistrationIdKey, tx: tx)
    }

    // MARK: - Manual Message Fetch

    public func isManualMessageFetchEnabled(tx: DBReadTransaction) -> Bool {
        return getOrLoadAccountState(tx: tx).isManualMessageFetchEnabled
    }

    public func setIsManualMessageFetchEnabled(_ isEnabled: Bool, tx: DBWriteTransaction) {
        mutateWithLock(tx: tx) {
            kvStore.writeValue(isEnabled, forKey: Keys.isManualMessageFetchEnabled, tx: tx)
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
            kvStore.writeValue(
                phoneNumberDiscoverability == .everybody,
                forKey: Keys.isDiscoverableByPhoneNumber,
                tx: tx,
            )

            kvStore.writeValue(
                dateProvider(),
                forKey: Keys.lastSetIsDiscoverableByPhoneNumber,
                tx: tx,
            )
        }
    }
}

extension TSAccountManagerImpl: LocalIdentifiersSetter {

    public func initializeLocalIdentifiers(
        e164: E164,
        aci: Aci,
        pni: Pni,
        deviceId: DeviceId,
        serverAuthToken: String,
        tx: DBWriteTransaction,
    ) {
        mutateWithLock(tx: tx) {
            let oldNumber = kvStore.fetchValue(String.self, forKey: Keys.localPhoneNumber, tx: tx)
            Self.regStateLogger.info("local number \(oldNumber ?? "nil") -> \(e164)")
            kvStore.writeValue(e164.stringValue, forKey: Keys.localPhoneNumber, tx: tx)

            let oldAci = Aci.parseFrom(aciString: kvStore.fetchValue(String.self, forKey: Keys.localAci, tx: tx))
            Self.regStateLogger.info("local aci \(oldAci?.logString ?? "nil") -> \(aci)")
            kvStore.writeValue(aci.serviceIdUppercaseString, forKey: Keys.localAci, tx: tx)

            let oldPni = Pni.parseFrom(pniString: kvStore.fetchValue(String.self, forKey: Keys.localPni, tx: tx))
            Self.regStateLogger.info("local pni \(oldPni?.logString ?? "nil") -> \(pni)")
            // Encoded without the "PNI:" prefix for backwards compatibility.
            kvStore.writeValue(pni.rawUUID.uuidString, forKey: Keys.localPni, tx: tx)

            Self.regStateLogger.info("device id is primary? \(deviceId == .primary)")
            kvStore.writeValue(Int64(deviceId.uint32Value), forKey: Keys.deviceId, tx: tx)
            kvStore.writeValue(serverAuthToken, forKey: Keys.serverAuthToken, tx: tx)

            kvStore.writeValue(dateProvider(), forKey: Keys.registrationDate, tx: tx)

            kvStore.removeValue(forKey: Keys.isDeregisteredOrDelinked, tx: tx)
            kvStore.removeValue(forKey: Keys.reregistrationPhoneNumber, tx: tx)
            kvStore.removeValue(forKey: Keys.reregistrationAci, tx: tx)
            kvStore.removeValue(forKey: Keys.reregistrationWasPrimaryDevice, tx: tx)
        }
    }

    public func changeLocalNumber(
        newE164: E164,
        aci: Aci,
        pni: Pni,
        tx: DBWriteTransaction,
    ) {
        mutateWithLock(tx: tx) {
            let oldNumber = kvStore.fetchValue(String.self, forKey: Keys.localPhoneNumber, tx: tx)
            Self.regStateLogger.info("local number \(oldNumber ?? "nil") -> \(newE164.stringValue)")
            kvStore.writeValue(newE164.stringValue, forKey: Keys.localPhoneNumber, tx: tx)

            let oldAci = kvStore.fetchValue(String.self, forKey: Keys.localAci, tx: tx)
            Self.regStateLogger.info("local aci \(oldAci ?? "nil") -> \(aci)")
            kvStore.writeValue(aci.serviceIdUppercaseString, forKey: Keys.localAci, tx: tx)

            let oldPni = kvStore.fetchValue(String.self, forKey: Keys.localPni, tx: tx)
            Self.regStateLogger.info("local pni \(oldPni ?? "nil") -> \(pni)")
            // Encoded without the "PNI:" prefix for backwards compatibility.
            kvStore.writeValue(pni.rawUUID.uuidString, forKey: Keys.localPni, tx: tx)
        }
    }

    public func setIsDeregisteredOrDelinked(_ isDeregisteredOrDelinked: Bool, tx: DBWriteTransaction) -> Bool {
        return mutateWithLock(tx: tx) {
            let oldValue = kvStore.fetchValue(Bool.self, forKey: Keys.isDeregisteredOrDelinked, tx: tx) ?? false
            guard oldValue != isDeregisteredOrDelinked else {
                return false
            }
            if isDeregisteredOrDelinked {
                Self.regStateLogger.warn("Deregistered!")
            } else {
                Self.regStateLogger.info("Resetting isDeregistered/Delinked")
            }
            if isDeregisteredOrDelinked {
                kvStore.writeValue(isDeregisteredOrDelinked, forKey: Keys.isDeregisteredOrDelinked, tx: tx)
            } else {
                kvStore.removeValue(forKey: Keys.isDeregisteredOrDelinked, tx: tx)
            }
            return true
        }
    }

    public func resetForReregistration(
        localNumber: E164,
        localAci: Aci,
        discoverability: PhoneNumberDiscoverability?,
        wasPrimaryDevice: Bool,
        tx: DBWriteTransaction,
    ) {
        mutateWithLock(tx: tx) {
            Self.regStateLogger.info("Resetting for reregistration, was primary? \(wasPrimaryDevice)")
            kvStore.removeAll(tx: tx)

            kvStore.writeValue(localNumber.stringValue, forKey: Keys.reregistrationPhoneNumber, tx: tx)
            kvStore.writeValue(localAci.serviceIdUppercaseString, forKey: Keys.reregistrationAci, tx: tx)
            kvStore.writeValue(wasPrimaryDevice, forKey: Keys.reregistrationWasPrimaryDevice, tx: tx)
        }

        if let discoverability {
            setPhoneNumberDiscoverability(discoverability, tx: tx)
        }
    }

    public func setIsTransferInProgress(_ isTransferInProgress: Bool, tx: DBWriteTransaction) -> Bool {
        let oldValue = kvStore.fetchValue(Bool.self, forKey: Keys.isTransferInProgress, tx: tx) ?? false
        guard oldValue != isTransferInProgress else {
            return false
        }
        if isTransferInProgress {
            Self.regStateLogger.warn("Transfer in progress!")
        } else {
            Self.regStateLogger.info("Resetting isTransferInProgress")
        }
        mutateWithLock(tx: tx) {
            if isTransferInProgress {
                kvStore.writeValue(isTransferInProgress, forKey: Keys.isTransferInProgress, tx: tx)
            } else {
                kvStore.removeValue(forKey: Keys.isTransferInProgress, tx: tx)
            }
        }
        return true
    }

    public func setWasTransferred(_ wasTransferred: Bool, tx: DBWriteTransaction) -> Bool {
        let oldValue = kvStore.fetchValue(Bool.self, forKey: Keys.wasTransferred, tx: tx) ?? false
        guard oldValue != wasTransferred else {
            return false
        }
        if wasTransferred {
            Self.regStateLogger.warn("Marking wasTransferred!")
        } else {
            Self.regStateLogger.info("Resetting wasTransferred")
        }
        mutateWithLock(tx: tx) {
            if wasTransferred {
                kvStore.writeValue(wasTransferred, forKey: Keys.wasTransferred, tx: tx)
            } else {
                kvStore.removeValue(forKey: Keys.wasTransferred, tx: tx)
            }
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
                guard kvStore.fetchValue(Bool.self, forKey: Keys.isTransferInProgress, tx: tx) ?? false else {
                    return
                }
                Self.regStateLogger.info("Transfer was in progress but app relaunched; resetting")
                kvStore.removeValue(forKey: Keys.isTransferInProgress, tx: tx)
            }
        }
    }
}

extension TSAccountManagerImpl: DatabaseChangeDelegate {
    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {}

    public func databaseChangesDidUpdateExternally() {
        self.db.read { tx in
            _ = reloadAccountState(tx: tx)
        }
    }

    public func databaseChangesDidReset() {}
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
    private func reloadAccountState(tx: DBReadTransaction) -> AccountState {
        return accountStateLock.withLock {
            return loadAccountState(tx: tx)
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
        let accountState = AccountState(kvStore: kvStore, tx: tx)
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

        let deviceId: LocalDeviceId

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
            kvStore: NewKeyValueStore,
            tx: DBReadTransaction,
        ) {
            // WARNING: AccountState is loaded before data migrations have run (as well as after).
            // Do not use data migrations to update AccountState data; do it through schema migrations
            // or through normal write transactions. TSAccountManager should be the only code accessing this state anyway.
            let localIdentifiers = Self.loadLocalIdentifiers(
                kvStore: kvStore,
                tx: tx,
            )
            self.localIdentifiers = localIdentifiers

            let persistedDeviceId = kvStore.fetchValue(Int64.self, forKey: Keys.deviceId, tx: tx).map(UInt32.init(truncatingIfNeeded:))

            if let persistedDeviceId {
                if let validatedDeviceId = DeviceId(validating: persistedDeviceId) {
                    self.deviceId = .valid(validatedDeviceId)
                } else {
                    self.deviceId = .invalid
                }
            } else {
                // Assume primary, for backwards compatibility.
                self.deviceId = .valid(.primary)
            }

            self.serverAuthToken = kvStore.fetchValue(String.self, forKey: Keys.serverAuthToken, tx: tx)

            let isPrimaryDevice: Bool?
            if let persistedDeviceId {
                isPrimaryDevice = persistedDeviceId == DeviceId.primary.rawValue
            } else {
                isPrimaryDevice = nil
            }

            let isTransferInProgress = kvStore.fetchValue(Bool.self, forKey: Keys.isTransferInProgress, tx: tx) ?? false
            self.isTransferInProgress = isTransferInProgress

            self.registrationState = Self.loadRegistrationState(
                localIdentifiers: localIdentifiers,
                isPrimaryDevice: isPrimaryDevice,
                isTransferInProgress: isTransferInProgress,
                kvStore: kvStore,
                tx: tx,
            )
            if self.registrationState.isRegistered {
                owsPrecondition(localIdentifiers != nil, "If we're registered, we must have LocalIdentifiers.")
            }
            self.registrationDate = kvStore.fetchValue(Date.self, forKey: Keys.registrationDate, tx: tx)

            self.phoneNumberDiscoverability = kvStore.fetchValue(Bool.self, forKey: Keys.isDiscoverableByPhoneNumber, tx: tx).map {
                return $0 ? .everybody : .nobody
            }
            self.lastSetIsDiscoverableByPhoneNumberAt = kvStore.fetchValue(Date.self, forKey: Keys.lastSetIsDiscoverableByPhoneNumber, tx: tx) ?? .distantPast

            self.isManualMessageFetchEnabled = kvStore.fetchValue(Bool.self, forKey: Keys.isManualMessageFetchEnabled, tx: tx) ?? false
        }

        private static func loadLocalIdentifiers(
            kvStore: NewKeyValueStore,
            tx: DBReadTransaction,
        ) -> LocalIdentifiers? {
            let localNumber = kvStore.fetchValue(String.self, forKey: Keys.localPhoneNumber, tx: tx)
            let localAci = Aci.parseFrom(aciString: kvStore.fetchValue(String.self, forKey: Keys.localAci, tx: tx))
            let localPni = Pni.parseFrom(pniString: kvStore.fetchValue(String.self, forKey: Keys.localPni, tx: tx))
            guard let localNumber, let localAci else {
                owsAssertDebug((localNumber == nil) == (localAci == nil), "ACI/phone number presence must match")
                return nil
            }
            return LocalIdentifiers(aci: localAci, pni: localPni, phoneNumber: localNumber)
        }

        private static func loadRegistrationState(
            localIdentifiers: LocalIdentifiers?,
            isPrimaryDevice: Bool?,
            isTransferInProgress: Bool,
            kvStore: NewKeyValueStore,
            tx: DBReadTransaction,
        ) -> TSRegistrationState {
            let reregistrationPhoneNumber = kvStore.fetchValue(String.self, forKey: Keys.reregistrationPhoneNumber, tx: tx)
            // TODO: Eventually require reregistrationAci during re-registration.
            let reregistrationAci = Aci.parseFrom(aciString: kvStore.fetchValue(String.self, forKey: Keys.reregistrationAci, tx: tx))
            let isDeregisteredOrDelinked = kvStore.fetchValue(Bool.self, forKey: Keys.isDeregisteredOrDelinked, tx: tx) ?? false
            let wasTransferred = kvStore.fetchValue(Bool.self, forKey: Keys.wasTransferred, tx: tx) ?? false

            // Go in semi-reverse order; with higher priority stuff going first.
            if wasTransferred {
                // If we transferred, we are transferred regardless of what else
                // may be going on. Other state might be a mess; doesn't matter.
                return .transferred
            } else if isTransferInProgress {
                // Ditto for a transfer in progress; regardless of whatever
                // else is going on (except being transferred) this takes precedence.
                switch isPrimaryDevice {
                case true:
                    return .transferringPrimaryOutgoing
                case false:
                    return .transferringLinkedOutgoing
                default:
                    // If we never knew primary device state, it must be an
                    // incoming transfer, where we started from a blank state.
                    return .transferringIncoming
                }
            } else if let reregistrationPhoneNumber {
                // If a "reregistrationPhoneNumber" is present, we are reregistering.
                // reregistrationAci is optional (for now, see above TODO).
                // isDeregistered is probably also true; this takes precedence.

                let shouldDefaultToPrimaryDevice = UIDevice.current.userInterfaceIdiom == .phone
                if kvStore.fetchValue(Bool.self, forKey: Keys.reregistrationWasPrimaryDevice, tx: tx) ?? shouldDefaultToPrimaryDevice {
                    return .reregistering(
                        phoneNumber: reregistrationPhoneNumber,
                        aci: reregistrationAci,
                    )
                } else {
                    return .relinking(
                        phoneNumber: reregistrationPhoneNumber,
                        aci: reregistrationAci,
                    )
                }
            } else if isDeregisteredOrDelinked {
                // if isDeregistered is true, we may have been registered
                // or not. But its being true means we should be deregistered
                // (or delinked, based on whether this is a primary).
                // isPrimaryDevice should have some value; if we've explicitly
                // set isDeregistered that means we _were_ registered before.
                switch isPrimaryDevice {
                case true:
                    return .deregistered
                case false:
                    return .delinked
                default:
                    owsFailDebug("deregistered or delinked && isPrimaryDevice == nil")
                    return .delinked
                }
            } else if localIdentifiers == nil {
                // Setting localIdentifiers is what marks us as registered
                // in primary registration. (As long as above conditions don't
                // override that state)
                // For provisioning, we set them before finishing, but the fact
                // that we set them means we linked (but didn't finish yet).
                return .unregistered
            } else {
                // We have local identifiers, so we are registered/provisioned.
                switch isPrimaryDevice {
                case true:
                    return .registered
                case false:
                    return .provisioned
                default:
                    owsFailDebug("registered or provisioned && isPrimaryDevice == nil")
                    return .provisioned
                }
            }
        }

        func log(_ logger: PrefixedLogger) {
            logger.info("registrationState: \(registrationState.logString); serverAuthToken? \(serverAuthToken != nil)")
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
