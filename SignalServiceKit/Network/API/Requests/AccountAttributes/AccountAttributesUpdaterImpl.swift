//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AccountAttributesUpdaterImpl: AccountAttributesUpdater {
    private let accountAttributesGenerator: AccountAttributesGenerator
    private let appReadiness: AppReadiness
    private let appVersion: AppVersion
    private let cronStore: CronStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager
    private let svrLocalStorage: SVRLocalStorage
    private let syncManager: SyncManagerProtocol
    private let tsAccountManager: TSAccountManager

    private enum Constants {
        // We must refresh our registration recovery password periodically. We
        // typically do this when updating to a new version, but we want to refresh
        // it after 14 days if we haven't upgraded.
        static let periodicRefreshInterval: TimeInterval = 14 * .day
    }

    public init(
        accountAttributesGenerator: AccountAttributesGenerator,
        appReadiness: AppReadiness,
        appVersion: AppVersion,
        cron: Cron,
        dateProvider: @escaping DateProvider,
        db: any DB,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        svrLocalStorage: SVRLocalStorage,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountAttributesGenerator = accountAttributesGenerator
        self.appReadiness = appReadiness
        self.appVersion = appVersion
        self.cronStore = CronStore(uniqueKey: .updateAttributes)
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: "AccountAttributesUpdater")
        self.networkManager = networkManager
        self.profileManager = profileManager
        self.svrLocalStorage = svrLocalStorage
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager
        self.registerForCron(cron)
    }

    private func registerForCron(_ cron: Cron) {
        cron.scheduleFrequently(
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { () throws -> Bool in
                let updateConfig = self.db.read { tx -> UpdateConfig? in
                    guard let updateConfig = self.updateConfig(tx: tx) else {
                        return nil
                    }
                    // We update periodically (according to Cron), whenever the capabilities
                    // change (useful during testing or if capabilities are influenced by
                    // RemoteConfig, DB migrations, etc.), and whenever requested explicitly.
                    let shouldUpdate: Bool = (
                        updateConfig.updateRequestToken != nil
                            || Date() >= self.cronStore.mostRecentDate(tx: tx).addingTimeInterval(Constants.periodicRefreshInterval)
                            || updateConfig.capabilities.requestParameters != self.oldCapabilities(tx: tx),
                    )
                    return shouldUpdate ? updateConfig : nil
                }
                guard let updateConfig else {
                    return false
                }
                try await self.updateAccountAttributes(updateConfig: updateConfig, authedAccount: .implicit())
                return true
            },
            handleResult: { result in
                switch result {
                case .failure(is NotRegisteredError), .success(false), .failure(is CancellationError):
                    break
                case .success(true):
                    // Handled by updateAccountAttributes.
                    break
                case .failure(let error):
                    Logger.warn("account attributes hit terminal error; stopping for now: \(error)")
                    await self.db.awaitableWrite(block: self.updateMostRecentDate(tx:))
                }
            },
        )
    }

    private func updateMostRecentDate(tx: DBWriteTransaction) {
        self.cronStore.setMostRecentDate(Date(), jitter: Constants.periodicRefreshInterval / 20, tx: tx)
    }

    public func updateAccountAttributes(authedAccount: AuthedAccount) async throws {
        let updateConfig = await db.awaitableWrite { tx -> UpdateConfig? in
            self.kvStore.setData(
                Randomness.generateRandomBytes(16),
                key: Keys.latestUpdateRequestToken,
                transaction: tx,
            )
            return self.updateConfig(tx: tx)
        }
        guard let updateConfig else {
            return
        }
        try await self.updateAccountAttributes(updateConfig: updateConfig, authedAccount: authedAccount)
    }

    public func scheduleAccountAttributesUpdate(authedAccount: AuthedAccount, tx: DBWriteTransaction) {
        self.kvStore.setData(
            Randomness.generateRandomBytes(16),
            key: Keys.latestUpdateRequestToken,
            transaction: tx,
        )
        let updateConfig = self.updateConfig(tx: tx)
        guard let updateConfig else {
            return
        }
        tx.addSyncCompletion {
            Task {
                try await self.updateAccountAttributes(updateConfig: updateConfig, authedAccount: authedAccount)
            }
        }
    }

    private struct UpdateConfig {
        var registrationState: TSRegistrationState
        var updateRequestToken: Data?
        var capabilities: AccountAttributes.Capabilities
    }

    private func updateConfig(tx: DBReadTransaction) -> UpdateConfig? {
        let registrationState = self.tsAccountManager.registrationState(tx: tx)
        guard registrationState.isRegistered else {
            return nil
        }

        // has non-nil value if isRegistered is true.
        let hasBackedUpMasterKey = self.svrLocalStorage.getIsMasterKeyBackedUp(tx)
        let capabilities = AccountAttributes.Capabilities(hasSVRBackups: hasBackedUpMasterKey)
        let lastAttributeRequestToken = self.kvStore.getData(Keys.latestUpdateRequestToken, transaction: tx)

        return UpdateConfig(
            registrationState: registrationState,
            updateRequestToken: lastAttributeRequestToken,
            capabilities: capabilities,
        )
    }

    private func oldCapabilities(tx: DBReadTransaction) -> [String: NSNumber]? {
        return self.kvStore.getDictionary(
            Keys.lastUpdateDeviceCapabilities,
            keyClass: NSString.self,
            objectClass: NSNumber.self,
            transaction: tx,
        ) as [String: NSNumber]?
    }

    /// Performs a single attempt to update the account attributes.
    ///
    /// This method assumes we have a priori knowledge that an update is
    /// required; callers must check whether or not an update is required.
    private func updateAccountAttributes(updateConfig: UpdateConfig, authedAccount: AuthedAccount) async throws {
        let request: TSRequest
        if updateConfig.registrationState.isPrimaryDevice == true {
            let attributes = try db.read { tx in
                return try accountAttributesGenerator
                    .generateForPrimary(capabilities: updateConfig.capabilities, tx: tx)
            }
            request = AccountAttributesRequestFactory(tsAccountManager: tsAccountManager)
                .updatePrimaryDeviceAttributesRequest(attributes, auth: authedAccount.chatServiceAuth)
        } else {
            request = AccountAttributesRequestFactory(tsAccountManager: tsAccountManager)
                .updateLinkedDeviceCapabilitiesRequest(updateConfig.capabilities, auth: authedAccount.chatServiceAuth)
        }
        _ = try await networkManager.asyncRequest(request)

        await db.awaitableWrite { tx in
            self.updateMostRecentDate(tx: tx)
            self.kvStore.setObject(updateConfig.capabilities.requestParameters, key: Keys.lastUpdateDeviceCapabilities, transaction: tx)
            // Clear the update request unless a new update has been requested
            // while this update was in flight.
            if
                let updateRequestToken = updateConfig.updateRequestToken,
                updateRequestToken == self.kvStore.getData(Keys.latestUpdateRequestToken, transaction: tx)
            {
                self.kvStore.removeValue(forKey: Keys.latestUpdateRequestToken, transaction: tx)
            }
        }

        // Fetch our profile (unclear why), but ignore the result and any errors
        // because this is a best-effort fetch.
        _ = try? await profileManager.fetchLocalUsersProfile(authedAccount: authedAccount)

        // Primary devices should sync their configuration whenever they
        // update their account attributes.
        if updateConfig.registrationState.isRegisteredPrimaryDevice {
            self.syncManager.sendConfigurationSyncMessage()
        }
    }

    private enum Keys {
        static let latestUpdateRequestToken = "latestUpdateRequestDate"
        static let lastUpdateDeviceCapabilities = "lastUpdateDeviceCapabilities"
    }
}
