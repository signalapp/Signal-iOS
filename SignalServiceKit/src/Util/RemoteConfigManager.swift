//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class RemoteConfig: BaseFlags {

    init(_ config: [String: Bool]) {
        self.config = config
    }

    // rather than interact with `config` directly, prefer encoding any string constants
    // into a getter below...
    private let config: [String: Bool]

    @objc
    public static var kbs: Bool {
        // This feature latches "on" – once they have a master key in KBS,
        // even if we turn it off on the server they will keep using KBS.
        guard !KeyBackupService.hasMasterKey else { return true }
        return isEnabled(.kbs)
    }

    @objc
    public static var groupsV2CreateGroups: Bool {
        guard FeatureFlags.groupsV2CreateGroups else { return false }
        if DebugFlags.groupsV2IgnoreServerFlags { return true }
        return isEnabled(.groupsV2GoodCitizen)
    }

    @objc
    public static var groupsV2GoodCitizen: Bool {
        if groupsV2CreateGroups {
            return true
        }
        guard FeatureFlags.groupsV2GoodCitizen else { return false }
        if DebugFlags.groupsV2IgnoreServerFlags { return true }
        return isEnabled(.groupsV2GoodCitizen)
    }

    @objc
    public static var groupsV2SetCapability: Bool {
        guard FeatureFlags.groupsV2SetCapability else { return false }
        if DebugFlags.groupsV2IgnoreServerFlags { return true }
        return isEnabled(.groupsV2GoodCitizen)
    }

    @objc
    public static var deleteForEveryone: Bool { isEnabled(.deleteForEveryone) }

    @objc
    public static var versionedProfileFetches: Bool {
        if DebugFlags.forceVersionedProfiles { return true }
        return isEnabled(.versionedProfiles)
    }

    @objc
    public static var versionedProfileUpdate: Bool {
        if DebugFlags.forceVersionedProfiles { return true }
        return isEnabled(.versionedProfiles)
    }

    private static func isEnabled(_ flag: Flags.Supported, defaultValue: Bool = false) -> Bool {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        return remoteConfig.config[flag.rawFlag] ?? defaultValue
    }

    @objc
    public static func logFlags() {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else {
            Logger.info("No cached config.")
            return
        }

        let logFlag = { (prefix: String, key: String, value: Any?) in
            if let value = value {
                Logger.info("\(prefix): \(key) = \(value)", function: "")
            } else {
                Logger.info("\(prefix): \(key) = nil", function: "")
            }
        }

        for flag in Flags.Supported.allCases {
            let value = remoteConfig.config[flag.rawFlag]
            logFlag("Config.Supported", flag.rawFlag, value)
        }

        for flag in Flags.Sticky.allCases {
            let value = remoteConfig.config[flag.rawFlag]
            logFlag("Config.Sticky", flag.rawFlag, value)
        }

        let flagMap = buildFlagMap()
        for key in Array(flagMap.keys).sorted() {
            let value = flagMap[key]
            logFlag("Flag", key, value)
        }
    }

    public static func buildFlagMap() -> [String: Any] {
        BaseFlags.buildFlagMap(for: RemoteConfig.self) { (key: String) -> Any? in
            RemoteConfig.value(forKey: key)
        }
    }
}

private struct Flags {
    static let prefix = "ios."

    // Values defined in this array remain forever true once they are
    // marked true regardless of the remote state.
    enum Sticky: String, FlagType {
        case groupsV2GoodCitizen
        case versionedProfiles
    }

    // We filter the received config down to just the supported flags.
    // This ensures if we have a sticky flag it doesn't get inadvertently
    // set because we cached a value before it went public. e.g. if we set
    // a sticky flag to 100% in beta then turn it back to 0% before going
    // to production.
    enum Supported: String, FlagType {
        case kbs
        case groupsV2CreateGroups
        case groupsV2GoodCitizen
        case deleteForEveryone
        case versionedProfiles
    }
}

private protocol FlagType: CaseIterable {
    var rawValue: String { get }
    var rawFlag: String { get }
    static var allRawFlags: [String] { get }
}

private extension FlagType {
    var rawFlag: String { Flags.prefix + rawValue }
    static var allRawFlags: [String] { allCases.map { $0.rawFlag } }
}

@objc
public protocol RemoteConfigManager: AnyObject {
    var cachedConfig: RemoteConfig? { get }

    func warmCaches()
}

@objc
public class StubbableRemoteConfigManager: NSObject, RemoteConfigManager {
    public var cachedConfig: RemoteConfig?

    public func warmCaches() {}
}

@objc
public class ServiceRemoteConfigManager: NSObject, RemoteConfigManager {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var grdbStorage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    private var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    private let serviceClient: SignalServiceClient = SignalServiceRestClient()

    let keyValueStore: SDSKeyValueStore = SDSKeyValueStore(collection: "RemoteConfigManager")

    // MARK: -

    private let hasWarmedCache = AtomicBool(false)

    private var _cachedConfig: RemoteConfig?
    @objc
    public private(set) var cachedConfig: RemoteConfig? {
        get {
            if !hasWarmedCache.get() {
                owsFailDebug("CachedConfig not yet set.")
            }

            return _cachedConfig
        }
        set {
            AssertIsOnMainThread()
            assert(_cachedConfig == nil)

            _cachedConfig = newValue
        }
    }

    @objc
    public override init() {
        super.init()

        // The fetched config won't take effect until the *next* launch.
        // That's not ideal, but we can't risk changing configs in the middle
        // of an app lifetime.
        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
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

    public func warmCaches() {
        cacheCurrent()

        RemoteConfig.logFlags()
    }

    private func cacheCurrent() {
        AssertIsOnMainThread()

        if let storedConfig = self.databaseStorage.read(block: { transaction in
            self.keyValueStore.getRemoteConfig(transaction: transaction)
        }) {
            Logger.info("loaded stored config: \(storedConfig)")
            self.cachedConfig = RemoteConfig(storedConfig)
        } else {
            Logger.info("no stored remote config")
        }

        hasWarmedCache.set(true)
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
        firstly {
            self.serviceClient.getRemoteConfig()
        }.done(on: .global()) { fetchedConfig in
            var configToStore = fetchedConfig.filter { Flags.Supported.allRawFlags.contains($0.key) }
            self.databaseStorage.write { transaction in
                // Update fetched config to reflect any sticky flags.
                if let existingConfig = self.keyValueStore.getRemoteConfig(transaction: transaction) {
                    existingConfig.lazy.filter { Flags.Sticky.allRawFlags.contains($0.key) }.forEach {
                        configToStore[$0.key] = $0.value || (fetchedConfig[$0.key] ?? false)
                    }
                }

                self.keyValueStore.setRemoteConfig(configToStore, transaction: transaction)
                self.keyValueStore.setLastFetched(Date(), transaction: transaction)
            }
            Logger.info("stored new remoteConfig: \(configToStore)")
        }.catch { error in
            Logger.error("error: \(error)")
        }
    }
}

private extension SDSKeyValueStore {

    // MARK: - Remote Config

    var remoteConfigKey: String { "remoteConfigKey" }

    func getRemoteConfig(transaction: SDSAnyReadTransaction) -> [String: Bool]? {
        guard let object = getObject(forKey: remoteConfigKey, transaction: transaction) else {
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
