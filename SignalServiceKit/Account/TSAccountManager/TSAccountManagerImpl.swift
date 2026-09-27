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

    public func getRegistrationId(for identity: OWSIdentity, tx: DBReadTransaction) -> UInt32? {
        let key = switch identity {
        case .aci: Keys.aciRegistrationIdKey
        case .pni: Keys.pniRegistrationIdKey
        }
        return kvStore.fetchValue(Int64.self, forKey: key, tx: tx).map(UInt32.init(truncatingIfNeeded:))
    }

    public func setRegistrationId(_ newRegistrationId: UInt32, for identity: OWSIdentity, tx: DBWriteTransaction) {
        let key = switch identity {
        case .aci: Keys.aciRegistrationIdKey
        case .pni: Keys.pniRegistrationIdKey
        }
        kvStore.writeValue(Int64(newRegistrationId), forKey: key, tx: tx)
    }

    public func clearRegistrationIds(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.aciRegistrationIdKey, tx: tx)
        kvStore.removeValue(forKey: Keys.pniRegistrationIdKey, tx: tx)
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
        aci: Aci,
        phoneNumber: LocalIdentifiers.PhoneNumber,
        deviceId: DeviceId,
        serverAuthToken: String,
        tx: DBWriteTransaction,
    ) {
        mutateWithLock(tx: tx) {
            let oldNumber = kvStore.fetchValue(String.self, forKey: Keys.localPhoneNumber, tx: tx)
            Self.regStateLogger.info("local number \(oldNumber ?? "nil") -> \(phoneNumber.e164)")
            kvStore.writeValue(phoneNumber.e164.stringValue, forKey: Keys.localPhoneNumber, tx: tx)

            let oldAci = Aci.parseFrom(aciString: kvStore.fetchValue(String.self, forKey: Keys.localAci, tx: tx))
            Self.regStateLogger.info("local aci \(oldAci?.logString ?? "nil") -> \(aci)")
            kvStore.writeValue(aci.serviceIdUppercaseString, forKey: Keys.localAci, tx: tx)

            let oldPni = Pni.parseFrom(pniString: kvStore.fetchValue(String.self, forKey: Keys.localPni, tx: tx))
            Self.regStateLogger.info("local pni \(oldPni?.logString ?? "nil") -> \(phoneNumber.pni)")
            // Encoded without the "PNI:" prefix for backwards compatibility.
            kvStore.writeValue(phoneNumber.pni.rawUUID.uuidString, forKey: Keys.localPni, tx: tx)

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
        aci: Aci,
        phoneNumber: LocalIdentifiers.PhoneNumber,
        tx: DBWriteTransaction,
    ) {
        mutateWithLock(tx: tx) {
            let oldNumber = kvStore.fetchValue(String.self, forKey: Keys.localPhoneNumber, tx: tx)
            Self.regStateLogger.info("local number \(oldNumber ?? "nil") -> \(phoneNumber.e164.stringValue)")
            kvStore.writeValue(phoneNumber.e164.stringValue, forKey: Keys.localPhoneNumber, tx: tx)

            let oldAci = kvStore.fetchValue(String.self, forKey: Keys.localAci, tx: tx)
            Self.regStateLogger.info("local aci \(oldAci ?? "nil") -> \(aci)")
            kvStore.writeValue(aci.serviceIdUppercaseString, forKey: Keys.localAci, tx: tx)

            let oldPni = kvStore.fetchValue(String.self, forKey: Keys.localPni, tx: tx)
            Self.regStateLogger.info("local pni \(oldPni ?? "nil") -> \(phoneNumber.pni)")
            // Encoded without the "PNI:" prefix for backwards compatibility.
            kvStore.writeValue(phoneNumber.pni.rawUUID.uuidString, forKey: Keys.localPni, tx: tx)
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
        aci: Aci?,
        phoneNumber: E164,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction,
    ) {
        mutateWithLock(tx: tx) {
            Self.regStateLogger.info("resetting for reregistration; isPrimary? \(isPrimaryDevice)")

            kvStore.writeValue(phoneNumber.stringValue, forKey: Keys.reregistrationPhoneNumber, tx: tx)
            kvStore.writeValue(aci?.serviceIdUppercaseString, forKey: Keys.reregistrationAci, tx: tx)
            kvStore.writeValue(isPrimaryDevice, forKey: Keys.reregistrationWasPrimaryDevice, tx: tx)

            let keysToKeep: Set<String> = [
                Keys.isDiscoverableByPhoneNumber,
                Keys.lastSetIsDiscoverableByPhoneNumber,
                Keys.reregistrationAci,
                Keys.reregistrationPhoneNumber,
                Keys.reregistrationWasPrimaryDevice,
            ]
            let keysToRemove: Set<String> = [
                Keys.deviceId,
                Keys.isDeregisteredOrDelinked,
                Keys.isManualMessageFetchEnabled,
                Keys.isTransferInProgress,
                Keys.localAci,
                Keys.localPhoneNumber,
                Keys.localPni,
                Keys.aciRegistrationIdKey,
                Keys.pniRegistrationIdKey,
                Keys.registrationDate,
                Keys.serverAuthToken,
                Keys.wasTransferred,
            ]
            for key in kvStore.fetchKeys(tx: tx) {
                if keysToKeep.contains(key) {
                    continue
                }
                owsAssertDebug(keysToRemove.contains(key), "unknown key should be added to a set")
                kvStore.removeValue(forKey: key, tx: tx)
            }
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
            let (aci, phoneNumber, pni) = Self.loadLocalIdentifiers(
                kvStore: kvStore,
                tx: tx,
            )
            self.localIdentifiers = { () -> LocalIdentifiers? in
                guard let phoneNumber, let aci else {
                    owsAssertDebug((phoneNumber == nil) == (aci == nil), "ACI/phone number presence must match")
                    return nil
                }
                return LocalIdentifiers(aci: aci, pni: pni, phoneNumber: phoneNumber)
            }()

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
                aci: aci,
                phoneNumber: phoneNumber,
                pni: pni,
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
        ) -> (aci: Aci?, phoneNumber: String?, pni: Pni?) {
            let localNumber = kvStore.fetchValue(String.self, forKey: Keys.localPhoneNumber, tx: tx)
            let localAci = Aci.parseFrom(aciString: kvStore.fetchValue(String.self, forKey: Keys.localAci, tx: tx))
            let localPni = Pni.parseFrom(pniString: kvStore.fetchValue(String.self, forKey: Keys.localPni, tx: tx))
            return (localAci, localNumber, localPni)
        }

        private static func loadRegistrationState(
            aci: Aci?,
            phoneNumber: String?,
            pni: Pni?,
            isPrimaryDevice: Bool?,
            isTransferInProgress: Bool,
            kvStore: NewKeyValueStore,
            tx: DBReadTransaction,
        ) -> TSRegistrationState {
            // Go in semi-reverse order; with higher priority stuff going first.
            let wasTransferred = kvStore.fetchValue(Bool.self, forKey: Keys.wasTransferred, tx: tx) ?? false
            if wasTransferred {
                // If we transferred, we are transferred regardless of what else
                // may be going on. Other state might be a mess; doesn't matter.
                return .transferred
            }
            if isTransferInProgress {
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
            }
            let reregistrationPhoneNumber = kvStore.fetchValue(String.self, forKey: Keys.reregistrationPhoneNumber, tx: tx)
            if let reregistrationPhoneNumber {
                // (Note: isDeregistered is probably also true; this takes precedence.)
                let reregistrationAci = Aci.parseFrom(aciString: kvStore.fetchValue(String.self, forKey: Keys.reregistrationAci, tx: tx))

                let shouldDefaultToPrimaryDevice = UIDevice.current.userInterfaceIdiom == .phone
                if kvStore.fetchValue(Bool.self, forKey: Keys.reregistrationWasPrimaryDevice, tx: tx) ?? shouldDefaultToPrimaryDevice {
                    return .reregistering(ReregisteringLocalIdentifiers(phoneNumber: reregistrationPhoneNumber, aci: reregistrationAci))
                } else {
                    return .relinking(ReregisteringLocalIdentifiers(phoneNumber: reregistrationPhoneNumber, aci: reregistrationAci))
                }
            }
            let isDeregisteredOrDelinked = kvStore.fetchValue(Bool.self, forKey: Keys.isDeregisteredOrDelinked, tx: tx) ?? false
            if isDeregisteredOrDelinked {
                // if isDeregistered is true, we may have been registered
                // or not. But its being true means we should be deregistered
                // (or delinked, based on whether this is a primary).
                // isPrimaryDevice should have some value; if we've explicitly
                // set isDeregistered that means we _were_ registered before.
                let localIdentifiers = DeregisteredLocalIdentifiers(aci: aci, phoneNumber: phoneNumber, pni: pni)
                switch isPrimaryDevice {
                case true:
                    return .deregistered(localIdentifiers)
                case false:
                    return .delinked(localIdentifiers)
                default:
                    owsFailDebug("deregistered or delinked && isPrimaryDevice == nil")
                    return .delinked(localIdentifiers)
                }
            }
            if let aci, let phoneNumber {
                let localIdentifiers = LocalIdentifiers(aci: aci, pni: pni, phoneNumber: phoneNumber)
                // We have local identifiers, so we are registered/provisioned.
                switch isPrimaryDevice {
                case true:
                    return .registered(localIdentifiers)
                case false:
                    return .provisioned(localIdentifiers)
                default:
                    owsFailDebug("registered or provisioned && isPrimaryDevice == nil")
                    return .provisioned(localIdentifiers)
                }
            }
            // Setting localIdentifiers is what marks us as registered
            // in primary registration. (As long as above conditions don't
            // override that state)
            // For provisioning, we set them before finishing, but the fact
            // that we set them means we linked (but didn't finish yet).
            return .unregistered
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

            static let aciRegistrationIdKey = "TSStorageLocalRegistrationId"
            static let pniRegistrationIdKey = "TSStorageLocalPniRegistrationId"

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
