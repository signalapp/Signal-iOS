//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class RemoteConfig: BaseFlags {

    // rather than interact with `config` directly, prefer encoding any string constants
    // into a getter below...
    fileprivate let isEnabledFlags: [String: Bool]
    fileprivate let valueFlags: [String: AnyObject]
    private let standardMediaQualityLevel: ImageQualityLevel?
    private let paymentsDisabledRegions: PhoneNumberRegions
    private let applePayDisabledRegions: PhoneNumberRegions
    private let creditAndDebitCardDisabledRegions: PhoneNumberRegions
    private let paypalDisabledRegions: PhoneNumberRegions

    init(isEnabledFlags: [String: Bool],
         valueFlags: [String: AnyObject]) {
        self.isEnabledFlags = isEnabledFlags
        self.valueFlags = valueFlags
        self.standardMediaQualityLevel = Self.determineStandardMediaQualityLevel(valueFlags: valueFlags)
        self.paymentsDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .paymentsDisabledRegions)
        self.applePayDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .applePayDisabledRegions)
        self.creditAndDebitCardDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .creditAndDebitCardDisabledRegions)
        self.paypalDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .paypalDisabledRegions)
    }

    @objc
    public static var kbs: Bool {
        return isEnabled(.kbs)
    }

    private static let forceDisableUuidSafetyNumbers = true

    @objc
    public static var uuidSafetyNumbers: Bool {
        guard !forceDisableUuidSafetyNumbers else { return false }
        return isEnabled(.uuidSafetyNumbers)
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

    public static var groupsV2MaxBannedMembers: UInt {
        groupsV2MaxGroupSizeHardLimit
    }

    @objc
    public static var groupCalling: Bool {
        return DebugFlags.forceGroupCalling || !isEnabled(.groupCallingKillSwitch)
    }

    @objc
    public static var cdsSyncInterval: TimeInterval {
        interval(.cdsSyncInterval, defaultInterval: kDayInterval * 2)
    }

    @objc
    public static var automaticSessionResetKillSwitch: Bool {
        return isEnabled(.automaticSessionResetKillSwitch)
    }

    @objc
    public static var automaticSessionResetAttemptInterval: TimeInterval {
        interval(.automaticSessionResetAttemptInterval, defaultInterval: kHourInterval)
    }

    @objc
    public static var reactiveProfileKeyAttemptInterval: TimeInterval {
        interval(.reactiveProfileKeyAttemptInterval, defaultInterval: kHourInterval)
    }

    @objc
    public static var paymentsResetKillSwitch: Bool {
        isEnabled(.paymentsResetKillSwitch)
    }

    public static var standardMediaQualityLevel: ImageQualityLevel? {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else { return nil }
        return remoteConfig.standardMediaQualityLevel
    }

    public static var paymentsDisabledRegions: PhoneNumberRegions {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else { return [] }
        return remoteConfig.paymentsDisabledRegions
    }

    public static var applePayDisabledRegions: PhoneNumberRegions {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else { return [] }
        return remoteConfig.applePayDisabledRegions
    }

    public static var creditAndDebitCardDisabledRegions: PhoneNumberRegions {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else { return [] }
        return remoteConfig.creditAndDebitCardDisabledRegions
    }

    public static var canDonateOneTimeWithApplePay: Bool {
        !isEnabled(.applePayOneTimeDonationKillSwitch)
    }

    public static var canDonateGiftWithApplePay: Bool {
        !isEnabled(.applePayGiftDonationKillSwitch)
    }

    public static var canDonateMonthlyWithApplePay: Bool {
        !isEnabled(.applePayMonthlyDonationKillSwitch)
    }

    public static var canDonateOneTimeWithCreditOrDebitCard: Bool {
        !isEnabled(.cardOneTimeDonationKillSwitch)
    }

    public static var canDonateGiftWithCreditOrDebitCard: Bool {
        !isEnabled(.cardGiftDonationKillSwitch)
    }

    public static var canDonateMonthlyWithCreditOrDebitCard: Bool {
        !isEnabled(.cardMonthlyDonationKillSwitch)
    }

    public static var canDonateOneTimeWithPaypal: Bool {
        !isEnabled(.paypalOneTimeDonationKillSwitch)
    }

    public static var canDonateGiftWithPayPal: Bool {
        !isEnabled(.paypalGiftDonationKillSwitch)
    }

    public static var canDonateMonthlyWithPaypal: Bool {
        !isEnabled(.paypalMonthlyDonationKillSwitch)
    }

    public static var paypalDisabledRegions: PhoneNumberRegions {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else { return [] }
        return remoteConfig.paypalDisabledRegions
    }

    private static func determineStandardMediaQualityLevel(valueFlags: [String: AnyObject]) -> ImageQualityLevel? {
        let rawFlag: String = Flags.SupportedValuesFlags.standardMediaQualityLevel.rawFlag

        guard
            let csvString = valueFlags[rawFlag] as? String,
            let stringValue = Self.countryCodeValue(csvString: csvString, csvDescription: rawFlag),
            let uintValue = UInt(stringValue),
            let defaultMediaQuality = ImageQualityLevel(rawValue: uintValue)
        else {
            return nil
        }
        return defaultMediaQuality
    }

    fileprivate static func parsePhoneNumberRegions(
        valueFlags: [String: AnyObject],
        flag: Flags.SupportedValuesFlags
    ) -> PhoneNumberRegions {
        guard let valueList = valueFlags[flag.rawFlag] as? String else { return [] }
        return PhoneNumberRegions(fromRemoteConfig: valueList)
    }

    @objc
    public static var senderKeyKillSwitch: Bool {
        isEnabled(.senderKeyKillSwitch)
    }

    @objc
    public static var messageResendKillSwitch: Bool {
        isEnabled(.messageResendKillSwitch)
    }

    @objc
    public static var replaceableInteractionExpiration: TimeInterval {
        interval(.replaceableInteractionExpiration, defaultInterval: kHourInterval)
    }

    @objc
    public static var messageSendLogEntryLifetime: TimeInterval {
        interval(.messageSendLogEntryLifetime, defaultInterval: 2 * kWeekInterval)
    }

    @objc
    public static var donorBadgeDisplay: Bool {
        DebugFlags.forceDonorBadgeDisplay || !isEnabled(.donorBadgeDisplayKillSwitch)
    }

    @objc
    public static var changePhoneNumberUI: Bool {
        if DebugFlags.forceChangePhoneNumberUI.get() {
            return true
        }
        return isEnabled(.changePhoneNumberUI)
    }

    @objc
    public static var stories: Bool {
        if DebugFlags.forceStories {
            return true
        }
        if isEnabled(.storiesKillSwitch) {
            return false
        }
        return true
    }

    @objc
    public static var canReceiveGiftBadges: Bool {
        FeatureFlags.shouldUseRemoteConfigForReceivingGiftBadges && isEnabled(.canReceiveGiftBadges, defaultValue: true)
    }

    public static var canSendGiftBadges: Bool {
        if DebugFlags.internalSettings {
            return true
        } else if FeatureFlags.isPrerelease {
            return isEnabled(.canSendGiftBadgesInPrerelease, defaultValue: false)
        } else {
            return isEnabled(.canSendGiftBadgesInProduction, defaultValue: false)
        }
    }

    public static var inboundGroupRings: Bool {
        DebugFlags.internalSettings || !isEnabled(.inboundGroupRingsKillSwitch)
    }

    public static var outboundGroupRings: Bool {
        DebugFlags.internalSettings || isEnabled(.groupRings2)
    }

    public static var maxGroupCallRingSize: UInt {
        let defaultValue: UInt = 16
        guard AppReadiness.isAppReady else {
            owsFailDebug("Storage is not yet ready.")
            return defaultValue
        }
        guard let rawValue: AnyObject = value(.maxGroupCallRingSize) else {
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

    public static var contactDiscoveryV2KillSwitch: Bool {
        isEnabled(.contactDiscoveryV2KillSwitch)
    }

    public static var enableAutoAPNSRotation: Bool {
        return isEnabled(.enableAutoAPNSRotation, defaultValue: false)
    }

    // MARK: - Country code buckets

    /// Determine if a country-code-dependent flag is enabled for the current
    /// user, given a country-code CSV and key.
    ///
    /// - Parameter csvString: a CSV containing `<country-code>:<parts-per-million>` pairs
    /// - Parameter key: a key to use as part of bucketing
    static func isCountryCodeBucketEnabled(csvString: String, key: String, csvDescription: String) -> Bool {
        guard
            let countryCodeValue = countryCodeValue(csvString: csvString, csvDescription: csvDescription),
            let countEnabled = UInt64(countryCodeValue)
        else {
            return false
        }

        return isBucketEnabled(key: key, countEnabled: countEnabled, bucketSize: 1_000_000)
    }

    private static func isCountryCodeBucketEnabled(flag: Flags.SupportedValuesFlags, valueFlags: [String: AnyObject]) -> Bool {
        let rawFlag = flag.rawFlag
        guard let csvString = valueFlags[rawFlag] as? String else { return false }

        return isCountryCodeBucketEnabled(csvString: csvString, key: rawFlag, csvDescription: rawFlag)
    }

    /// Given a CSV of `<country-code>:<value>` pairs, extract the `<value>`
    /// corresponding to the current user's country.
    private static func countryCodeValue(csvString: String, csvDescription: String) -> String? {
        guard !csvString.isEmpty else { return nil }

        // The value should always be a comma-separated list of country codes colon-separated
        // from a value. There all may be an optional be a wildcard "*" country code that any
        // unspecified country codes should use. If neither the local country code or the wildcard
        // is specified, we assume the value is not set.
        let countryCodeToValueMap = csvString
            .components(separatedBy: ",")
            .reduce(into: [String: String]()) { result, value in
                let components = value.components(separatedBy: ":")
                guard components.count == 2 else { return owsFailDebug("Invalid \(csvDescription) value \(value)") }
                let countryCode = components[0]
                let countryValue = components[1]
                result[countryCode] = countryValue
        }

        guard !countryCodeToValueMap.isEmpty else { return nil }

        guard let localE164 = TSAccountManager.shared.localNumber,
            let localCountryCode = PhoneNumber(fromE164: localE164)?.getCountryCode()?.stringValue else {
                owsFailDebug("Missing local number")
                return nil
        }

        return countryCodeToValueMap[localCountryCode] ?? countryCodeToValueMap["*"]
    }

    private static func isBucketEnabled(key: String, countEnabled: UInt64, bucketSize: UInt64) -> Bool {
        guard let uuid = TSAccountManager.shared.localUuid else {
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

        data.append(uuid.data)

        guard let hash = Cryptography.computeSHA256Digest(data) else {
            owsFailDebug("Failed to calculate hash")
            return 0
        }

        guard hash.count == 32 else {
            owsFailDebug("Hash has incorrect length \(hash.count)")
            return 0
        }

        // uuid_bucket = UINT64_FROM_FIRST_8_BYTES_BIG_ENDIAN(SHA256(rawFlag + "." + uuidBytes)) % bucketSize
        return UInt64(bigEndianData: hash.prefix(8))! % bucketSize
    }

    // MARK: -

    private static func interval(
        _ flag: Flags.SupportedValuesFlags,
        defaultInterval: TimeInterval
    ) -> TimeInterval {
        guard let intervalString: String = value(flag),
              let interval = TimeInterval(intervalString) else {
            return defaultInterval
        }
        return interval
    }

    private static func isEnabled(_ flag: Flags.SupportedIsEnabledFlags, defaultValue: Bool = false) -> Bool {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        return remoteConfig.isEnabledFlags[flag.rawFlag] ?? defaultValue
    }

    private static func value<T>(_ flag: Flags.SupportedValuesFlags) -> T? {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else {
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
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else {
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

        let flagMap = allFlags()
        for key in flagMap.keys.sorted() {
            let value = flagMap[key]
            logFlag("Flag", key, value)
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

    // Values defined in this array will update while the app is running,
    // as soon as we fetch an update to the remote config. They will not
    // wait for an app restart.
    enum HotSwappableIsEnabledFlags: String, FlagType {
        // This can't be empty, so we define a bogus case. Remove this if you add a flag here.
        case __noHotSwappableIsEnabledFlags
    }

    // We filter the received config down to just the supported flags.
    // This ensures if we have a sticky flag it doesn't get inadvertently
    // set because we cached a value before it went public. e.g. if we set
    // a sticky flag to 100% in beta then turn it back to 0% before going
    // to production.
    enum SupportedIsEnabledFlags: String, FlagType {
        case kbs
        case uuidSafetyNumbers
        case groupCallingKillSwitch
        case automaticSessionResetKillSwitch
        case paymentsResetKillSwitch
        case senderKeyKillSwitch
        case messageResendKillSwitch
        case donorBadgeDisplayKillSwitch
        case changePhoneNumberUI
        case canSendGiftBadgesInPrerelease
        case canSendGiftBadgesInProduction
        case canReceiveGiftBadges
        case groupRings2
        case inboundGroupRingsKillSwitch
        case storiesKillSwitch
        case applePayOneTimeDonationKillSwitch
        case applePayGiftDonationKillSwitch
        case applePayMonthlyDonationKillSwitch
        case cardOneTimeDonationKillSwitch
        case cardGiftDonationKillSwitch
        case cardMonthlyDonationKillSwitch
        case paypalOneTimeDonationKillSwitch
        case paypalGiftDonationKillSwitch
        case paypalMonthlyDonationKillSwitch
        case contactDiscoveryV2KillSwitch
        case enableAutoAPNSRotation
        case ringrtcNwPathMonitorTrialKillSwitch
    }

    // Values defined in this array remain set once they are
    // set regardless of the remote state.
    enum StickyValuesFlags: String, FlagType {
        case groupsV2MaxGroupSizeRecommended
        case groupsV2MaxGroupSizeHardLimit
    }

    // Values defined in this array will update while the app is running,
    // as soon as we fetch an update to the remote config. They will not
    // wait for an app restart.
    enum HotSwappableValuesFlags: String, FlagType {
        case groupsV2MaxGroupSizeRecommended
        case groupsV2MaxGroupSizeHardLimit
        case automaticSessionResetAttemptInterval
        case reactiveProfileKeyAttemptInterval
        case paymentsDisabledRegions
        case applePayDisabledRegions
        case creditAndDebitCardDisabledRegions
        case paypalDisabledRegions
        case maxGroupCallRingSize
    }

    // We filter the received config down to just the supported values.
    // This ensures if we have a sticky value it doesn't get inadvertently
    // set because we cached a value before it went public. e.g. if we set
    // a sticky value to X in beta then remove it before going to production.
    enum SupportedValuesFlags: String, FlagType {
        case groupsV2MaxGroupSizeRecommended
        case groupsV2MaxGroupSizeHardLimit
        case clientExpiration
        case cdsSyncInterval
        case automaticSessionResetAttemptInterval
        case reactiveProfileKeyAttemptInterval
        case standardMediaQualityLevel
        case replaceableInteractionExpiration
        case messageSendLogEntryLifetime
        case paymentsDisabledRegions
        case applePayDisabledRegions
        case creditAndDebitCardDisabledRegions
        case paypalDisabledRegions
        case maxGroupCallRingSize
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
        case "cdsSyncInterval": return "cds.syncInterval.seconds"
        case "paymentsDisabledRegions": return "global.payments.disabledRegions"
        case "applePayDisabledRegions": return "global.donations.apayDisabledRegions"
        case "creditAndDebitCardDisabledRegions": return "global.donations.ccDisabledRegions"
        case "paypalDisabledRegions": return "global.donations.paypalDisabledRegions"
        case "maxGroupCallRingSize": return "global.calling.maxGroupCallRingSize"
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

    let keyValueStore: SDSKeyValueStore = SDSKeyValueStore(collection: "RemoteConfigManager")

    // MARK: -

    private let hasWarmedCache = AtomicBool(false)

    private var _cachedConfig = AtomicOptional<RemoteConfig>(nil)
    @objc
    public private(set) var cachedConfig: RemoteConfig? {
        get {
            if !hasWarmedCache.get() {
                owsFailDebug("CachedConfig not yet set.")
            }

            return _cachedConfig.get()
        }
        set { _cachedConfig.set(newValue) }
    }

    @objc
    public override init() {
        super.init()

        // The fetched config won't take effect until the *next* launch.
        // That's not ideal, but we can't risk changing configs in the middle
        // of an app lifetime.
        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            guard self.tsAccountManager.isRegistered else {
                return
            }
            self.scheduleNextRefresh()
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

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        guard tsAccountManager.isRegistered else { return }
        Logger.info("Refreshing and immediately applying new flags due to new registration.")
        refresh().done(on: .global()) {
            self.cacheCurrent()
        }.catch { error in
            Logger.error("Failed to update remote config after registration change \(error)")
        }
    }

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        cacheCurrent()

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            RemoteConfig.logFlags()
        }
    }

    private func cacheCurrent() {
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

    private static let refreshInterval = 2 * kHourInterval
    private var refreshTimer: Timer?

    private var lastAttempt: Date = .distantPast
    private var consecutiveFailures: UInt = 0
    private var nextPermittedAttempt: Date {
        AssertIsOnMainThread()
        let backoffDelay = OWSOperation.retryIntervalForExponentialBackoff(failureCount: consecutiveFailures)
        let earliestPermittedAttempt = lastAttempt.addingTimeInterval(backoffDelay)

        let lastSuccess = databaseStorage.read { keyValueStore.getLastFetched(transaction: $0) }
        let nextScheduledRefresh = (lastSuccess ?? .distantPast).addingTimeInterval(Self.refreshInterval)

        return max(earliestPermittedAttempt, nextScheduledRefresh)
    }

    private func scheduleNextRefresh() {
        AssertIsOnMainThread()
        refreshTimer?.invalidate()
        refreshTimer = nil
        let nextAttempt = nextPermittedAttempt

        if nextAttempt.isBeforeNow {
            refresh()
        } else {
            Logger.info("Scheduling remote config refresh for \(nextAttempt).")
            refreshTimer = Timer.scheduledTimer(
                withTimeInterval: nextAttempt.timeIntervalSinceNow,
                repeats: false
            ) { [weak self] timer in
                timer.invalidate()
                self?.refresh()
            }
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

    @discardableResult
    private func refresh() -> Promise<Void> {
        AssertIsOnMainThread()
        Logger.info("Refreshing remote config.")
        lastAttempt = Date()

        return firstly(on: .global()) {
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

            // Hotswap any hotswappable flags.

            var cachedIsEnabledFlags = self.cachedConfig?.isEnabledFlags ?? [:]
            var cachedValueFlags = self.cachedConfig?.valueFlags ?? [:]

            for flag in Flags.HotSwappableIsEnabledFlags.allRawFlags {
                cachedIsEnabledFlags[flag] = isEnabledFlags[flag]
            }

            for flag in Flags.HotSwappableValuesFlags.allRawFlags {
                cachedValueFlags[flag] = valueFlags[flag]
            }

            self.cachedConfig = RemoteConfig(isEnabledFlags: cachedIsEnabledFlags, valueFlags: cachedValueFlags)

            Logger.info("Hotswapped new remoteConfig. isEnabledFlags: \(cachedIsEnabledFlags), valueFlags: \(cachedValueFlags)")

            // Persist all flags in the database to be applied on next launch.

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

            // As a special case, persist RingRTC field trials. See comments in
            // ``RingrtcFieldTrials`` for details.
            RingrtcFieldTrials.saveNwPathMonitorTrialState(
                isEnabled: {
                    let flag = Flags.SupportedIsEnabledFlags.ringrtcNwPathMonitorTrialKillSwitch
                    let isKilled = isEnabledFlags[flag.rawValue] ?? false
                    return !isKilled
                }(),
                in: CurrentAppContext().appUserDefaults()
            )

            self.consecutiveFailures = 0
            Logger.info("Stored new remoteConfig. isEnabledFlags: \(isEnabledFlags), valueFlags: \(valueFlags)")
        }.catch(on: .main) { error in
            Logger.error("error: \(error)")
            self.consecutiveFailures += 1
        }.ensure(on: .main) {
            self.scheduleNextRefresh()
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
        let currentVersion4 = appVersion.currentAppVersion4
        for minimumVersion in minimumVersions {
            // We only are interested in minimum versions greater than our current version.
            // Note: This method of comparison will only work as long as we always use
            // *long* version strings (x.x.x.x). We enforce that `MinimumVersion` only
            // uses long versions while decoding.
            guard minimumVersion.string.compare(
                currentVersion4,
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

    private static var remoteConfigIsEnabledFlagsKey: String { "remoteConfigKey" }

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

    private static var remoteConfigValueFlagsKey: String { "remoteConfigValueFlags" }

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
