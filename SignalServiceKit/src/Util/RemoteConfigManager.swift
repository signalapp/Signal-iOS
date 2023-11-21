//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

@objc
public class RemoteConfig: BaseFlags {

    /// Difference between the last time the server says it is and the time our
    /// local device says it is. Add this to the local device time to get the
    /// "real" time according to the server.
    ///
    /// This will always be noisy; for one the server response takes variable
    /// time to get to us, so really this represents the time on the server when
    /// it crafted its response, not when we got it. And of course the local
    /// clock can change.
    fileprivate let lastKnownClockSkew: TimeInterval

    fileprivate let isEnabledFlags: [String: Bool]
    fileprivate let valueFlags: [String: String]
    fileprivate let timeGatedFlags: [String: Date]
    private let paymentsDisabledRegions: PhoneNumberRegions
    private let applePayDisabledRegions: PhoneNumberRegions
    private let creditAndDebitCardDisabledRegions: PhoneNumberRegions
    private let paypalDisabledRegions: PhoneNumberRegions
    private let sepaEnabledRegions: PhoneNumberRegions

    init(
        clockSkew: TimeInterval,
        isEnabledFlags: [String: Bool],
        valueFlags: [String: String],
        timeGatedFlags: [String: Date]
    ) {
        self.lastKnownClockSkew = clockSkew
        self.isEnabledFlags = isEnabledFlags
        self.valueFlags = valueFlags
        self.timeGatedFlags = timeGatedFlags
        self.paymentsDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .paymentsDisabledRegions)
        self.applePayDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .applePayDisabledRegions)
        self.creditAndDebitCardDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .creditAndDebitCardDisabledRegions)
        self.paypalDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .paypalDisabledRegions)
        self.sepaEnabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .sepaEnabledRegions)
    }

    fileprivate static var emptyConfig: RemoteConfig {
        RemoteConfig(clockSkew: 0, isEnabledFlags: [:], valueFlags: [:], timeGatedFlags: [:])
    }

    fileprivate func mergingHotSwappableFlags(from newConfig: RemoteConfig) -> RemoteConfig {
        var isEnabledFlags = self.isEnabledFlags
        for flag in IsEnabledFlag.allCases {
            guard flag.isHotSwappable else { continue }
            isEnabledFlags[flag.rawValue] = newConfig.isEnabledFlags[flag.rawValue]
        }
        var valueFlags = self.valueFlags
        for flag in ValueFlag.allCases {
            guard flag.isHotSwappable else { continue }
            valueFlags[flag.rawValue] = newConfig.valueFlags[flag.rawValue]
        }
        var timeGatedFlags = self.timeGatedFlags
        for flag in TimeGatedFlag.allCases {
            guard flag.isHotSwappable else { continue }
            timeGatedFlags[flag.rawValue] = newConfig.timeGatedFlags[flag.rawValue]
        }
        return RemoteConfig(
            clockSkew: newConfig.lastKnownClockSkew,
            isEnabledFlags: isEnabledFlags,
            valueFlags: valueFlags,
            timeGatedFlags: timeGatedFlags
        )
    }

    @objc
    public static var groupsV2MaxGroupSizeRecommended: UInt {
        getUIntValue(forFlag: .groupsV2MaxGroupSizeRecommended, defaultValue: 151)
    }

    @objc
    public static var groupsV2MaxGroupSizeHardLimit: UInt {
        getUIntValue(forFlag: .groupsV2MaxGroupSizeHardLimit, defaultValue: 1001)
    }

    public static var groupsV2MaxBannedMembers: UInt {
        groupsV2MaxGroupSizeHardLimit
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

    public static func standardMediaQualityLevel(localPhoneNumber: String?) -> ImageQualityLevel? {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else { return nil }
        return remoteConfig.standardMediaQualityLevel(localPhoneNumber: localPhoneNumber)
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

    public static var sepaEnabledRegions: PhoneNumberRegions {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else { return [] }
        return remoteConfig.sepaEnabledRegions
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

    public static var canDonateWithSepa: Bool {
        isEnabled(.canDonateWithSepa)
    }

    public static var paypalDisabledRegions: PhoneNumberRegions {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else { return [] }
        return remoteConfig.paypalDisabledRegions
    }

    private func standardMediaQualityLevel(localPhoneNumber: String?) -> ImageQualityLevel? {
        let rawValue: String = ValueFlag.standardMediaQualityLevel.rawValue
        guard
            let csvString = valueFlags[rawValue],
            let stringValue = Self.countryCodeValue(csvString: csvString, csvDescription: rawValue, localPhoneNumber: localPhoneNumber),
            let uintValue = UInt(stringValue),
            let defaultMediaQuality = ImageQualityLevel(rawValue: uintValue)
        else {
            return nil
        }
        return defaultMediaQuality
    }

    fileprivate static func parsePhoneNumberRegions(
        valueFlags: [String: String],
        flag: ValueFlag
    ) -> PhoneNumberRegions {
        guard let valueList = valueFlags[flag.rawValue] else { return [] }
        return PhoneNumberRegions(fromRemoteConfig: valueList)
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

    public static var maxGroupCallRingSize: UInt {
        getUIntValue(forFlag: .maxGroupCallRingSize, defaultValue: 16)
    }

    public static var enableAutoAPNSRotation: Bool {
        return isEnabled(.enableAutoAPNSRotation, defaultValue: false)
    }

    /// The minimum length for a valid nickname, in Unicode codepoints.
    public static var minNicknameLength: UInt32 {
        getUInt32Value(forFlag: .minNicknameLength, defaultValue: 3)
    }

    /// The maximum length for a valid nickname, in Unicode codepoints.
    public static var maxNicknameLength: UInt32 {
        getUInt32Value(forFlag: .maxNicknameLength, defaultValue: 32)
    }

    static var tryToReturnAcisWithoutUaks: Bool {
        return !isEnabled(.cdsDisableCompatibilityMode)
    }

    public static var maxAttachmentDownloadSizeBytes: UInt {
        return getUIntValue(forFlag: .maxAttachmentDownloadSizeBytes, defaultValue: 100 * 1024 * 1024)
    }

    // MARK: UInt values

    private static func getUIntValue(
        forFlag flag: ValueFlag,
        defaultValue: UInt
    ) -> UInt {
        getStringConvertibleValue(
            forFlag: flag,
            defaultValue: defaultValue
        )
    }

    private static func getUInt32Value(
        forFlag flag: ValueFlag,
        defaultValue: UInt32
    ) -> UInt32 {
        getStringConvertibleValue(
            forFlag: flag,
            defaultValue: defaultValue
        )
    }

    private static func getStringConvertibleValue<V>(
        forFlag flag: ValueFlag,
        defaultValue: V
    ) -> V where V: LosslessStringConvertible {
        guard AppReadiness.isAppReady else {
            owsFailDebug("Storage is not yet ready.")
            return defaultValue
        }

        guard let stringValue: String = value(flag) else {
            return defaultValue
        }

        guard let value = V(stringValue) else {
            owsFailDebug("Invalid value.")
            return defaultValue
        }

        return value
    }

    // MARK: - Country code buckets

    /// Determine if a country-code-dependent flag is enabled for the current
    /// user, given a country-code CSV and key.
    ///
    /// - Parameter csvString: a CSV containing `<country-code>:<parts-per-million>` pairs
    /// - Parameter key: a key to use as part of bucketing
    static func isCountryCodeBucketEnabled(csvString: String, key: String, csvDescription: String, localIdentifiers: LocalIdentifiers) -> Bool {
        guard
            let countryCodeValue = countryCodeValue(csvString: csvString, csvDescription: csvDescription, localPhoneNumber: localIdentifiers.phoneNumber),
            let countEnabled = UInt64(countryCodeValue)
        else {
            return false
        }

        return isBucketEnabled(key: key, countEnabled: countEnabled, bucketSize: 1_000_000, localAci: localIdentifiers.aci)
    }

    private static func isCountryCodeBucketEnabled(flag: ValueFlag, valueFlags: [String: String], localIdentifiers: LocalIdentifiers) -> Bool {
        let rawValue = flag.rawValue
        guard let csvString = valueFlags[rawValue] else { return false }

        return isCountryCodeBucketEnabled(csvString: csvString, key: rawValue, csvDescription: rawValue, localIdentifiers: localIdentifiers)
    }

    /// Given a CSV of `<country-code>:<value>` pairs, extract the `<value>`
    /// corresponding to the current user's country.
    private static func countryCodeValue(csvString: String, csvDescription: String, localPhoneNumber: String?) -> String? {
        guard !csvString.isEmpty else { return nil }

        // The value should always be a comma-separated list of country codes
        // colon-separated from a value. There all may be an optional be a wildcard
        // "*" country code that any unspecified country codes should use. If
        // neither the local country code or the wildcard is specified, we assume
        // the value is not set.
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

        guard
            let localPhoneNumber,
            let localCountryCode = PhoneNumber(fromE164: localPhoneNumber)?.getCountryCode()?.stringValue
        else {
            owsFailDebug("Invalid local number")
            return nil
        }

        return countryCodeToValueMap[localCountryCode] ?? countryCodeToValueMap["*"]
    }

    private static func isBucketEnabled(key: String, countEnabled: UInt64, bucketSize: UInt64, localAci: Aci) -> Bool {
        return countEnabled > bucket(key: key, aci: localAci, bucketSize: bucketSize)
    }

    static func bucket(key: String, aci: Aci, bucketSize: UInt64) -> UInt64 {
        guard var data = (key + ".").data(using: .utf8) else {
            owsFailDebug("Failed to get data from key")
            return 0
        }

        data.append(Data(aci.serviceIdBinary))

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

    private static func interval(_ flag: ValueFlag, defaultInterval: TimeInterval) -> TimeInterval {
        guard let intervalString: String = value(flag), let interval = TimeInterval(intervalString) else {
            return defaultInterval
        }
        return interval
    }

    private static func isEnabled(_ flag: IsEnabledFlag, defaultValue: Bool = false) -> Bool {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        return remoteConfig.isEnabled(flag, defaultValue: defaultValue)
    }

    private func isEnabled(_ flag: IsEnabledFlag, defaultValue: Bool = false) -> Bool {
        return isEnabledFlags[flag.rawValue] ?? defaultValue
    }

    private static func isEnabled(_ flag: TimeGatedFlag, defaultValue: Bool = false) -> Bool {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        return remoteConfig.isEnabled(flag, defaultValue: defaultValue)
    }

    private func isEnabled(_ flag: TimeGatedFlag, defaultValue: Bool = false) -> Bool {
        guard let dateThreshold = timeGatedFlags[flag.rawValue] else {
            return defaultValue
        }
        let correctedDate = Date().addingTimeInterval(self.lastKnownClockSkew)
        return correctedDate >= dateThreshold
    }

    private static func value(_ flag: ValueFlag) -> String? {
        guard let remoteConfig = Self.remoteConfigManager.cachedConfig else {
            return nil
        }
        return remoteConfig.valueFlags[flag.rawValue]
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
            }
        }

        for flag in IsEnabledFlag.allCases {
            let value = remoteConfig.isEnabledFlags[flag.rawValue]
            logFlag("Config.IsEnabled", flag.rawValue, value)
        }

        for flag in ValueFlag.allCases {
            let value = remoteConfig.valueFlags[flag.rawValue]
            logFlag("Config.Value", flag.rawValue, value)
        }

        for flag in TimeGatedFlag.allCases {
            let value = remoteConfig.timeGatedFlags[flag.rawValue]
            logFlag("Config.TimeGated", flag.rawValue, value)
        }
    }
}

// MARK: - IsEnabledFlag

private enum IsEnabledFlag: String, FlagType {
    case automaticSessionResetKillSwitch = "ios.automaticSessionResetKillSwitch"
    case paymentsResetKillSwitch = "ios.paymentsResetKillSwitch"
    case messageResendKillSwitch = "ios.messageResendKillSwitch"
    case applePayOneTimeDonationKillSwitch = "ios.applePayOneTimeDonationKillSwitch"
    case applePayGiftDonationKillSwitch = "ios.applePayGiftDonationKillSwitch"
    case applePayMonthlyDonationKillSwitch = "ios.applePayMonthlyDonationKillSwitch"
    case cardOneTimeDonationKillSwitch = "ios.cardOneTimeDonationKillSwitch"
    case cardGiftDonationKillSwitch = "ios.cardGiftDonationKillSwitch"
    case cardMonthlyDonationKillSwitch = "ios.cardMonthlyDonationKillSwitch"
    case paypalOneTimeDonationKillSwitch = "ios.paypalOneTimeDonationKillSwitch"
    case paypalGiftDonationKillSwitch = "ios.paypalGiftDonationKillSwitch"
    case paypalMonthlyDonationKillSwitch = "ios.paypalMonthlyDonationKillSwitch"
    case enableAutoAPNSRotation = "ios.enableAutoAPNSRotation"
    case ringrtcNwPathMonitorTrialKillSwitch = "ios.ringrtcNwPathMonitorTrialKillSwitch"
    case cdsDisableCompatibilityMode = "cds.disableCompatibilityMode"
    case canDonateWithSepa = "ios.canDonateWithSepa"

    var isSticky: Bool {
        switch self {
        case .automaticSessionResetKillSwitch: fallthrough
        case .paymentsResetKillSwitch: fallthrough
        case .messageResendKillSwitch: fallthrough
        case .applePayOneTimeDonationKillSwitch: fallthrough
        case .applePayGiftDonationKillSwitch: fallthrough
        case .applePayMonthlyDonationKillSwitch: fallthrough
        case .cardOneTimeDonationKillSwitch: fallthrough
        case .cardGiftDonationKillSwitch: fallthrough
        case .cardMonthlyDonationKillSwitch: fallthrough
        case .paypalOneTimeDonationKillSwitch: fallthrough
        case .paypalGiftDonationKillSwitch: fallthrough
        case .paypalMonthlyDonationKillSwitch: fallthrough
        case .enableAutoAPNSRotation: fallthrough
        case .ringrtcNwPathMonitorTrialKillSwitch: fallthrough
        case .cdsDisableCompatibilityMode: fallthrough
        case .canDonateWithSepa:
            return false
        }
    }
    var isHotSwappable: Bool {
        switch self {
        case .automaticSessionResetKillSwitch: fallthrough
        case .paymentsResetKillSwitch: fallthrough
        case .messageResendKillSwitch: fallthrough
        case .applePayOneTimeDonationKillSwitch: fallthrough
        case .applePayGiftDonationKillSwitch: fallthrough
        case .applePayMonthlyDonationKillSwitch: fallthrough
        case .cardOneTimeDonationKillSwitch: fallthrough
        case .cardGiftDonationKillSwitch: fallthrough
        case .cardMonthlyDonationKillSwitch: fallthrough
        case .paypalOneTimeDonationKillSwitch: fallthrough
        case .paypalGiftDonationKillSwitch: fallthrough
        case .paypalMonthlyDonationKillSwitch: fallthrough
        case .enableAutoAPNSRotation: fallthrough
        case .ringrtcNwPathMonitorTrialKillSwitch: fallthrough
        case .cdsDisableCompatibilityMode: fallthrough
        case .canDonateWithSepa:
            return false
        }
    }
}

private enum ValueFlag: String, FlagType {
    case groupsV2MaxGroupSizeRecommended = "global.groupsv2.maxGroupSize"
    case groupsV2MaxGroupSizeHardLimit = "global.groupsv2.groupSizeHardLimit"
    case clientExpiration = "ios.clientExpiration"
    case cdsSyncInterval = "cds.syncInterval.seconds"
    case automaticSessionResetAttemptInterval = "ios.automaticSessionResetAttemptInterval"
    case reactiveProfileKeyAttemptInterval = "ios.reactiveProfileKeyAttemptInterval"
    case standardMediaQualityLevel = "ios.standardMediaQualityLevel"
    case replaceableInteractionExpiration = "ios.replaceableInteractionExpiration"
    case messageSendLogEntryLifetime = "ios.messageSendLogEntryLifetime"
    case paymentsDisabledRegions = "global.payments.disabledRegions"
    case applePayDisabledRegions = "global.donations.apayDisabledRegions"
    case creditAndDebitCardDisabledRegions = "global.donations.ccDisabledRegions"
    case paypalDisabledRegions = "global.donations.paypalDisabledRegions"
    case sepaEnabledRegions = "global.donations.sepaEnabledRegions"
    case maxGroupCallRingSize = "global.calling.maxGroupCallRingSize"
    case minNicknameLength = "global.nicknames.min"
    case maxNicknameLength = "global.nicknames.max"
    case maxAttachmentDownloadSizeBytes = "global.attachments.maxBytes"

    var isSticky: Bool {
        switch self {
        case .groupsV2MaxGroupSizeRecommended: fallthrough
        case .groupsV2MaxGroupSizeHardLimit:
            return true

        case .clientExpiration: fallthrough
        case .cdsSyncInterval: fallthrough
        case .automaticSessionResetAttemptInterval: fallthrough
        case .reactiveProfileKeyAttemptInterval: fallthrough
        case .standardMediaQualityLevel: fallthrough
        case .replaceableInteractionExpiration: fallthrough
        case .messageSendLogEntryLifetime: fallthrough
        case .paymentsDisabledRegions: fallthrough
        case .applePayDisabledRegions: fallthrough
        case .creditAndDebitCardDisabledRegions: fallthrough
        case .paypalDisabledRegions: fallthrough
        case .sepaEnabledRegions: fallthrough
        case .maxGroupCallRingSize: fallthrough
        case .minNicknameLength: fallthrough
        case .maxNicknameLength: fallthrough
        case .maxAttachmentDownloadSizeBytes:
            return false
        }
    }

    var isHotSwappable: Bool {
        switch self {
        case .groupsV2MaxGroupSizeRecommended: fallthrough
        case .groupsV2MaxGroupSizeHardLimit: fallthrough
        case .automaticSessionResetAttemptInterval: fallthrough
        case .reactiveProfileKeyAttemptInterval: fallthrough
        case .paymentsDisabledRegions: fallthrough
        case .applePayDisabledRegions: fallthrough
        case .creditAndDebitCardDisabledRegions: fallthrough
        case .paypalDisabledRegions: fallthrough
        case .sepaEnabledRegions: fallthrough
        case .maxGroupCallRingSize:
            return true

        case .clientExpiration: fallthrough
        case .cdsSyncInterval: fallthrough
        case .standardMediaQualityLevel: fallthrough
        case .replaceableInteractionExpiration: fallthrough
        case .messageSendLogEntryLifetime: fallthrough
        case .minNicknameLength: fallthrough
        case .maxNicknameLength: fallthrough
        case .maxAttachmentDownloadSizeBytes:
            return false
        }
    }
}

private enum TimeGatedFlag: String, FlagType {
    case __none

    var isSticky: Bool {
        switch self {
        case .__none:
            return false
        }
    }

    var isHotSwappable: Bool {
        // These flags are time-gated. This means they are hot-swappable by
        // default. Even if we don't fetch a fresh remote config, we may cross the
        // time threshold while the app is in memory, updating the value from false
        // to true. As such we'll also hot swap every time gated flag.
        return true
    }
}

// MARK: -

private protocol FlagType: CaseIterable {
    // Values defined in this array remain set once they are set regardless of
    // the remote state.
    var isSticky: Bool { get }

    // Values defined in this array will update while the app is running, as
    // soon as we fetch an update to the remote config. They will not wait for
    // an app restart.
    var isHotSwappable: Bool { get }
}

// MARK: -

public protocol RemoteConfigManager {
    func warmCaches()
    var cachedConfig: RemoteConfig? { get }
    func refresh(account: AuthedAccount) -> Promise<RemoteConfig>
}

// MARK: -

#if TESTABLE_BUILD

public class StubbableRemoteConfigManager: RemoteConfigManager {
    public var cachedConfig: RemoteConfig?

    public func warmCaches() {}

    public func refresh(account: AuthedAccount) -> Promise<RemoteConfig> {
        return .value(cachedConfig!)
    }
}

#endif

// MARK: -

public class RemoteConfigManagerImpl: RemoteConfigManager {
    private let appExpiry: AppExpiry
    private let db: DB
    private let keyValueStore: KeyValueStore
    private let tsAccountManager: TSAccountManager
    private let serviceClient: SignalServiceClient

    // MARK: -

    private let _cachedConfig = AtomicValue<RemoteConfig?>(nil, lock: AtomicLock())
    public var cachedConfig: RemoteConfig? {
        let result = _cachedConfig.get()
        owsAssertDebug(result != nil, "cachedConfig not yet set.")
        return result
    }
    @discardableResult
    private func updateCachedConfig(_ updateBlock: (RemoteConfig?) -> RemoteConfig) -> RemoteConfig {
        return _cachedConfig.update { mutableValue in
            let newValue = updateBlock(mutableValue)
            mutableValue = newValue
            return newValue
        }
    }

    public init(
        appExpiry: AppExpiry,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        tsAccountManager: TSAccountManager,
        serviceClient: SignalServiceClient
    ) {
        self.appExpiry = appExpiry
        self.db = db
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "RemoteConfigManager")
        self.tsAccountManager = tsAccountManager
        self.serviceClient = serviceClient

        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            guard self.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                return
            }
            self.scheduleNextRefresh()
        }

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

        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else { return }
        Logger.info("Refreshing and immediately applying new flags due to new registration.")
        refresh().catch { error in
            Logger.error("Failed to update remote config after registration change \(error)")
        }
    }

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        // swiftlint:disable large_tuple
        let (
            lastKnownClockSkew,
            isEnabledFlags,
            valueFlags,
            timeGatedFlags,
            registrationState
        ): (TimeInterval, [String: Bool]?, [String: String]?, [String: Date]?, TSRegistrationState) = db.read { tx in
            return (
                self.keyValueStore.getLastKnownClockSkew(transaction: tx),
                self.keyValueStore.getRemoteConfigIsEnabledFlags(transaction: tx),
                self.keyValueStore.getRemoteConfigValueFlags(transaction: tx),
                self.keyValueStore.getRemoteConfigTimeGatedFlags(transaction: tx),
                DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx)
            )
        }
        // swiftlint:enable large_tuple
        let remoteConfig: RemoteConfig
        if registrationState.isRegistered, (isEnabledFlags != nil || valueFlags != nil || timeGatedFlags != nil) {
            remoteConfig = RemoteConfig(
                clockSkew: lastKnownClockSkew,
                isEnabledFlags: isEnabledFlags ?? [:],
                valueFlags: valueFlags ?? [:],
                timeGatedFlags: timeGatedFlags ?? [:]
            )
        } else {
            // If we're not registered or haven't saved one, use an empty one.
            remoteConfig = .emptyConfig
        }
        updateCachedConfig { _ in remoteConfig }
        warmSecondaryCaches(valueFlags: valueFlags ?? [:])

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            RemoteConfig.logFlags()
        }
    }

    fileprivate func warmSecondaryCaches(valueFlags: [String: String]) {
        checkClientExpiration(valueFlags: valueFlags)
    }

    private static let refreshInterval = 2 * kHourInterval
    private var refreshTimer: Timer?

    private var lastAttempt: Date = .distantPast
    private var consecutiveFailures: UInt = 0
    private var nextPermittedAttempt: Date {
        AssertIsOnMainThread()
        let backoffDelay = OWSOperation.retryIntervalForExponentialBackoff(failureCount: consecutiveFailures)
        let earliestPermittedAttempt = lastAttempt.addingTimeInterval(backoffDelay)

        let lastSuccess = db.read { keyValueStore.getLastFetched(transaction: $0) }
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

    @discardableResult
    public func refresh(account: AuthedAccount = .implicit()) -> Promise<RemoteConfig> {
        AssertIsOnMainThread()
        Logger.info("Refreshing remote config.")
        lastAttempt = Date()

        let promise = firstly(on: DispatchQueue.global()) {
            self.serviceClient.getRemoteConfig(auth: account.chatServiceAuth)
        }.map(on: DispatchQueue.global()) { (fetchedConfig: RemoteConfigResponse) in

            let clockSkew: TimeInterval
            if let serverEpochTimeSeconds = fetchedConfig.serverEpochTimeSeconds {
                let dateAccordingToServer = Date(timeIntervalSince1970: TimeInterval(serverEpochTimeSeconds))
                clockSkew = dateAccordingToServer.timeIntervalSince(Date())
            } else {
                clockSkew = 0
            }

            // We filter the received config down to just the supported flags. This
            // ensures if we have a sticky flag, it doesn't get inadvertently set
            // because we cached a value before it went public. e.g. if we set a sticky
            // flag to 100% in beta then turn it back to 0% before going to production.
            var isEnabledFlags = [String: Bool]()
            var valueFlags = [String: String]()
            var timeGatedFlags = [String: Date]()
            fetchedConfig.items.forEach { (key: String, item: RemoteConfigItem) in
                switch item {
                case .isEnabled(let isEnabled):
                    if IsEnabledFlag(rawValue: key) != nil {
                        isEnabledFlags[key] = isEnabled
                    }
                case .value(let value):
                    if ValueFlag(rawValue: key) != nil {
                        valueFlags[key] = value
                    } else if TimeGatedFlag(rawValue: key) != nil {
                        if let secondsSinceEpoch = TimeInterval(value) {
                            timeGatedFlags[key] = Date(timeIntervalSince1970: secondsSinceEpoch)
                        } else {
                            owsFailDebug("Invalid value: \(value) \(type(of: value))")
                        }
                    }
                }
            }

            // Persist all flags in the database to be applied on next launch.

            self.db.write { transaction in
                // Preserve any sticky flags.
                if let existingConfig = self.keyValueStore.getRemoteConfigIsEnabledFlags(transaction: transaction) {
                    existingConfig.forEach { (key: String, value: Bool) in
                        // Preserve "is enabled" flags if they are sticky and already set.
                        if let flag = IsEnabledFlag(rawValue: key), flag.isSticky, value == true {
                            isEnabledFlags[key] = value
                        }
                    }
                }
                if let existingConfig = self.keyValueStore.getRemoteConfigValueFlags(transaction: transaction) {
                    existingConfig.forEach { (key: String, value: String) in
                        // Preserve "value" flags if they are sticky and already set and missing
                        // from the fetched config.
                        if let flag = ValueFlag(rawValue: key), flag.isSticky, valueFlags[key] == nil {
                            valueFlags[key] = value
                        }
                    }
                }
                if let existingConfig = self.keyValueStore.getRemoteConfigTimeGatedFlags(transaction: transaction) {
                    existingConfig.forEach { (key: String, value: Date) in
                        // Preserve "time gated" flags if they are sticky and already set and
                        // missing from the fetched config.
                        if let flag = TimeGatedFlag(rawValue: key), flag.isSticky, timeGatedFlags[key] == nil {
                            timeGatedFlags[key] = value
                        }
                    }
                }

                self.keyValueStore.setClockSkew(clockSkew, transaction: transaction)
                self.keyValueStore.setRemoteConfigIsEnabledFlags(isEnabledFlags, transaction: transaction)
                self.keyValueStore.setRemoteConfigValueFlags(valueFlags, transaction: transaction)
                self.keyValueStore.setRemoteConfigTimeGatedFlags(timeGatedFlags, transaction: transaction)
                self.keyValueStore.setLastFetched(Date(), transaction: transaction)

                self.checkClientExpiration(valueFlags: valueFlags)
            }

            // As a special case, persist RingRTC field trials. See comments in
            // ``RingrtcFieldTrials`` for details.
            RingrtcFieldTrials.saveNwPathMonitorTrialState(
                isEnabled: {
                    let flag = IsEnabledFlag.ringrtcNwPathMonitorTrialKillSwitch
                    let isKilled = isEnabledFlags[flag.rawValue] ?? false
                    return !isKilled
                }(),
                in: CurrentAppContext().appUserDefaults()
            )

            self.consecutiveFailures = 0

            // This has *all* the new values, even those that can't be hot-swapped.
            let newConfig = RemoteConfig(
                clockSkew: clockSkew,
                isEnabledFlags: isEnabledFlags,
                valueFlags: valueFlags,
                timeGatedFlags: timeGatedFlags
            )

            // This has hot-swappable new values and non-hot-swappable old values.
            let mergedConfig = self.updateCachedConfig { oldConfig in
                return (oldConfig ?? .emptyConfig).mergingHotSwappableFlags(from: newConfig)
            }
            self.warmSecondaryCaches(valueFlags: mergedConfig.valueFlags)

            // We always return `newConfig` because callers may want to see the
            // newly-fetched, non-hot-swappable values for themselves.
            return newConfig
        }

        promise.catch(on: DispatchQueue.main) { error in
            Logger.error("error: \(error)")
            self.consecutiveFailures += 1
        }.ensure(on: DispatchQueue.main) {
            self.scheduleNextRefresh()
        }.cauterize()

        return promise
    }

    // MARK: - Client Expiration

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
            // We filter things like look like an ip address, but we don't want to
            // filter the version string so we replace the dots before logging.
            return "<MinimumVersion: \(string.replacingOccurrences(of: ".", with: "_")), \(enforcementDate)>"
        }
    }

    private func checkClientExpiration(valueFlags: [String: String]) {
        var minimumVersions: [MinimumVersion]?
        defer {
            if let minimumVersions {
                appExpiry.setExpirationDateForCurrentVersion(remoteExpirationDate(minimumVersions: minimumVersions), db: db)
            }
        }

        guard let jsonString = valueFlags[ValueFlag.clientExpiration.rawValue] else {
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
                // remote config is in some way invalid. Probably, someone typoed a key. We
                // don't want to ignore all client expiration because one value was wrong,
                // so we just throw away that specific minimum version.
                guard let string = decodedValue.string, let enforcementDate = decodedValue.enforcementDate else {
                    owsFailDebug("Received improperly formatted clientExpiration: \(jsonString)")
                    return nil
                }

                // The version should always be a complete long version (eg 3.16.0.1). If
                // it's not, we throw it away but still make sure to maintain all the valid
                // minimum versions we received.
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
        let currentVersion4 = AppVersionImpl.shared.currentAppVersion4
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

private extension KeyValueStore {

    // MARK: - Remote Config Enabled Flags

    private static var remoteConfigIsEnabledFlagsKey: String { "remoteConfigKey" }

    func getRemoteConfigIsEnabledFlags(transaction: DBReadTransaction) -> [String: Bool]? {
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

    func setRemoteConfigIsEnabledFlags(_ newValue: [String: Bool], transaction: DBWriteTransaction) {
        return setObject(newValue,
                         key: Self.remoteConfigIsEnabledFlagsKey,
                         transaction: transaction)
    }

    // MARK: - Remote Config Value Flags

    private static var remoteConfigValueFlagsKey: String { "remoteConfigValueFlags" }

    func getRemoteConfigValueFlags(transaction: DBReadTransaction) -> [String: String]? {
        guard let object = getObject(forKey: Self.remoteConfigValueFlagsKey, transaction: transaction) else {
            return nil
        }

        guard let remoteConfig = object as? [String: String] else {
            owsFailDebug("unexpected object: \(object)")
            return nil
        }

        return remoteConfig
    }

    func setRemoteConfigValueFlags(_ newValue: [String: String], transaction: DBWriteTransaction) {
        return setObject(newValue, key: Self.remoteConfigValueFlagsKey, transaction: transaction)
    }

    // MARK: - Remote Config Time Gated Flags

    private static var remoteConfigTimeGatedFlagsKey: String { "remoteConfigTimeGatedFlags" }

    func getRemoteConfigTimeGatedFlags(transaction: DBReadTransaction) -> [String: Date]? {
        guard let object = getObject(forKey: Self.remoteConfigTimeGatedFlagsKey, transaction: transaction) else {
            return nil
        }

        guard let remoteConfig = object as? [String: Date] else {
            owsFailDebug("unexpected object: \(object)")
            return nil
        }

        return remoteConfig
    }

    func setRemoteConfigTimeGatedFlags(_ newValue: [String: Date], transaction: DBWriteTransaction) {
        return setObject(newValue, key: Self.remoteConfigTimeGatedFlagsKey, transaction: transaction)
    }

    // MARK: - Last Fetched

    var lastFetchedKey: String { "lastFetchedKey" }

    func getLastFetched(transaction: DBReadTransaction) -> Date? {
        return getDate(lastFetchedKey, transaction: transaction)
    }

    func setLastFetched(_ newValue: Date, transaction: DBWriteTransaction) {
        return setDate(newValue, key: lastFetchedKey, transaction: transaction)
    }

    // MARK: - Clock Skew

    var clockSkewKey: String { "clockSkewKey" }

    func getLastKnownClockSkew(transaction: DBReadTransaction) -> TimeInterval {
        return getDouble(clockSkewKey, defaultValue: 0, transaction: transaction)
    }

    func setClockSkew(_ newValue: TimeInterval, transaction: DBWriteTransaction) {
        return setDouble(newValue, key: clockSkewKey, transaction: transaction)
    }
}
