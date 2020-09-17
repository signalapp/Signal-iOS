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

    // MARK: - Account Attributes & Capabilities

    private static let needsAccountAttributesUpdateKey = "TSAccountManager_NeedsAccountAttributesUpdateKey"

    // Sets the flag to force an account attributes update,
    // then returns a promise for the current attempt.
    @objc
    func updateAccountAttributes() -> AnyPromise {
        Self.databaseStorage.write { transaction in
            self.keyValueStore.setDate(Date(),
                                       key: Self.needsAccountAttributesUpdateKey,
                                       transaction: transaction)
        }
        return AnyPromise(updateAccountAttributesIfNecessaryAttempt())
    }

    @objc
    func updateAccountAttributesIfNecessary() {
        firstly {
            updateAccountAttributesIfNecessaryAttempt()
        }.done(on: DispatchQueue.global()) { _ in
            Logger.info("Success.")
        }.catch(on: DispatchQueue.global()) { error in
            Logger.warn("Error: \(error).")
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
    private func updateAccountAttributesIfNecessaryAttempt() -> Promise<Void> {
        guard isRegisteredAndReady else {
            Logger.info("Aborting; not registered and ready.")
            return Promise.value(())
        }
        guard AppReadiness.isAppReady else {
            Logger.info("Aborting; app is not ready.")
            return Promise.value(())
        }

        let deviceCapabilitiesKey = "deviceCapabilities"
        let appVersionKey = "appVersion"

        let currentDeviceCapabilities: [String: NSNumber] = OWSRequestFactory.deviceCapabilitiesForLocalDevice()
        let currentAppVersion = AppVersion.shared().currentAppVersionLong

        var lastAttributeRequest: Date?
        let shouldUpdateAttributes = Self.databaseStorage.read { (transaction: SDSAnyReadTransaction) -> Bool in
            // Check if there's been a request for an attributes update.
            lastAttributeRequest = self.keyValueStore.getDate(Self.needsAccountAttributesUpdateKey,
                                                              transaction: transaction)
            if lastAttributeRequest != nil {
                return true
            }
            // Check if device capabilities have changed.
            let lastDeviceCapabilities = self.keyValueStore.getObject(forKey: deviceCapabilitiesKey,
                                                                      transaction: transaction) as? [String: NSNumber]
            guard lastDeviceCapabilities == currentDeviceCapabilities else {
                return true
            }
            // Check if the app version has changed.
            let lastAppVersion = self.keyValueStore.getString(appVersionKey, transaction: transaction)
            guard lastAppVersion == currentAppVersion else {
                return true
            }
            Logger.info("Skipping; lastAppVersion: \(String(describing: lastAppVersion)), currentAppVersion: \(currentAppVersion).")
            return false
        }
        guard shouldUpdateAttributes else {
            return Promise.value(())
        }
        Logger.info("Updating account attributes.")
        let promise: Promise<Void> = firstly(on: .global()) { () -> Promise<Void> in
            let client = SignalServiceRestClient()
            return (self.isPrimaryDevice
                ? client.updatePrimaryDeviceAccountAttributes()
                : client.updateSecondaryDeviceCapabilities())
        }.then(on: DispatchQueue.global()) {
            self.profileManager.fetchLocalUsersProfilePromise()
        }.map(on: DispatchQueue.global()) { _ -> Void in
            Self.databaseStorage.write { transaction in
                self.keyValueStore.setObject(currentDeviceCapabilities, key: deviceCapabilitiesKey,
                                             transaction: transaction)
                self.keyValueStore.setString(currentAppVersion, key: appVersionKey,
                                             transaction: transaction)

                // Clear the update request unless a new update has been requested
                // while this update was in flight.
                if lastAttributeRequest != nil,
                    lastAttributeRequest == self.keyValueStore.getDate(Self.needsAccountAttributesUpdateKey,
                                                                       transaction: transaction) {
                    self.keyValueStore.removeValue(forKey: Self.needsAccountAttributesUpdateKey,
                                                   transaction: transaction)
                }
            }

            // Primary devices should sync their configuration whenever they
            // update their account attributes.
            if self.isRegisteredPrimaryDevice {
                self.syncManager.sendConfigurationSyncMessage()
            }
        }
        return promise
    }
}
