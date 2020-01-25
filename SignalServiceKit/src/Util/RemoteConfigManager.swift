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
        return isEnabled("ios.pinsForEveryone")
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
    }

    // MARK: -

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
        }.done(on: .global()) { remoteConfig in
            self.databaseStorage.write { transaction in
                self.keyValueStore.setRemoteConfig(remoteConfig, transaction: transaction)
                self.keyValueStore.setLastFetched(Date(), transaction: transaction)
            }
            Logger.info("stored new remoteConfig: \(remoteConfig)")
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
