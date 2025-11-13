//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AccountAttributesUpdaterImpl: AccountAttributesUpdater {
    private let accountAttributesGenerator: AccountAttributesGenerator
    private let appReadiness: AppReadiness
    private let appVersion: AppVersion
    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager
    private let svrLocalStorage: SVRLocalStorage
    private let syncManager: SyncManagerProtocol
    private let tsAccountManager: TSAccountManager

    public init(
        accountAttributesGenerator: AccountAttributesGenerator,
        appReadiness: AppReadiness,
        appVersion: AppVersion,
        dateProvider: @escaping DateProvider,
        db: any DB,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        svrLocalStorage: SVRLocalStorage,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager
    ) {
        self.accountAttributesGenerator = accountAttributesGenerator
        self.appReadiness = appReadiness
        self.appVersion = appVersion
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: "AccountAttributesUpdater")
        self.networkManager = networkManager
        self.profileManager = profileManager
        self.svrLocalStorage = svrLocalStorage
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task {
                try await self.updateAccountAttributesIfNecessaryAttempt(authedAccount: .implicit())
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabilityDidChange),
            name: .reachabilityChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func reachabilityDidChange() {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task {
                try await self.updateAccountAttributesIfNecessaryAttempt(authedAccount: .implicit())
            }
        }
    }

    public func updateAccountAttributes(authedAccount: AuthedAccount) async throws {
        await db.awaitableWrite { tx in
            self.kvStore.setData(
                Randomness.generateRandomBytes(16),
                key: Keys.latestUpdateRequestToken,
                transaction: tx,
            )
        }
        try await self.updateAccountAttributesIfNecessaryAttempt(authedAccount: authedAccount)
    }

    public func scheduleAccountAttributesUpdate(authedAccount: AuthedAccount, tx: DBWriteTransaction) {
        self.kvStore.setData(
            Randomness.generateRandomBytes(16),
            key: Keys.latestUpdateRequestToken,
            transaction: tx,
        )
        tx.addSyncCompletion {
            Task {
                try await self.updateAccountAttributesIfNecessaryAttempt(authedAccount: authedAccount)
            }
        }
    }

    // Performs a single attempt to update the account attributes.
    //
    // We need to update our account attributes in a variety of scenarios:
    //
    // * Every time the user upgrades to a new version.
    // * Whenever the device capabilities change.
    //   This is useful during development and internal testing when
    //   moving between builds with different device capabilities.
    // * Whenever another component of the system requests an attribute,
    //   update e.g. during registration, after rotating the profile key, etc.
    //
    // The client will retry failed attempts:
    //
    // * On launch.
    // * When reachability changes.
    private func updateAccountAttributesIfNecessaryAttempt(authedAccount: AuthedAccount) async throws {
        guard appReadiness.isAppReady else {
            Logger.info("Aborting; app is not ready.")
            return
        }

        let currentAppVersion = appVersion.currentAppVersion

        enum ShouldUpdate {
            case no
            case yes(
                currentDeviceCapabilities: AccountAttributes.Capabilities,
                lastAttributeRequestToken: Data?,
                registrationState: TSRegistrationState,
                aciRegistrationId: UInt32,
                pniRegistrationId: UInt32
            )
        }

        let shouldUpdate = db.read { tx -> ShouldUpdate in
            let registrationState = self.tsAccountManager.registrationState(tx: tx)
            let isRegistered = registrationState.isRegistered
            let aciRegistrationId = self.tsAccountManager.getRegistrationId(for: .aci, tx: tx)
            let pniRegistrationId = self.tsAccountManager.getRegistrationId(for: .pni, tx: tx)

            guard
                isRegistered,
                let aciRegistrationId,
                let pniRegistrationId
            else {
                return .no
            }

            // has non-nil value if isRegistered is true.
            let hasBackedUpMasterKey = self.svrLocalStorage.getIsMasterKeyBackedUp(tx)
            let currentDeviceCapabilities = AccountAttributes.Capabilities(hasSVRBackups: hasBackedUpMasterKey)

            // Check if there's been a request for an attributes update.
            let lastAttributeRequestToken = self.kvStore.getData(Keys.latestUpdateRequestToken, transaction: tx)
            if lastAttributeRequestToken != nil {
                return .yes(
                    currentDeviceCapabilities: currentDeviceCapabilities,
                    lastAttributeRequestToken: lastAttributeRequestToken,
                    registrationState: registrationState,
                    aciRegistrationId: aciRegistrationId,
                    pniRegistrationId: pniRegistrationId
                )
            }

            // Check if device capabilities have changed.
            let lastUpdateDeviceCapabilities = self.kvStore.getDictionary(
                Keys.lastUpdateDeviceCapabilities,
                keyClass: NSString.self,
                objectClass: NSNumber.self,
                transaction: tx
            ) as [String: NSNumber]?
            if lastUpdateDeviceCapabilities != currentDeviceCapabilities.requestParameters {
                return .yes(
                    currentDeviceCapabilities: currentDeviceCapabilities,
                    lastAttributeRequestToken: lastAttributeRequestToken,
                    registrationState: registrationState,
                    aciRegistrationId: aciRegistrationId,
                    pniRegistrationId: pniRegistrationId
                )
            }
            // Check if the app version has changed.
            let lastUpdateAppVersion = self.kvStore.getString(Keys.lastUpdateAppVersion, transaction: tx)
            if lastUpdateAppVersion != currentAppVersion {
                return .yes(
                    currentDeviceCapabilities: currentDeviceCapabilities,
                    lastAttributeRequestToken: lastAttributeRequestToken,
                    registrationState: registrationState,
                    aciRegistrationId: aciRegistrationId,
                    pniRegistrationId: pniRegistrationId
                )
            }
            return .no
        }
        switch shouldUpdate {
        case .no:
            return
        case let .yes(
            currentDeviceCapabilities,
            lastAttributeRequestToken,
            registrationState,
            aciRegistrationId,
            pniRegistrationId
        ):
            Logger.info("Updating account attributes.")
            let reportedDeviceCapabilities: AccountAttributes.Capabilities
            if registrationState.isPrimaryDevice == true {
                let attributes = db.read { tx in
                    accountAttributesGenerator.generateForPrimary(
                        aciRegistrationId: aciRegistrationId,
                        pniRegistrationId: pniRegistrationId,
                        tx: tx
                    )
                }

                let request = AccountAttributesRequestFactory(
                    tsAccountManager: tsAccountManager
                ).updatePrimaryDeviceAttributesRequest(
                    attributes,
                    auth: authedAccount.chatServiceAuth
                )
                _ = try await networkManager.asyncRequest(request)

                reportedDeviceCapabilities = attributes.capabilities
            } else {
                let request = AccountAttributesRequestFactory(
                    tsAccountManager: tsAccountManager
                ).updateLinkedDeviceCapabilitiesRequest(
                    currentDeviceCapabilities,
                    auth: authedAccount.chatServiceAuth
                )
                _ = try await networkManager.asyncRequest(request)

                reportedDeviceCapabilities = currentDeviceCapabilities
            }

            // Kick off an async profile fetch (not awaited)
            Task {
                _ = try await profileManager.fetchLocalUsersProfile(authedAccount: authedAccount)
            }

            await db.awaitableWrite { tx in
                self.kvStore.setString(currentAppVersion, key: Keys.lastUpdateAppVersion, transaction: tx)
                self.kvStore.setObject(reportedDeviceCapabilities.requestParameters, key: Keys.lastUpdateDeviceCapabilities, transaction: tx)
                // Clear the update request unless a new update has been requested
                // while this update was in flight.
                if
                    let lastAttributeRequestToken,
                    lastAttributeRequestToken == self.kvStore.getData(Keys.latestUpdateRequestToken, transaction: tx)
                {
                    self.kvStore.removeValue(forKey: Keys.latestUpdateRequestToken, transaction: tx)
                }
            }

            // Primary devices should sync their configuration whenever they
            // update their account attributes.
            if registrationState.isRegisteredPrimaryDevice {
                self.syncManager.sendConfigurationSyncMessage()
            }
        }
    }

    private enum Keys {
        static let latestUpdateRequestToken = "latestUpdateRequestDate"
        static let lastUpdateDeviceCapabilities = "lastUpdateDeviceCapabilities"
        static let lastUpdateAppVersion = "lastUpdateAppVersion"
    }
}
