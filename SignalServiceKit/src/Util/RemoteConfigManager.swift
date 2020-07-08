//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class RemoteConfig: BaseFlags {

    // rather than interact with `config` directly, prefer encoding any string constants
    // into a getter below...
    private let isEnabledFlags: [String: Bool]
    private let valueFlags: [String: Any]

    init(isEnabledFlags: [String: Bool],
         valueFlags: [String: Any]) {
        self.isEnabledFlags = isEnabledFlags
        self.valueFlags = valueFlags
    }

    @objc
    public static var mandatoryPins: Bool { isEnabled(.mandatoryPins) }

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

    @objc
    public static func groupsV2maxMemberCount(defaultValue: UInt) -> UInt {
        value(.groupsV2memberCountMax,
              defaultValue: defaultValue)
    }

    private static func isEnabled(_ flag: Flags.SupportedIsEnabledFlags, defaultValue: Bool = false) -> Bool {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        return remoteConfig.isEnabledFlags[flag.rawFlag] ?? defaultValue
    }

    private static func value<T>(_ flag: Flags.SupportedValuesFlags, defaultValue: T) -> T {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        guard let remoteObject = remoteConfig.valueFlags[flag.rawFlag] else {
            return defaultValue
        }
        guard let remoteValue = remoteObject as? T else {
            owsFailDebug("Remote value has unexpected type: \(remoteObject)")
            return defaultValue
        }
        return remoteValue
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

        for flag in Flags.SupportedIsEnabledFlags.allCases {
            let value = remoteConfig.isEnabledFlags[flag.rawFlag]
            logFlag("Config.SupportedIsEnabled", flag.rawFlag, value)
        }

        for flag in Flags.StickyIsEnabledFlags.allCases {
            let value = remoteConfig.isEnabledFlags[flag.rawFlag]
            logFlag("Config.StickyIsEnabled", flag.rawFlag, value)
        }

        for flag in Flags.SupportedValuesFlags.allCases {
            let value = remoteConfig.valueFlags[flag.rawFlag]
            logFlag("Config.SupportedValues", flag.rawFlag, value)
        }

        for flag in Flags.StickyValuesFlags.allCases {
            let value = remoteConfig.valueFlags[flag.rawFlag]
            logFlag("Config.StickyValues", flag.rawFlag, value)
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

// MARK: -

private struct Flags {
    static let prefix = "ios."

    // Values defined in this array remain forever true once they are
    // marked true regardless of the remote state.
    enum StickyIsEnabledFlags: String, FlagType {
        case groupsV2GoodCitizen
        case versionedProfiles
    }

    // We filter the received config down to just the supported flags.
    // This ensures if we have a sticky flag it doesn't get inadvertently
    // set because we cached a value before it went public. e.g. if we set
    // a sticky flag to 100% in beta then turn it back to 0% before going
    // to production.
    enum SupportedIsEnabledFlags: String, FlagType {
        case kbs
        case mandatoryPins
        case groupsV2CreateGroups
        case groupsV2GoodCitizen
        case deleteForEveryone
        case versionedProfiles
    }

    // Values defined in this array remain set once they are
    // set regardless of the remote state.
    enum StickyValuesFlags: String, FlagType {
        case groupsV2memberCountMax
    }

    // We filter the received config down to just the supported values.
    // This ensures if we have a sticky value it doesn't get inadvertently
    // set because we cached a value before it went public. e.g. if we set
    // a sticky value to X in beta then remove it before going to production.
    enum SupportedValuesFlags: String, FlagType {
        case groupsV2memberCountMax
    }
}

// MARK: -

private protocol FlagType: CaseIterable {
    var rawValue: String { get }
    var rawFlag: String { get }
    static var allRawFlags: [String] { get }
}

// MARK: -

private extension FlagType {
    var rawFlag: String { Flags.prefix + rawValue }
    static var allRawFlags: [String] { allCases.map { $0.rawFlag } }
}

// MARK: -

@objc
public protocol RemoteConfigManager: AnyObject {
    var cachedConfig: RemoteConfig? { get }

    func warmCaches()
}

// MARK: -

@objc
public class StubbableRemoteConfigManager: NSObject, RemoteConfigManager {
    public var cachedConfig: RemoteConfig?

    public func warmCaches() {}
}

// MARK: -

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

        var isEnabledFlags = [String: Bool]()
        var valueFlags = [String: Any]()
        self.databaseStorage.read { transaction in
            isEnabledFlags = self.keyValueStore.getRemoteConfigIsEnabledFlags(transaction: transaction) ?? [:]
            valueFlags = self.keyValueStore.getRemoteConfigValueFlags(transaction: transaction) ?? [:]
        }

        if !isEnabledFlags.isEmpty || !valueFlags.isEmpty {
            Logger.info("Loaded stored config. isEnabledFlags: \(isEnabledFlags), valueFlags: \(valueFlags)")
            self.cachedConfig = RemoteConfig(isEnabledFlags: isEnabledFlags, valueFlags: valueFlags)
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

    private static func isValidValue(_ value: Any) -> Bool {
        // Discard Data for now; ParamParser can't auto-decode them.
        if value as? String != nil {
            return true
        } else if value as? Bool != nil {
            return true
        } else if value as? Int != nil {
            return true
        } else if value as? UInt != nil {
            return true
        } else if value as? Int8 != nil {
            return true
        } else if value as? UInt8 != nil {
            return true
        } else if value as? Int16 != nil {
            return true
        } else if value as? UInt16 != nil {
            return true
        } else if value as? Int32 != nil {
            return true
        } else if value as? UInt32 != nil {
            return true
        } else if value as? Int64 != nil {
            return true
        } else if value as? UInt64 != nil {
            return true
        } else {
            return false
        }
    }

    private func refresh() {
        firstly {
            self.serviceClient.getRemoteConfig()
        }.done(on: .global()) { (fetchedConfig: [String: ConfigItem]) in
            // Extract the _supported_ flags from the fetched config.
            var isEnabledFlags = [String: Bool]()
            var valueFlags = [String: Any]()
            fetchedConfig.forEach { (key: String, item: ConfigItem) in
                if Flags.SupportedIsEnabledFlags.allRawFlags.contains(key) {
                    isEnabledFlags[key] = item.isEnabled
                }
                if Flags.SupportedValuesFlags.allRawFlags.contains(key),
                    let value = item.value {
                    if Self.isValidValue(value) {
                        valueFlags[key] = value
                    } else {
                        owsFailDebug("Invalid value: \(value) \(type(of: value))")
                    }
                }
            }

            self.databaseStorage.write { transaction in
                // Preserve any sticky flags.
                if let existingConfig = self.keyValueStore.getRemoteConfigIsEnabledFlags(transaction: transaction) {
                    existingConfig.forEach { (key: String, value: Bool) in
                        // Preserve "is enabled" flags if they are sticky and already set.
                        if Flags.StickyIsEnabledFlags.allRawFlags.contains(key),
                            value == true {
                            isEnabledFlags[key] = value
                        }
                    }
                }
                if let existingConfig = self.keyValueStore.getRemoteConfigValueFlags(transaction: transaction) {
                    existingConfig.forEach { (key: String, value: Any) in
                        // Preserve "value" flags if they are sticky and already set and missing from the fetched config.
                        if Flags.StickyValuesFlags.allRawFlags.contains(key),
                            valueFlags[key] == nil {
                            valueFlags[key] = value
                        }
                    }
                }

                self.keyValueStore.setRemoteConfigIsEnabledFlags(isEnabledFlags, transaction: transaction)
                self.keyValueStore.setRemoteConfigValueFlags(valueFlags, transaction: transaction)
                self.keyValueStore.setLastFetched(Date(), transaction: transaction)
            }
            Logger.info("stored new remoteConfig. isEnabledFlags: \(isEnabledFlags), valueFlags: \(valueFlags)")
        }.catch { error in
            Logger.error("error: \(error)")
        }
    }
}

// MARK: -

private extension SDSKeyValueStore {

    // MARK: - Remote Config Enabled Flags

    private static let remoteConfigIsEnabledFlagsKey = "remoteConfigKey"

    func getRemoteConfigIsEnabledFlags(transaction: SDSAnyReadTransaction) -> [String: Bool]? {
        guard let object = getObject(forKey: Self.remoteConfigIsEnabledFlagsKey,
                                     transaction: transaction) else {
            return nil
        }

        guard let remoteConfig = object as? [String: Bool] else {
            owsFailDebug("unexpected object: \(object)")
            return nil
        }

        return remoteConfig
    }

    func setRemoteConfigIsEnabledFlags(_ newValue: [String: Bool], transaction: SDSAnyWriteTransaction) {
        return setObject(newValue,
                         key: Self.remoteConfigIsEnabledFlagsKey,
                         transaction: transaction)
    }

    // MARK: - Remote Config Value Flags

    private static let remoteConfigValueFlagsKey = "remoteConfigValueFlags"

    func getRemoteConfigValueFlags(transaction: SDSAnyReadTransaction) -> [String: Any]? {
        guard let object = getObject(forKey: Self.remoteConfigValueFlagsKey, transaction: transaction) else {
            return nil
        }

        guard let remoteConfig = object as? [String: Any] else {
            owsFailDebug("unexpected object: \(object)")
            return nil
        }

        return remoteConfig
    }

    func setRemoteConfigValueFlags(_ newValue: [String: Any], transaction: SDSAnyWriteTransaction) {
        return setObject(newValue, key: Self.remoteConfigValueFlagsKey, transaction: transaction)
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
