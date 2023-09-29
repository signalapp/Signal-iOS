//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class TSAccountManagerImpl: TSAccountManagerProtocol {

    private let dateProvider: DateProvider
    private let db: DB
    private let schedulers: Schedulers

    private let accountStateManager: AccountStateManager
    private let kvStore: KeyValueStore

    public init(
        dateProvider: @escaping DateProvider,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        schedulers: Schedulers
    ) {
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

    public func initializeLocalIdentifiers(
        e164: E164,
        aci: Aci,
        pni: Pni?,
        deviceId: UInt32,
        serverAuthToken: String,
        tx: DBWriteTransaction
    ) {
        accountStateManager.initializeLocalIdentifiers(
            e164: e164,
            aci: aci,
            pni: pni,
            deviceId: deviceId,
            serverAuthToken: serverAuthToken,
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
