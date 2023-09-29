//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class TSAccountManagerImpl: TSAccountManagerProtocol {

    private let appReadiness: Shims.AppReadiness
    private let dateProvider: DateProvider
    private let db: DB
    private let schedulers: Schedulers

    private let accountStateManager: AccountStateManager
    private let kvStore: KeyValueStore

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
        self.accountStateManager = AccountStateManager(
            dateProvider: dateProvider,
            db: db,
            kvStore: kvStore
        )
        self.kvStore = kvStore

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            if !self.appReadiness.isMainApp {
                self.db.appendDbChangeDelegate(self)
            }
        }
    }

    /// Temporary method until old TSAccountManager is deleted. While both exist,
    /// each needs to inform the other about account state updates so the other
    /// can update their cache.
    /// Called inside the lock that is shared between both TSAccountManagers.
    public func tmp_loadAccountState(tx: DBReadTransaction) {
        owsAssertDebug(FeatureFlags.tsAccountManagerBridging, "Canary")
        accountStateManager.tmp_loadAccountState(tx: tx)
    }

    public func warmCaches() {
        // Load account state into the cache and log.
        accountStateManager.getOrLoadAccountStateWithMaybeTransaction().log()
    }

    // MARK: - Local Identifiers

    public var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? {
        return accountStateManager.getOrLoadAccountStateWithMaybeTransaction().localIdentifiers
    }

    public func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return accountStateManager.getOrLoadAccountState(tx: tx).localIdentifiers
    }

    // MARK: - Registration State

    public var registrationStateWithMaybeSneakyTransaction: TSRegistrationState {
        return accountStateManager.getOrLoadAccountStateWithMaybeTransaction().registrationState
    }

    public func registrationState(tx: DBReadTransaction) -> TSRegistrationState {
        return accountStateManager.getOrLoadAccountState(tx: tx).registrationState
    }

    public var storedServerUsernameWithMaybeTransaction: String? {
        return accountStateManager.getOrLoadAccountStateWithMaybeTransaction().serverUsername
    }

    public func storedServerUsername(tx: DBReadTransaction) -> String? {
        return accountStateManager.getOrLoadAccountState(tx: tx).serverUsername
    }

    public var storedServerAuthTokenWithMaybeTransaction: String? {
        return accountStateManager.getOrLoadAccountStateWithMaybeTransaction().serverAuthToken
    }

    public func storedServerAuthToken(tx: DBReadTransaction) -> String? {
        return accountStateManager.getOrLoadAccountState(tx: tx).serverAuthToken
    }

    public var storedDeviceIdWithMaybeTransaction: UInt32 {
        return accountStateManager.getOrLoadAccountStateWithMaybeTransaction().deviceId
    }

    public func storedDeviceId(tx: DBReadTransaction) -> UInt32 {
        return accountStateManager.getOrLoadAccountState(tx: tx).deviceId
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
        accountStateManager.getOrLoadAccountState(tx: tx).isDiscoverableByPhoneNumber
    }

    public func setIsManualMessageFetchEnabled(_ isEnabled: Bool, tx: DBWriteTransaction) {
        accountStateManager.setManualMessageFetchEnabled(isEnabled, tx: tx)
    }

    // MARK: - Phone Number Discoverability

    public func hasDefinedIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool {
        accountStateManager.getOrLoadAccountState(tx: tx).hasDefinedIsDiscoverableByPhoneNumber
    }

    public func isDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool {
        accountStateManager.getOrLoadAccountState(tx: tx).isDiscoverableByPhoneNumber
    }
}

extension TSAccountManagerImpl: PhoneNumberDiscoverabilitySetter {

    public func setIsDiscoverableByPhoneNumber(_ isDiscoverable: Bool, tx: DBWriteTransaction) {
        accountStateManager.setIsDiscoverableByPhoneNumber(isDiscoverable, tx: tx)
    }
}

extension TSAccountManagerImpl: LocalIdentifiersSetter {

    public func setDeviceId(_ deviceId: UInt32, serverAuthToken: String, tx: DBWriteTransaction) {
        accountStateManager.setDeviceId(deviceId, serverAuthToken: serverAuthToken, tx: tx)
    }

    /// The old TSAccountManager expects isOnboarded to be set for registration, not just provisioning.
    /// While bridging between the old and new, set it in the new code. Once the old code is removed
    /// and readers stop expecting the value, delete tmp_setIsOnboarded.
    public func initializeLocalIdentifiers(
        e164: E164,
        aci: Aci,
        pni: Pni?,
        deviceId: UInt32,
        serverAuthToken: String,
        tmp_setIsOnboarded: Bool,
        tx: DBWriteTransaction
    ) {
        accountStateManager.initializeLocalIdentifiers(
            e164: e164,
            aci: aci,
            pni: pni,
            deviceId: deviceId,
            serverAuthToken: serverAuthToken,
            tmp_setIsOnboarded: tmp_setIsOnboarded,
            tx: tx
        )
    }

    public func changeLocalNumber(
        newE164: E164,
        aci: Aci,
        pni: Pni?,
        tx: DBWriteTransaction
    ) {
        accountStateManager.changeLocalNumber(
            newE164: newE164,
            aci: aci,
            pni: pni,
            tx: tx
        )
    }

    public func setDidFinishProvisioning(tx: DBWriteTransaction) {
        accountStateManager.setDidFinishProvisioning(tx: tx)
    }

    public func setIsDeregisteredOrDelinked(_ isDeregisteredOrDelinked: Bool, tx: DBWriteTransaction) -> Bool {
        return accountStateManager.setIsDeregisteredOrDelinked(isDeregisteredOrDelinked, tx: tx)
    }

    public func resetForReregistration(
        localNumber: E164,
        localAci: Aci,
        tx: DBWriteTransaction
    ) {
        return accountStateManager.resetForReRegistration(
            localNumber: localNumber,
            localAci: localAci,
            tx: tx
        )
    }

    public func setIsTransferInProgress(_ isTransferInProgress: Bool, tx: DBWriteTransaction) -> Bool {
        return accountStateManager.setIsTransferInProgress(isTransferInProgress, tx: tx)
    }

    public func setWasTransferred(_ wasTransferred: Bool, tx: DBWriteTransaction) -> Bool {
        return accountStateManager.setWasTransferred(wasTransferred, tx: tx)
    }
}

extension TSAccountManagerImpl: DBChangeDelegate {

    public func dbChangesDidUpdateExternally() {
        self.db.read(block: accountStateManager.reloadAccountState(tx:))
    }
}

extension TSAccountManagerImpl {
    public enum Shims {
        public typealias AppReadiness = _TSAccountManagerImpl_AppReadinessShim
    }

    public enum Wrappers {
        public typealias AppReadiness = _TSAccountManagerImpl_AppReadinessWrapper
    }
}

public protocol _TSAccountManagerImpl_AppReadinessShim {

    var isMainApp: Bool { get }

    func runNowOrWhenAppDidBecomeReadyAsync(_ block: @escaping () -> Void)
}

public class _TSAccountManagerImpl_AppReadinessWrapper: _TSAccountManagerImpl_AppReadinessShim {

    public init() {}

    public var isMainApp: Bool {
        return CurrentAppContext().isMainApp
    }

    public func runNowOrWhenAppDidBecomeReadyAsync(_ block: @escaping () -> Void) {
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync(block)
    }
}
