//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class RemoteConfig: BaseFlags {

    // rather than interact with `config` directly, prefer encoding any string constants
    // into a getter below...
    private let isEnabledFlags: [String: Bool]
    private let valueFlags: [String: AnyObject]
    private let researchMegaphone: Bool

    init(isEnabledFlags: [String: Bool],
         valueFlags: [String: AnyObject]) {
        self.isEnabledFlags = isEnabledFlags
        self.valueFlags = valueFlags
        self.researchMegaphone = Self.isResearchMegaphoneEnabled(valueFlags: valueFlags)
    }

    @objc
    public static var kbs: Bool {
        // This feature latches "on" – once they have a master key in KBS,
        // even if we turn it off on the server they will keep using KBS.
        guard !KeyBackupService.hasMasterKey else { return true }
        return isEnabled(.kbs)
    }

    @objc
    public static var groupsV2InviteLinks: Bool {
        true
    }

    private static let forceDisableUuidSafetyNumbers = true

    @objc
    public static var uuidSafetyNumbers: Bool {
        guard !forceDisableUuidSafetyNumbers else { return false }
        return isEnabled(.uuidSafetyNumbers)
    }

    @objc
    public static var profilesForAll: Bool {
        if DebugFlags.forceProfilesForAll { return true }
        return isEnabled(.profilesForAll)
    }

    @objc
    public static var groupsV2MaxGroupSizeRecommended: UInt {
        let defaultValue: UInt = 151
        guard AppReadiness.isAppReady else {
            owsFailDebug("Storage is not yet ready.")
            return defaultValue
        }
        guard let rawValue: AnyObject = value(.groupsV2MaxGroupSizeRecommended) else {
            return defaultValue
        }
        guard let stringValue = rawValue as? String else {
            owsFailDebug("Unexpected value.")
            return defaultValue
        }
        guard let uintValue = UInt(stringValue) else {
            owsFailDebug("Invalid value.")
            return defaultValue
        }
        return uintValue
    }

    @objc
    public static var groupsV2MaxGroupSizeHardLimit: UInt {
        let defaultValue: UInt = 1001
        guard AppReadiness.isAppReady else {
            owsFailDebug("Storage is not yet ready.")
            return defaultValue
        }
        guard let rawValue: AnyObject = value(.groupsV2MaxGroupSizeHardLimit) else {
            return defaultValue
        }
        guard let stringValue = rawValue as? String else {
            owsFailDebug("Unexpected value.")
            return defaultValue
        }
        guard let uintValue = UInt(stringValue) else {
            owsFailDebug("Invalid value.")
            return defaultValue
        }
        return uintValue
    }

    @objc
    public static var usernames: Bool {
        FeatureFlags.usernamesSupported
    }

    // Controls whether or not the client will show the manual migration UI.
    // Will only offer migrations if all members can be migrated.
    @objc
    public static var groupsV2MigrationAutoMigrations: Bool {
        guard FeatureFlags.groupsV2Migrations else {
            return false
        }
        // If either of the "blocking migrations" or "manual migrations" flags
        // are set, auto migrations are also enabled.
        return (DebugFlags.groupsV2migrationsForceEnableAutoMigrations.get() ||
                    isEnabled(.groupsV2autoMigrations) ||
                    isEnabled(.groupsV2manualMigrations) ||
                    isEnabled(.groupsV2blockingMigrations))
    }

    // Controls whether or not the client will show the manual migration UI.
    // Will only offer migrations if all members can be migrated.
    @objc
    public static var groupsV2MigrationManualMigrations: Bool {
        guard FeatureFlags.groupsV2Migrations else {
            return false
        }
        // If the "blocking migrations" flag is set, manual migrations are also enabled.
        return (DebugFlags.groupsV2migrationsForceEnableManualMigrations.get() ||
                    isEnabled(.groupsV2manualMigrations) ||
                    isEnabled(.groupsV2blockingMigrations))
    }

    // Controls whether or not the client will show the manual migration UI.
    // Will only offer migrations if all members can be migrated.
    @objc
    public static var groupsV2MigrationBlockingMigrations: Bool {
        guard FeatureFlags.groupsV2Migrations else {
            return false
        }
        return (DebugFlags.groupsV2MigrationForceBlockingMigrations.get() ||
            isEnabled(.groupsV2blockingMigrations))
    }

    @objc
    public static var groupCalling: Bool {
        return DebugFlags.forceGroupCalling || !isEnabled(.groupCallingKillSwitch)
    }

    @objc
    public static var cdsSyncInterval: TimeInterval {
        guard let cdsSyncIntervalString: String = value(.cdsSyncInterval),
              let cdsSyncInterval = TimeInterval(cdsSyncIntervalString) else {
            return 2 * kDayInterval
        }
        return cdsSyncInterval
    }

    @objc
    public static var automaticSessionResetKillSwitch: Bool {
        return isEnabled(.automaticSessionResetKillSwitch)
    }

    @objc
    public static var automaticSessionResetAttemptInterval: TimeInterval {
        guard let automaticSessionResetAttemptIntervalString: String = value(.automaticSessionResetAttemptInterval),
              let automaticSessionResetAttemptInterval = TimeInterval(automaticSessionResetAttemptIntervalString) else {
            return kHourInterval
        }
        return automaticSessionResetAttemptInterval
    }

    @objc
    public static var researchMegaphone: Bool {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else { return false }
        return remoteConfig.researchMegaphone
    }

    private static func isResearchMegaphoneEnabled(valueFlags: [String: AnyObject]) -> Bool {
        let rawFlag = Flags.SupportedValuesFlags.researchMegaphone.rawFlag

        guard let value = valueFlags[rawFlag] as? String else { return false }

        guard !value.isEmpty else { return false }

        // The value should always be a comma-separated list of country codes colon-separated
        // from how many buckets out of 1 million should be enabled to see the research
        // megaphone in that country code. There will also optional be a wildcard "*" bucket
        // that any unspecified country codes should use. If neither the local country code
        // or the wildcard is specified, we assume the megaphone is not enabled.
        let countEnabledPerCountryCode = value
            .components(separatedBy: ",")
            .reduce(into: [String: UInt64]()) { result, value in
                let components = value.components(separatedBy: ":")
                guard components.count == 2 else { return owsFailDebug("Invalid research megaphone value \(value)")}
                let countryCode = components[0]
                let countEnabled = UInt64(components[1])
                result[countryCode] = countEnabled
        }

        guard !countEnabledPerCountryCode.isEmpty else { return false }

        guard let localE164 = TSAccountManager.shared().localNumber,
            let localCountryCode = PhoneNumber(fromE164: localE164)?.getCountryCode()?.stringValue else {
                owsFailDebug("Missing local number")
                return false
        }

        let localCountEnabled = countEnabledPerCountryCode[localCountryCode]
        let wildcardCountEnabled = countEnabledPerCountryCode["*"]

        if let countEnabled = localCountEnabled ?? wildcardCountEnabled {
            return isBucketEnabled(key: rawFlag, countEnabled: countEnabled, bucketSize: 1000000)
        } else {
            return false
        }
    }

    // MARK: -

    private static func isBucketEnabled(key: String, countEnabled: UInt64, bucketSize: UInt64) -> Bool {
        guard let uuid = TSAccountManager.shared().localUuid else {
            owsFailDebug("Missing local UUID")
            return false
        }

        return countEnabled > bucket(key: key, uuid: uuid, bucketSize: bucketSize)
    }

    static func bucket(key: String, uuid: UUID, bucketSize: UInt64) -> UInt64 {
        guard var data = (key + ".").data(using: .utf8) else {
            owsFailDebug("Failed to get data from key")
            return 0
        }

        let uuidBytes = withUnsafePointer(to: uuid.uuid) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: uuid.uuid))
        }

        data.append(uuidBytes)

        guard let hash = Cryptography.computeSHA256Digest(data) else {
            owsFailDebug("Failed to calculate hash")
            return 0
        }

        guard hash.count == 32 else {
            owsFailDebug("Hash has incorrect length \(hash.count)")
            return 0
        }

        // uuid_bucket = UINT64_FROM_FIRST_8_BYTES_BIG_ENDIAN(SHA256(rawFlag + "." + uuidBytes)) % bucketSize
        let uuidBucket = hash[0..<8].withUnsafeBytes {
            UInt64(bigEndian: $0.load(as: UInt64.self)) % bucketSize
        }

        return uuidBucket
    }

    private static func isEnabled(_ flag: Flags.SupportedIsEnabledFlags, defaultValue: Bool = false) -> Bool {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        return remoteConfig.isEnabledFlags[flag.rawFlag] ?? defaultValue
    }

    private static func value<T>(_ flag: Flags.SupportedValuesFlags) -> T? {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else {
            return nil
        }
        guard let remoteObject = remoteConfig.valueFlags[flag.rawFlag] else {
            return nil
        }
        guard let remoteValue = remoteObject as? T else {
            owsFailDebug("Remote value has unexpected type: \(remoteObject)")
            return nil
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
        case uuidSafetyNumbers
    }

    // We filter the received config down to just the supported flags.
    // This ensures if we have a sticky flag it doesn't get inadvertently
    // set because we cached a value before it went public. e.g. if we set
    // a sticky flag to 100% in beta then turn it back to 0% before going
    // to production.
    enum SupportedIsEnabledFlags: String, FlagType {
        case kbs
        case uuidSafetyNumbers
        case groupsV2InviteLinksV2
        case profilesForAll
        case groupsV2autoMigrations
        case groupsV2manualMigrations
        case groupsV2blockingMigrations
        case groupCallingKillSwitch
        case automaticSessionResetKillSwitch
    }

    // Values defined in this array remain set once they are
    // set regardless of the remote state.
    enum StickyValuesFlags: String, FlagType {
        case groupsV2MaxGroupSizeRecommended
        case groupsV2MaxGroupSizeHardLimit
    }

    // We filter the received config down to just the supported values.
    // This ensures if we have a sticky value it doesn't get inadvertently
    // set because we cached a value before it went public. e.g. if we set
    // a sticky value to X in beta then remove it before going to production.
    enum SupportedValuesFlags: String, FlagType {
        case groupsV2MaxGroupSizeRecommended
        case groupsV2MaxGroupSizeHardLimit
        case clientExpiration
        case researchMegaphone
        case cdsSyncInterval
        case automaticSessionResetAttemptInterval
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
    var rawFlag: String {
        switch rawValue {
        case "groupsV2MaxGroupSizeRecommended": return "global.groupsv2.maxGroupSize"
        case "groupsV2MaxGroupSizeHardLimit": return "global.groupsv2.groupSizeHardLimit"
        case "researchMegaphone": return "research.megaphone.1"
        case "cdsSyncInterval": return "cds.syncInterval.seconds"
        default: return Flags.prefix + rawValue
        }
    }

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

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            RemoteConfig.logFlags()
        }
    }

    private func cacheCurrent() {
        AssertIsOnMainThread()

        var isEnabledFlags = [String: Bool]()
        var valueFlags = [String: AnyObject]()
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

        checkClientExpiration(valueFlags: valueFlags)

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

    private static func isValidValue(_ value: AnyObject) -> Bool {
        // Discard Data for now; ParamParser can't auto-decode them.
        if value as? String != nil {
            return true
        } else {
            owsFailDebug("Unexpected value: \(type(of: value))")
            return false
        }
    }

    private func refresh() {
        firstly {
            self.serviceClient.getRemoteConfig()
        }.done(on: .global()) { (fetchedConfig: [String: RemoteConfigItem]) in
            // Extract the _supported_ flags from the fetched config.
            var isEnabledFlags = [String: Bool]()
            var valueFlags = [String: AnyObject]()
            fetchedConfig.forEach { (key: String, item: RemoteConfigItem) in
                switch item {
                case .isEnabled(let isEnabled):
                    if Flags.SupportedIsEnabledFlags.allRawFlags.contains(key) {
                        isEnabledFlags[key] = isEnabled
                    }
                case .value(let value):
                    if Flags.SupportedValuesFlags.allRawFlags.contains(key) {
                        if Self.isValidValue(value) {
                            valueFlags[key] = value
                        } else {
                            owsFailDebug("Invalid value: \(value) \(type(of: value))")
                        }
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
                    existingConfig.forEach { (key: String, value: AnyObject) in
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
                self.checkClientExpiration(valueFlags: valueFlags)
            }
            Logger.info("stored new remoteConfig. isEnabledFlags: \(isEnabledFlags), valueFlags: \(valueFlags)")
        }.catch { error in
            Logger.error("error: \(error)")
        }
    }
}

// MARK: - Client Expiration

private extension ServiceRemoteConfigManager {
    private struct DecodedMinimumVersion: Codable {
        let string: String?
        let enforcementDate: Date?

        enum CodingKeys: String, CodingKey {
            case string = "minVersion"
            case enforcementDate = "iso8601"
        }
    }

    private struct MinimumVersion: Equatable, CustomStringConvertible {
        let string: String
        let enforcementDate: Date

        var description: String {
            // We filter things like look like an ip address, but we don't
            // want to filter the version string so we replace the dots
            // before logging.
            return "<MinimumVersion: \(string.replacingOccurrences(of: ".", with: "_")), \(enforcementDate)>"
        }
    }

    func checkClientExpiration(valueFlags: [String: AnyObject]) {
        var minimumVersions: [MinimumVersion]?
        defer {
            if let minimumVersions = minimumVersions {
                Logger.info("Minimum client versions: \(minimumVersions)")

                if let remoteExpirationDate = remoteExpirationDate(minimumVersions: minimumVersions) {
                    Logger.info("Setting client expiration date: \(remoteExpirationDate)")
                    AppExpiry.shared.setExpirationDateForCurrentVersion(remoteExpirationDate)
                } else {
                    Logger.info("Clearing client expiration date")
                    AppExpiry.shared.setExpirationDateForCurrentVersion(nil)
                }
            }
        }

        guard let jsonString = valueFlags[Flags.SupportedValuesFlags.clientExpiration.rawFlag] as? String else {
            Logger.info("Received empty clientExpiration, clearing cached value.")
            minimumVersions = []
            return
        }

        guard let valueData = jsonString.data(using: .utf8) else {
            owsFailDebug("Failed to convert client expiration string to data, ignoring.")
            return
        }

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601

        do {
            let decodedValues = try jsonDecoder.decode([DecodedMinimumVersion].self, from: valueData)

            minimumVersions = decodedValues.compactMap { decodedValue in
                // If the string or enforcement date are nil, the JSON provided in the
                // remote config is in some way invalid. Probably, someone typoed a key.
                // We don't want to ignore all client expiration because one value was
                // wrong, so we just throw away that specific minimum version.
                guard let string = decodedValue.string, let enforcementDate = decodedValue.enforcementDate else {
                    owsFailDebug("Received improperly formatted clientExpiration: \(jsonString)")
                    return nil
                }

                // The version should always be a complete long version, like: 3.16.0.1
                // If it's not, we throw it away but still make sure to maintain all the
                // valid minimum versions we received.
                guard string.components(separatedBy: ".").count == 4 else {
                    owsFailDebug("Received invalid version string for clientExpiration: \(string)")
                    return nil
                }

                return MinimumVersion(string: string, enforcementDate: enforcementDate)
            }
        } catch {
            owsFailDebug("Failed to decode client expiration (\(jsonString), \(error)), ignoring.")
        }
    }

    private func remoteExpirationDate(minimumVersions: [MinimumVersion]) -> Date? {
        var oldestEnforcementDate: Date?
        let currentVersion = AppVersion.shared().currentAppVersionLong
        for minimumVersion in minimumVersions {
            // We only are interested in minimum versions greater than our current version.
            // Note: This method of comparison will only work as long as we always use
            // *long* version strings (x.x.x.x). We enforce that `MinimumVersion` only
            // uses long versions while decoding.
            guard minimumVersion.string.compare(
                currentVersion,
                options: .numeric
            ) == .orderedDescending else { continue }

            if let enforcementDate = oldestEnforcementDate {
                oldestEnforcementDate = min(enforcementDate, minimumVersion.enforcementDate)
            } else {
                oldestEnforcementDate = minimumVersion.enforcementDate
            }
        }
        return oldestEnforcementDate
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

    func getRemoteConfigValueFlags(transaction: SDSAnyReadTransaction) -> [String: AnyObject]? {
        guard let object = getObject(forKey: Self.remoteConfigValueFlagsKey, transaction: transaction) else {
            return nil
        }

        guard let remoteConfig = object as? [String: AnyObject] else {
            owsFailDebug("unexpected object: \(object)")
            return nil
        }

        return remoteConfig
    }

    func setRemoteConfigValueFlags(_ newValue: [String: AnyObject], transaction: SDSAnyWriteTransaction) {
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
