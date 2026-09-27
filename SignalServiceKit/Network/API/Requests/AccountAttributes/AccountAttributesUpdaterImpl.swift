//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AccountAttributesUpdaterImpl: AccountAttributesUpdater {
    private let accountAttributesGenerator: AccountAttributesGenerator
    private let appReadiness: AppReadiness
    private let cronStore: CronStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: NewKeyValueStore
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager
    private let syncManager: SyncManagerProtocol
    private let tsAccountManager: TSAccountManager
    private let twoFactorManager: OWS2FAManager

    private enum Constants {
        // We must refresh our registration recovery password periodically. We
        // typically do this when updating to a new version, but we want to refresh
        // it after 14 days if we haven't upgraded.
        static let periodicRefreshInterval: TimeInterval = 14 * .day
    }

    init(
        accountAttributesGenerator: AccountAttributesGenerator,
        appReadiness: AppReadiness,
        cron: Cron,
        dateProvider: @escaping DateProvider,
        db: any DB,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager,
        twoFactorManager: OWS2FAManager,
    ) {
        self.accountAttributesGenerator = accountAttributesGenerator
        self.appReadiness = appReadiness
        self.cronStore = CronStore(uniqueKey: .updateAttributes)
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = NewKeyValueStore(collection: "AccountAttributesUpdater")
        self.networkManager = networkManager
        self.profileManager = profileManager
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager
        self.twoFactorManager = twoFactorManager
        self.registerForCron(cron)
    }

    private func registerForCron(_ cron: Cron) {
        cron.scheduleFrequently(
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { () throws -> Bool in
                return try await self.updateAccountAttributesIfNeeded(authedAccount: .implicit)
            },
            handleResult: { result in
                switch result {
                case .success(false), .failure(is CancellationError):
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

    private let updateQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    private func updateAccountAttributesIfNeeded(authedAccount: AuthedAccount) async throws -> Bool {
        return try await updateQueue.runWithThrowingTask {
            return try await _updateAccountAttributesIfNeeded(authedAccount: authedAccount)
        }
    }

    private func _updateAccountAttributesIfNeeded(authedAccount: AuthedAccount) async throws -> Bool {
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
                    || updateConfig.capabilities != self.oldCapabilities(tx: tx),
            )
            return shouldUpdate ? updateConfig : nil
        }
        guard let updateConfig else {
            return false
        }
        try await self.updateAccountAttributes(updateConfig: updateConfig, authedAccount: authedAccount)
        return true
    }

    private func updateMostRecentDate(tx: DBWriteTransaction) {
        self.cronStore.setMostRecentDate(Date(), jitter: Constants.periodicRefreshInterval / 20, tx: tx)
    }

    @discardableResult
    public func scheduleAccountAttributesUpdate(authedAccount: AuthedAccount, tx: DBWriteTransaction) -> Task<Void, any Error> {
        self.kvStore.writeValue(
            Randomness.generateRandomBytes(16),
            forKey: Keys.latestUpdateRequestToken,
            tx: tx,
        )
        let txCompletion = CancellableContinuation<Void>()
        tx.addSyncCompletion { txCompletion.resume(with: .success(())) }
        return Task {
            try await txCompletion.wait()
            _ = try await self.updateAccountAttributesIfNeeded(authedAccount: authedAccount)
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
        let hasBackedUpMasterKey = self.twoFactorManager.shouldMasterKeyBeBackedUp(tx: tx)
        let capabilities = AccountAttributes.Capabilities(hasSVRBackups: hasBackedUpMasterKey)
        let lastAttributeRequestToken = self.kvStore.fetchValue(Data.self, forKey: Keys.latestUpdateRequestToken, tx: tx)

        return UpdateConfig(
            registrationState: registrationState,
            updateRequestToken: lastAttributeRequestToken,
            capabilities: capabilities,
        )
    }

    private func oldCapabilities(tx: DBReadTransaction) -> AccountAttributes.Capabilities? {
        let encodedCapabilities = self.kvStore.fetchValue(
            Data.self,
            forKey: Keys.lastUpdateDeviceCapabilities,
            tx: tx,
        )
        guard let encodedCapabilities else {
            return nil
        }
        do {
            return try JSONDecoder().decode(AccountAttributes.Capabilities.self, from: encodedCapabilities)
        } catch {
            // Expected when upgrading or downgrading... (we want to refresh because
            // they're definitely different if we can't decode them)
            return nil
        }
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
            self.kvStore.writeValue(
                failIfThrows { try JSONEncoder().encode(updateConfig.capabilities) },
                forKey: Keys.lastUpdateDeviceCapabilities,
                tx: tx,
            )
            // Clear the update request unless a new update has been requested
            // while this update was in flight.
            if
                let updateRequestToken = updateConfig.updateRequestToken,
                updateRequestToken == self.kvStore.fetchValue(Data.self, forKey: Keys.latestUpdateRequestToken, tx: tx)
            {
                self.kvStore.removeValue(forKey: Keys.latestUpdateRequestToken, tx: tx)
            }
        }

        // Best-effort fetch our own profile, in case we now have new
        // account-level capabilities (which we discover from our profile) as a
        // result of our account attributes update (which includes device-level
        // capabilities).
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
