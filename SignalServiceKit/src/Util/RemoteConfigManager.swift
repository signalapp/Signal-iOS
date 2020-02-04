//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class RemoteConfig: NSObject {

    init(_ config: [String: Bool]) {
        self.config = config
    }

    // rather than interact with `config` directly, prefer encoding any string constants
    // into a getter below...
    private let config: [String: Bool]

    @objc
    public static var pinsForEveryone: Bool {
        // If we've turned off the KBS feature we don't want to present the
        // pins for everyone migration even if this user is in the bucket.
        guard kbs else { return false }
        return isEnabled("ios.pinsForEveryone")
    }

    @objc
    public static var profileNameReminder: Bool {
        return isEnabled("ios.profileNameReminder")
    }

    @objc
    public static var kbs: Bool {
        // This feature latches "on" – once they have a master key in KBS,
        // even if we turn it off on the server they will keep using KBS.
        guard !KeyBackupService.hasMasterKey else { return true }
        // For now, KBS does not work for censorship circumvention users.
        guard !OWSSignalService.sharedInstance().isCensorshipCircumventionActive else { return false }
        return isEnabled("ios.kbs")
    }

    @objc
    public static var groupsV2CreateGroups: Bool {
        guard FeatureFlags.groupsV2CreateGroups else { return false }
        if FeatureFlags.groupsV2IgnoreServerFlags { return true }
        return isEnabled("ios.groupsV2CreateGroups")
    }

    @objc
    public static var groupsV2IncomingMessages: Bool {
        guard FeatureFlags.groupsV2IncomingMessages else { return false }
        if FeatureFlags.groupsV2IgnoreServerFlags { return true }
        return isEnabled("ios.groupsV2IncomingMessages")
    }

    private static func isEnabled(_ key: String, defaultValue: Bool = false) -> Bool {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        return remoteConfig.config[key] ?? defaultValue
    }
}

@objc
public protocol RemoteConfigManager: AnyObject {
    var cachedConfig: RemoteConfig? { get }
}

@objc
public class StubbableRemoteConfigManager: NSObject, RemoteConfigManager {
    public var cachedConfig: RemoteConfig?
}

@objc
public class ServiceRemoteConfigManager: NSObject, RemoteConfigManager {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    private let serviceClient: SignalServiceClient = SignalServiceRestClient()

    let keyValueStore: SDSKeyValueStore = SDSKeyValueStore(collection: "RemoteConfigManager")

    // MARK: -

    // Values defined in this array remain forever true once they are
    // marked true regardless of the remote state.
    private let stickyFlags = [
        "ios.pinsForEveryone"
    ]

    @objc
    public private(set) var cachedConfig: RemoteConfig?

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.cacheCurrent()
        }

        // The fetched config won't take effect until the *next* launch.
        // That's not ideal, but we can't risk changing configs in the middle
        // of an app lifetime.
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            guard self.tsAccountManager.isRegistered else {
                return
            }
            self.refreshIfReady()
        }

        // Listen for registration state changes so we can fetch the config
        // when the user registers. This will still not take effect until
        // the *next* launch, but we'll have it ready to apply at that point.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )
    }

    // MARK: -

    @objc func registrationStateDidChange() {
        guard self.tsAccountManager.isRegistered else { return }
        self.refreshIfReady()
    }

    private func cacheCurrent() {
        AssertIsOnMainThread()

        // set only once
        assert(self.cachedConfig == nil)

        if let storedConfig = self.databaseStorage.read(block: { transaction in
            self.keyValueStore.getRemoteConfig(transaction: transaction)
        }) {
            Logger.info("loaded stored config: \(storedConfig)")
            self.cachedConfig = RemoteConfig(storedConfig)
        } else {
            Logger.info("no stored remote config")
        }
    }

    private func refreshIfReady() {
        guard let lastFetched = (databaseStorage.read { transaction in
            self.keyValueStore.getLastFetched(transaction: transaction)
        }) else {
            refresh()
            return
        }

        if abs(lastFetched.timeIntervalSinceNow) > 2 * kHourInterval {
            refresh()
        } else {
            Logger.info("skipping due to recent fetch.")
        }
    }

    private func refresh() {
        return firstly {
            self.serviceClient.getRemoteConfig()
        }.done(on: .global()) { fetchedConfig in
            var configToStore = fetchedConfig
            self.databaseStorage.write { transaction in
                // Update fetched config to reflect any sticky flags.
                if let existingConfig = self.keyValueStore.getRemoteConfig(transaction: transaction) {
                    existingConfig.lazy.filter { self.stickyFlags.contains($0.key) }.forEach {
                        configToStore[$0.key] = $0.value || (fetchedConfig[$0.key] ?? false)
                    }
                }

                self.keyValueStore.setRemoteConfig(configToStore, transaction: transaction)
                self.keyValueStore.setLastFetched(Date(), transaction: transaction)
            }
            Logger.info("stored new remoteConfig: \(configToStore)")
        }.catch { error in
            Logger.error("error: \(error)")
        }.retainUntilComplete()
    }
}

private extension SDSKeyValueStore {

    // MARK: - Remote Config

    var remoteConfigKey: String { "remoteConfigKey" }

    func getRemoteConfig(transaction: SDSAnyReadTransaction) -> [String: Bool]? {
        guard let object = getObject(remoteConfigKey, transaction: transaction) else {
            return nil
        }

        guard let remoteConfig = object as? [String: Bool] else {
            owsFailDebug("unexpected object: \(object)")
            return nil
        }

        return remoteConfig
    }

    func setRemoteConfig(_ newValue: [String: Bool], transaction: SDSAnyWriteTransaction) {
        return setObject(newValue, key: remoteConfigKey, transaction: transaction)
    }

    // MARK: - Last Fetched

    var lastFetchedKey: String { "lastFetchedKey" }

    func getLastFetched(transaction: SDSAnyReadTransaction) -> Date? {
        return getDate(lastFetchedKey, transaction: transaction)
    }

    func setLastFetched(_ newValue: Date, transaction: SDSAnyWriteTransaction) {
        return setDate(newValue, key: lastFetchedKey, transaction: transaction)
    }
}
