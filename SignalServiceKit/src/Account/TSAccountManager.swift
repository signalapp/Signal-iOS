//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension TSAccountManager {

    // MARK: - Dependencies

    class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    private var syncManager: SyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    // MARK: -

    @objc
    private class func getLocalThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        guard let localAddress = self.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getWithContactAddress(localAddress, transaction: transaction)
    }

    @objc
    private class func getLocalThreadWithSneakyTransaction() -> TSThread? {
        return databaseStorage.read { transaction in
            return getLocalThread(transaction: transaction)
        }
    }

    @objc
    class func getOrCreateLocalThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        guard let localAddress = self.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    @objc
    class func getOrCreateLocalThreadWithSneakyTransaction() -> TSThread? {
        assert(!Thread.isMainThread)

        if let thread = getLocalThreadWithSneakyTransaction() {
            return thread
        }

        return databaseStorage.write { transaction in
            return getOrCreateLocalThread(transaction: transaction)
        }
    }

    @objc
    var isRegisteredPrimaryDevice: Bool {
        return isRegistered && self.storedDeviceId() == OWSDevicePrimaryDeviceId
    }

    @objc
    var isPrimaryDevice: Bool {
        return storedDeviceId() == OWSDevicePrimaryDeviceId
    }

    @objc
    var storedServerUsername: String? {
        guard let serviceIdentifier = self.localAddress?.serviceIdentifier else {
            return nil
        }

        return isRegisteredPrimaryDevice ? serviceIdentifier : "\(serviceIdentifier).\(storedDeviceId())"
    }

    @objc
    func localAccountId(transaction: SDSAnyReadTransaction) -> AccountId? {
        guard let localAddress = localAddress else { return nil }
        return OWSAccountIdFinder().accountId(forAddress: localAddress, transaction: transaction)
    }

    @objc(performUpdateAccountAttributes)
    func objc_performUpdateAccountAttributes() -> AnyPromise {
        return AnyPromise(performUpdateAccountAttributes())
    }

    func performUpdateAccountAttributes() -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            guard isRegisteredPrimaryDevice else {
                throw OWSAssertionError("only update account attributes on primary")
            }

            return SignalServiceRestClient().updatePrimaryDeviceAccountAttributes()
        }.done {
            // Fetch the local profile, as we may have changed its
            // account attributes.  Specifically, we need to determine
            // if all devices for our account now support UD for sync
            // messages.
            self.profileManager.fetchAndUpdateLocalUsersProfile()
        }
    }

    private static let accountStore = SDSKeyValueStore(collection: "TSAccountManager.accountStore")

    // Every time the user upgrades to a new version:
    //
    // * Update account attributes.
    // * Sync configuration to linked devices.
    //
    // We also do this work whenever the device capabilities change.
    // This is useful during development and internal testing when
    // moving between builds with different device capabilities.
    @objc
    func ensureAccountAttributes() {
        guard isRegisteredAndReady else {
            return
        }
        guard AppReadiness.isAppReady() else {
            owsFailDebug("App is not ready.")
            return
        }

        let deviceCapabilitiesKey = "deviceCapabilities"
        let appVersionKey = "appVersion"

        let currentDeviceCapabilities: [String: NSNumber] = OWSRequestFactory.deviceCapabilities()
        let currentAppVersion = AppVersion.sharedInstance().currentAppVersion

        let shouldUpdateAttributes = Self.databaseStorage.read { (transaction: SDSAnyReadTransaction) -> Bool in
            let lastDeviceCapabilities = Self.accountStore.getObject(forKey: deviceCapabilitiesKey, transaction: transaction) as? [String: NSNumber]
            guard lastDeviceCapabilities == currentDeviceCapabilities else {
                return true
            }
            let lastAppVersion = Self.accountStore.getString(appVersionKey, transaction: transaction)
            guard lastAppVersion == currentAppVersion else {
                return true
            }
            return false
        }
        guard shouldUpdateAttributes else {
            return
        }
        Logger.info("Updating account attributes.")
        firstly { () -> Promise<Void> in
            let client = SignalServiceRestClient()
            return (self.isPrimaryDevice
                ? client.updatePrimaryDeviceAccountAttributes()
                : client.updateDeviceCapabilities())
        }.then(on: DispatchQueue.global()) {
            self.profileManager.fetchLocalUsersProfilePromise()
        }.done(on: DispatchQueue.global()) { _ in
            Logger.info("Success.")
            Self.databaseStorage.write { transaction in
                Self.accountStore.setObject(currentDeviceCapabilities, key: deviceCapabilitiesKey, transaction: transaction)
                Self.accountStore.setString(currentAppVersion, key: appVersionKey, transaction: transaction)
            }
            self.syncManager.sendConfigurationSyncMessage()
        }.catch(on: DispatchQueue.global()) { error in
            Logger.warn("Error: \(error).")
        }.retainUntilComplete()
    }
}
