//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AccountAttributesUpdaterImpl: AccountAttributesUpdater {

    private let appReadiness: Shims.AppReadiness
    private let appVersion: AppVersion
    private let dateProvider: DateProvider
    private let db: DB
    private let profileManager: ProfileManager
    private let serviceClient: SignalServiceClient
    private let schedulers: Schedulers
    private let svrLocalStorage: SVRLocalStorage
    private let syncManager: SyncManagerProtocol
    private let tsAccountManager: TSAccountManager

    private let kvStore: KeyValueStore

    public init(
        appReadiness: Shims.AppReadiness,
        appVersion: AppVersion,
        dateProvider: @escaping DateProvider,
        db: DB,
        profileManager: ProfileManager,
        keyValueStoreFactory: KeyValueStoreFactory,
        serviceClient: SignalServiceClient,
        schedulers: Schedulers,
        svrLocalStorage: SVRLocalStorage,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager
    ) {
        self.appReadiness = appReadiness
        self.appVersion = appVersion
        self.dateProvider = dateProvider
        self.db = db
        self.profileManager = profileManager
        self.serviceClient = serviceClient
        self.schedulers = schedulers
        self.svrLocalStorage = svrLocalStorage
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager

        self.kvStore = keyValueStoreFactory.keyValueStore(collection: "AccountAttributesUpdater")

        appReadiness.runNowOrWhenAppBecomesReadyAsync {
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
        appReadiness.runNowOrWhenAppBecomesReadyAsync {
            Task {
                try await self.updateAccountAttributesIfNecessaryAttempt(authedAccount: .implicit())
            }
        }
    }

    public func updateAccountAttributes(authedAccount: AuthedAccount) async throws {
        await db.awaitableWrite { tx in
            self.kvStore.setDate(self.dateProvider(), key: Keys.latestUpdateRequestDate, transaction: tx)
        }
        try await self.updateAccountAttributesIfNecessaryAttempt(authedAccount: authedAccount)
    }

    public func scheduleAccountAttributesUpdate(authedAccount: AuthedAccount, tx: DBWriteTransaction) {
        self.kvStore.setDate(self.dateProvider(), key: Keys.latestUpdateRequestDate, transaction: tx)
        tx.addAsyncCompletion(on: schedulers.global()) {
            Task {
                try? await self.updateAccountAttributesIfNecessaryAttempt(authedAccount: authedAccount)
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
        guard appReadiness.isAppReady() else {
            Logger.info("Aborting; app is not ready.")
            return
        }

        let currentAppVersion4 = appVersion.currentAppVersion4

        enum ShouldUpdate {
            case no
            case yes(
                currentDeviceCapabilities: AccountAttributes.Capabilities,
                lastAttributeRequestDate: Date?,
                registrationState: TSRegistrationState
            )
        }

        let shouldUpdate = db.read { tx -> ShouldUpdate in
            let registrationState = self.tsAccountManager.registrationState(tx: tx)
            let isRegistered = registrationState.isRegistered

            guard isRegistered else {
                Logger.info("Aborting; not registered.")
                return .no
            }

            // has non-nil value if isRegistered is true.
            let hasBackedUpMasterKey = self.svrLocalStorage.getIsMasterKeyBackedUp(tx)
            let currentDeviceCapabilities = AccountAttributes.Capabilities(hasSVRBackups: hasBackedUpMasterKey)

            // Check if there's been a request for an attributes update.
            let lastAttributeRequestDate = self.kvStore.getDate(Keys.latestUpdateRequestDate, transaction: tx)
            if lastAttributeRequestDate != nil {
                return .yes(
                    currentDeviceCapabilities: currentDeviceCapabilities,
                    lastAttributeRequestDate: lastAttributeRequestDate,
                    registrationState: registrationState
                )
            }

            // Check if device capabilities have changed.
            let lastUpdateDeviceCapabilities = self.kvStore.getObject(
                forKey: Keys.lastUpdateDeviceCapabilities,
                transaction: tx
            ) as? [String: NSNumber]
            if lastUpdateDeviceCapabilities != currentDeviceCapabilities.requestParameters {
                return .yes(
                    currentDeviceCapabilities: currentDeviceCapabilities,
                    lastAttributeRequestDate: lastAttributeRequestDate,
                    registrationState: registrationState
                )
            }
            // Check if the app version has changed.
            let lastUpdateAppVersion = self.kvStore.getString(Keys.lastUpdateAppVersion, transaction: tx)
            if lastUpdateAppVersion != currentAppVersion4 {
                return .yes(
                    currentDeviceCapabilities: currentDeviceCapabilities,
                    lastAttributeRequestDate: lastAttributeRequestDate,
                    registrationState: registrationState
                )
            }
            Logger.info("Skipping; lastAppVersion: \(String(describing: lastUpdateAppVersion)), currentAppVersion4: \(currentAppVersion4).")
            return .no
        }
        switch shouldUpdate {
        case .no:
            return
        case let .yes(currentDeviceCapabilities, lastAttributeRequestDate, registrationState):
            Logger.info("Updating account attributes.")
            let reportedDeviceCapabilities: AccountAttributes.Capabilities
            if registrationState.isPrimaryDevice == true {
                let attributes = try await serviceClient.updatePrimaryDeviceAccountAttributes(authedAccount: authedAccount)
                reportedDeviceCapabilities = attributes.capabilities
            } else {
                try await serviceClient.updateSecondaryDeviceCapabilities(currentDeviceCapabilities, authedAccount: authedAccount)
                reportedDeviceCapabilities = currentDeviceCapabilities
            }

            // Kick off an async profile fetch (not awaited)
            _ = profileManager.fetchLocalUsersProfile(mainAppOnly: true, authedAccount: authedAccount)

            await db.awaitableWrite { tx in
                self.kvStore.setString(currentAppVersion4, key: Keys.lastUpdateAppVersion, transaction: tx)
                self.kvStore.setObject(reportedDeviceCapabilities.requestParameters, key: Keys.lastUpdateDeviceCapabilities, transaction: tx)
                // Clear the update request unless a new update has been requested
                // while this update was in flight.
                if
                    let lastAttributeRequestDate,
                    lastAttributeRequestDate == self.kvStore.getDate(Keys.latestUpdateRequestDate, transaction: tx)
                {
                    self.kvStore.removeValue(forKey: Keys.latestUpdateRequestDate, transaction: tx)
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
        static let latestUpdateRequestDate = "latestUpdateRequestDate"
        static let lastUpdateDeviceCapabilities = "lastUpdateDeviceCapabilities"
        static let lastUpdateAppVersion = "lastUpdateAppVersion"

    }
}

extension AccountAttributesUpdaterImpl {
    public enum Shims {
        public typealias AppReadiness = _AccountAttributesUpdater_AppReadinessShim
    }

    public enum Wrappers {
        public typealias AppReadiness = _AccountAttributesUpdater_AppReadinessWrapper
    }
}

public protocol _AccountAttributesUpdater_AppReadinessShim {

    func isAppReady() -> Bool

    func runNowOrWhenAppBecomesReadyAsync(_ block: @escaping () -> Void)
}

public class _AccountAttributesUpdater_AppReadinessWrapper: _AccountAttributesUpdater_AppReadinessShim {

    public init() {}

    public func isAppReady() -> Bool {
        return AppReadiness.isAppReady
    }

    public func runNowOrWhenAppBecomesReadyAsync(_ block: @escaping () -> Void) {
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync(block)
    }
}
