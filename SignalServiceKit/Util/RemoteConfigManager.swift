//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import LibSignalClient

public class RemoteConfig {

    public static var current: RemoteConfig {
        return SSKEnvironment.shared.remoteConfigManagerRef.currentConfig()
    }

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

    public let paymentsDisabledRegions: PhoneNumberRegions
    public let applePayDisabledRegions: PhoneNumberRegions
    public let creditAndDebitCardDisabledRegions: PhoneNumberRegions
    public let paypalDisabledRegions: PhoneNumberRegions
    public let sepaEnabledRegions: PhoneNumberRegions
    public let idealEnabledRegions: PhoneNumberRegions

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
        self.idealEnabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .idealEnabledRegions)
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

    public var groupsV2MaxGroupSizeRecommended: UInt {
        getUIntValue(forFlag: .groupsV2MaxGroupSizeRecommended, defaultValue: 151)
    }

    public var groupsV2MaxGroupSizeHardLimit: UInt {
        getUIntValue(forFlag: .groupsV2MaxGroupSizeHardLimit, defaultValue: 1001)
    }

    public var groupsV2MaxBannedMembers: UInt {
        groupsV2MaxGroupSizeHardLimit
    }

    public var cdsSyncInterval: TimeInterval {
        interval(.cdsSyncInterval, defaultInterval: kDayInterval * 2)
    }

    public var automaticSessionResetKillSwitch: Bool {
        return isEnabled(.automaticSessionResetKillSwitch)
    }

    public var automaticSessionResetAttemptInterval: TimeInterval {
        interval(.automaticSessionResetAttemptInterval, defaultInterval: kHourInterval)
    }

    public var reactiveProfileKeyAttemptInterval: TimeInterval {
        interval(.reactiveProfileKeyAttemptInterval, defaultInterval: kHourInterval)
    }

    public var paymentsResetKillSwitch: Bool {
        isEnabled(.paymentsResetKillSwitch)
    }

    public var canDonateOneTimeWithApplePay: Bool {
        !isEnabled(.applePayOneTimeDonationKillSwitch)
    }

    public var canDonateGiftWithApplePay: Bool {
        !isEnabled(.applePayGiftDonationKillSwitch)
    }

    public var canDonateMonthlyWithApplePay: Bool {
        !isEnabled(.applePayMonthlyDonationKillSwitch)
    }

    public var canDonateOneTimeWithCreditOrDebitCard: Bool {
        !isEnabled(.cardOneTimeDonationKillSwitch)
    }

    public var canDonateGiftWithCreditOrDebitCard: Bool {
        !isEnabled(.cardGiftDonationKillSwitch)
    }

    public var canDonateMonthlyWithCreditOrDebitCard: Bool {
        !isEnabled(.cardMonthlyDonationKillSwitch)
    }

    public var canDonateOneTimeWithPaypal: Bool {
        !isEnabled(.paypalOneTimeDonationKillSwitch)
    }

    public var canDonateGiftWithPayPal: Bool {
        !isEnabled(.paypalGiftDonationKillSwitch)
    }

    public var canDonateMonthlyWithPaypal: Bool {
        !isEnabled(.paypalMonthlyDonationKillSwitch)
    }

    public func standardMediaQualityLevel(localPhoneNumber: String?) -> ImageQualityLevel? {
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

    public var messageResendKillSwitch: Bool {
        isEnabled(.messageResendKillSwitch)
    }

    public var replaceableInteractionExpiration: TimeInterval {
        interval(.replaceableInteractionExpiration, defaultInterval: kHourInterval)
    }

    public var messageSendLogEntryLifetime: TimeInterval {
        interval(.messageSendLogEntryLifetime, defaultInterval: 2 * kWeekInterval)
    }

    public var maxSenderKeyAge: TimeInterval {
        return Double(getStringConvertibleValue(forFlag: .maxSenderKeyAge, defaultValue: 2 * kWeekInMs)) / 1000
    }

    public var maxGroupCallRingSize: UInt {
        getUIntValue(forFlag: .maxGroupCallRingSize, defaultValue: 16)
    }

    public var enableAutoAPNSRotation: Bool {
        return isEnabled(.enableAutoAPNSRotation, defaultValue: false)
    }

    /// The minimum length for a valid nickname, in Unicode codepoints.
    public var minNicknameLength: UInt32 {
        getUInt32Value(forFlag: .minNicknameLength, defaultValue: 3)
    }

    /// The maximum length for a valid nickname, in Unicode codepoints.
    public var maxNicknameLength: UInt32 {
        getUInt32Value(forFlag: .maxNicknameLength, defaultValue: 32)
    }

    public var maxAttachmentDownloadSizeBytes: UInt {
        return getUIntValue(forFlag: .maxAttachmentDownloadSizeBytes, defaultValue: 100 * 1024 * 1024)
    }

    // Hardcoded value (but lives alongside `maxAttachmentDownloadSizeBytes`).
    public var maxMediaTierThumbnailDownloadSizeBytes: UInt = 1024 * 8

    public var enableGifSearch: Bool {
        return isEnabled(.enableGifSearch, defaultValue: true)
    }

    public var shouldCheckForServiceExtensionFailures: Bool {
        return !isEnabled(.serviceExtensionFailureKillSwitch)
    }

    public var backgroundRefreshInterval: TimeInterval {
        return TimeInterval(getUIntValue(
            forFlag: .backgroundRefreshInterval,
            defaultValue: UInt(kDayInterval)
        ))
    }

    @available(*, unavailable, message: "cached in UserDefaults by ChatConnectionManager")
    public var experimentalTransportUseLibsignal: Bool {
        return false
    }

    public var experimentalTransportShadowingHigh: Bool {
        return isEnabled(.experimentalTransportShadowingHigh, defaultValue: false)
    }

    @available(*, unavailable, message: "cached in UserDefaults by ChatConnectionManager")
    public var experimentalTransportShadowingEnabled: Bool {
        return false
    }

    public var messageQueueTime: TimeInterval {
        return interval(.messageQueueTimeInSeconds, defaultInterval: 45 * kDayInterval)
    }

    public var messageQueueTimeMs: UInt64 {
        return UInt64(messageQueueTime * Double(MSEC_PER_SEC))
    }

    public var shouldRunTSAttachmentMigrationInBGProcessingTask: Bool {
        return !isEnabled(.tsAttachmentMigrationBGProcessingTaskKillSwitch)
    }

    public var shouldRunTSAttachmentMigrationInMainAppBackground: Bool {
        return !isEnabled(.tsAttachmentMigrationMainAppBackgroundKillSwitch)
    }

    // MARK: UInt values

    private func getUIntValue(
        forFlag flag: ValueFlag,
        defaultValue: UInt
    ) -> UInt {
        getStringConvertibleValue(
            forFlag: flag,
            defaultValue: defaultValue
        )
    }

    private func getUInt32Value(
        forFlag flag: ValueFlag,
        defaultValue: UInt32
    ) -> UInt32 {
        getStringConvertibleValue(
            forFlag: flag,
            defaultValue: defaultValue
        )
    }

    private func getStringConvertibleValue<V>(
        forFlag flag: ValueFlag,
        defaultValue: V
    ) -> V where V: LosslessStringConvertible {
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
        let callingCodeToValueMap = csvString
            .components(separatedBy: ",")
            .reduce(into: [String: String]()) { result, value in
                let components = value.components(separatedBy: ":")
                guard components.count == 2 else { return owsFailDebug("Invalid \(csvDescription) value \(value)") }
                let callingCode = components[0]
                let countryValue = components[1]
                result[callingCode] = countryValue
            }

        guard !callingCodeToValueMap.isEmpty else { return nil }

        guard
            let localPhoneNumber,
            let localCallingCode = SSKEnvironment.shared.phoneNumberUtilRef.parseE164(localPhoneNumber)?.getCallingCode()
        else {
            owsFailDebug("Invalid local number")
            return nil
        }

        return callingCodeToValueMap[String(localCallingCode)] ?? callingCodeToValueMap["*"]
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

        let hash = Data(SHA256.hash(data: data))
        guard hash.count == 32 else {
            owsFailDebug("Hash has incorrect length \(hash.count)")
            return 0
        }

        // uuid_bucket = UINT64_FROM_FIRST_8_BYTES_BIG_ENDIAN(SHA256(rawFlag + "." + uuidBytes)) % bucketSize
        return UInt64(bigEndianData: hash.prefix(8))! % bucketSize
    }

    // MARK: -

    private func interval(_ flag: ValueFlag, defaultInterval: TimeInterval) -> TimeInterval {
        guard let intervalString: String = value(flag), let interval = TimeInterval(intervalString) else {
            return defaultInterval
        }
        return interval
    }

    private func isEnabled(_ flag: IsEnabledFlag, defaultValue: Bool = false) -> Bool {
        return isEnabledFlags[flag.rawValue] ?? defaultValue
    }

    private func isEnabled(_ flag: TimeGatedFlag, defaultValue: Bool = false) -> Bool {
        guard let dateThreshold = timeGatedFlags[flag.rawValue] else {
            return defaultValue
        }
        let correctedDate = Date().addingTimeInterval(self.lastKnownClockSkew)
        return correctedDate >= dateThreshold
    }

    private func value(_ flag: ValueFlag) -> String? {
        return valueFlags[flag.rawValue]
    }

    public func debugDescriptions() -> [String: String] {
        var result = [String: String]()
        for (key, value) in isEnabledFlags {
            result[key] = "\(value)"
        }
        for (key, value) in valueFlags {
            result[key] = "\(value)"
        }
        for (key, value) in timeGatedFlags {
            result[key] = "\(value)"
        }
        return result
    }

    public func logFlags() {
        for (key, value) in debugDescriptions() {
            Logger.info("RemoteConfig: \(key) = \(value)")
        }
    }
}

// MARK: - IsEnabledFlag

private enum IsEnabledFlag: String, FlagType {
    case applePayGiftDonationKillSwitch = "ios.applePayGiftDonationKillSwitch"
    case applePayMonthlyDonationKillSwitch = "ios.applePayMonthlyDonationKillSwitch"
    case applePayOneTimeDonationKillSwitch = "ios.applePayOneTimeDonationKillSwitch"
    case automaticSessionResetKillSwitch = "ios.automaticSessionResetKillSwitch"
    case cardGiftDonationKillSwitch = "ios.cardGiftDonationKillSwitch"
    case cardMonthlyDonationKillSwitch = "ios.cardMonthlyDonationKillSwitch"
    case cardOneTimeDonationKillSwitch = "ios.cardOneTimeDonationKillSwitch"
    case deleteForMeSyncMessageSending = "ios.deleteForMeSyncMessage.sending"
    case enableAutoAPNSRotation = "ios.enableAutoAPNSRotation"
    case enableGifSearch = "global.gifSearch"
    case experimentalTransportShadowingEnabled = "ios.experimentalTransportEnabled.shadowing"
    case experimentalTransportShadowingHigh = "ios.experimentalTransportEnabled.shadowingHigh"
    case experimentalTransportUseLibsignal = "ios.experimentalTransportEnabled.libsignal"
    case experimentalTransportUseLibsignalAuth = "ios.experimentalTransportEnabled.libsignalAuth"
    case messageResendKillSwitch = "ios.messageResendKillSwitch"
    case paymentsResetKillSwitch = "ios.paymentsResetKillSwitch"
    case paypalGiftDonationKillSwitch = "ios.paypalGiftDonationKillSwitch"
    case paypalMonthlyDonationKillSwitch = "ios.paypalMonthlyDonationKillSwitch"
    case paypalOneTimeDonationKillSwitch = "ios.paypalOneTimeDonationKillSwitch"
    case ringrtcNwPathMonitorTrialKillSwitch = "ios.ringrtcNwPathMonitorTrialKillSwitch"
    case serviceExtensionFailureKillSwitch = "ios.serviceExtensionFailureKillSwitch"
    case tsAttachmentMigrationMainAppBackgroundKillSwitch = "ios.tsAttachmentMigrationMainAppBackgroundKillSwitch"
    case tsAttachmentMigrationBGProcessingTaskKillSwitch = "ios.tsAttachmentMigrationBGProcessingTaskKillSwitch"

    var isSticky: Bool {
        switch self {
        case .applePayGiftDonationKillSwitch: false
        case .applePayMonthlyDonationKillSwitch: false
        case .applePayOneTimeDonationKillSwitch: false
        case .automaticSessionResetKillSwitch: false
        case .cardGiftDonationKillSwitch: false
        case .cardMonthlyDonationKillSwitch: false
        case .cardOneTimeDonationKillSwitch: false
        case .deleteForMeSyncMessageSending: false
        case .enableAutoAPNSRotation: false
        case .enableGifSearch: false
        case .experimentalTransportShadowingEnabled: false
        case .experimentalTransportShadowingHigh: false
        case .experimentalTransportUseLibsignal: false
        case .experimentalTransportUseLibsignalAuth: false
        case .messageResendKillSwitch: false
        case .paymentsResetKillSwitch: false
        case .paypalGiftDonationKillSwitch: false
        case .paypalMonthlyDonationKillSwitch: false
        case .paypalOneTimeDonationKillSwitch: false
        case .ringrtcNwPathMonitorTrialKillSwitch: false
        case .serviceExtensionFailureKillSwitch: false
        case .tsAttachmentMigrationMainAppBackgroundKillSwitch: false
        case .tsAttachmentMigrationBGProcessingTaskKillSwitch: false
        }
    }
    var isHotSwappable: Bool {
        switch self {
        case .applePayGiftDonationKillSwitch: false
        case .applePayMonthlyDonationKillSwitch: false
        case .applePayOneTimeDonationKillSwitch: false
        case .automaticSessionResetKillSwitch: false
        case .cardGiftDonationKillSwitch: false
        case .cardMonthlyDonationKillSwitch: false
        case .cardOneTimeDonationKillSwitch: false
        case .deleteForMeSyncMessageSending: false
        case .enableAutoAPNSRotation: false
        case .enableGifSearch: false
        case .experimentalTransportShadowingEnabled: false
        case .experimentalTransportShadowingHigh: false
        case .experimentalTransportUseLibsignal: false
        case .experimentalTransportUseLibsignalAuth: false
        case .messageResendKillSwitch: false
        case .paymentsResetKillSwitch: false
        case .paypalGiftDonationKillSwitch: false
        case .paypalMonthlyDonationKillSwitch: false
        case .paypalOneTimeDonationKillSwitch: false
        case .ringrtcNwPathMonitorTrialKillSwitch: false
        case .serviceExtensionFailureKillSwitch: true
        case .tsAttachmentMigrationMainAppBackgroundKillSwitch: true
        case .tsAttachmentMigrationBGProcessingTaskKillSwitch: true
        }
    }
}

private enum ValueFlag: String, FlagType {
    case applePayDisabledRegions = "global.donations.apayDisabledRegions"
    case automaticSessionResetAttemptInterval = "ios.automaticSessionResetAttemptInterval"
    case backgroundRefreshInterval = "ios.backgroundRefreshInterval"
    case cdsSyncInterval = "cds.syncInterval.seconds"
    case clientExpiration = "ios.clientExpiration"
    case creditAndDebitCardDisabledRegions = "global.donations.ccDisabledRegions"
    case groupsV2MaxGroupSizeHardLimit = "global.groupsv2.groupSizeHardLimit"
    case groupsV2MaxGroupSizeRecommended = "global.groupsv2.maxGroupSize"
    case idealEnabledRegions = "global.donations.idealEnabledRegions"
    case maxAttachmentDownloadSizeBytes = "global.attachments.maxBytes"
    case maxGroupCallRingSize = "global.calling.maxGroupCallRingSize"
    case maxNicknameLength = "global.nicknames.max"
    case maxSenderKeyAge = "ios.maxSenderKeyAge"
    case messageQueueTimeInSeconds = "global.messageQueueTimeInSeconds"
    case messageSendLogEntryLifetime = "ios.messageSendLogEntryLifetime"
    case minNicknameLength = "global.nicknames.min"
    case paymentsDisabledRegions = "global.payments.disabledRegions"
    case paypalDisabledRegions = "global.donations.paypalDisabledRegions"
    case reactiveProfileKeyAttemptInterval = "ios.reactiveProfileKeyAttemptInterval"
    case replaceableInteractionExpiration = "ios.replaceableInteractionExpiration"
    case sepaEnabledRegions = "global.donations.sepaEnabledRegions"
    case standardMediaQualityLevel = "ios.standardMediaQualityLevel"

    var isSticky: Bool {
        switch self {
        case .applePayDisabledRegions: false
        case .automaticSessionResetAttemptInterval: false
        case .backgroundRefreshInterval: false
        case .cdsSyncInterval: false
        case .clientExpiration: false
        case .creditAndDebitCardDisabledRegions: false
        case .groupsV2MaxGroupSizeHardLimit: true
        case .groupsV2MaxGroupSizeRecommended: true
        case .idealEnabledRegions: false
        case .maxAttachmentDownloadSizeBytes: false
        case .maxGroupCallRingSize: false
        case .maxNicknameLength: false
        case .maxSenderKeyAge: false
        case .messageQueueTimeInSeconds: false
        case .messageSendLogEntryLifetime: false
        case .minNicknameLength: false
        case .paymentsDisabledRegions: false
        case .paypalDisabledRegions: false
        case .reactiveProfileKeyAttemptInterval: false
        case .replaceableInteractionExpiration: false
        case .sepaEnabledRegions: false
        case .standardMediaQualityLevel: false
        }
    }

    var isHotSwappable: Bool {
        switch self {
        case .applePayDisabledRegions: true
        case .automaticSessionResetAttemptInterval: true
        case .backgroundRefreshInterval: true
        case .cdsSyncInterval: false
        case .clientExpiration: false
        case .creditAndDebitCardDisabledRegions: true
        case .groupsV2MaxGroupSizeHardLimit: true
        case .groupsV2MaxGroupSizeRecommended: true
        case .idealEnabledRegions: true
        case .maxAttachmentDownloadSizeBytes: false
        case .maxGroupCallRingSize: true
        case .maxNicknameLength: false
        case .maxSenderKeyAge: true
        case .messageQueueTimeInSeconds: false
        case .messageSendLogEntryLifetime: false
        case .minNicknameLength: false
        case .paymentsDisabledRegions: true
        case .paypalDisabledRegions: true
        case .reactiveProfileKeyAttemptInterval: true
        case .replaceableInteractionExpiration: false
        case .sepaEnabledRegions: true
        case .standardMediaQualityLevel: false
        }
    }
}

private enum TimeGatedFlag: String, FlagType {
    case __none

    var isSticky: Bool {
        switch self {
        case .__none: false
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

public protocol RemoteConfigProvider {
    func currentConfig() -> RemoteConfig
}

// MARK: -

#if TESTABLE_BUILD

public class MockRemoteConfigProvider: RemoteConfigProvider {
    var _currentConfig: RemoteConfig = .emptyConfig
    public func currentConfig() -> RemoteConfig { _currentConfig }
}

#endif

// MARK: -

public protocol RemoteConfigManager: RemoteConfigProvider {
    func warmCaches()
    var cachedConfig: RemoteConfig? { get }
    /// Refresh the remote config from the server if either:
    /// * has not been fetched this app launch
    /// * its been too long since we last fetched it
    /// and returns the latest fetched remote config value, whether just fetched
    /// or an eligible cached value.
    func refreshIfNeeded(account: AuthedAccount) async throws -> RemoteConfig
}

// MARK: -

#if TESTABLE_BUILD

public class StubbableRemoteConfigManager: RemoteConfigManager {
    public var cachedConfig: RemoteConfig?

    public func warmCaches() {}

    public func refreshIfNeeded(account: AuthedAccount) async throws -> RemoteConfig {
        return cachedConfig!
    }

    public func currentConfig() -> RemoteConfig {
        return cachedConfig ?? .emptyConfig
    }
}

#endif

// MARK: -

public class RemoteConfigManagerImpl: RemoteConfigManager {
    private let appExpiry: AppExpiry
    private let appReadiness: AppReadiness
    private let dateProvider: DateProvider
    private let db: any DB
    private let keyValueStore: KeyValueStore
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager

    // MARK: -

    private let _cachedConfig = AtomicValue<RemoteConfig?>(nil, lock: .init())
    public var cachedConfig: RemoteConfig? {
        let result = _cachedConfig.get()
        owsAssertDebug(result != nil, "cachedConfig not yet set.")
        return result
    }

    public func currentConfig() -> RemoteConfig {
        return cachedConfig ?? .emptyConfig
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
        appReadiness: AppReadiness,
        dateProvider: @escaping DateProvider,
        db: any DB,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager
    ) {
        self.appExpiry = appExpiry
        self.appReadiness = appReadiness
        self.dateProvider = dateProvider
        self.db = db
        self.keyValueStore = KeyValueStore(collection: "RemoteConfigManager")
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            guard self.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                return
            }
            Task {
                try await self.refreshIfNeeded()
            }
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
    private func registrationStateDidChange() {
        AssertIsOnMainThread()

        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else { return }
        Logger.info("Refreshing and immediately applying new flags due to new registration.")
        Task {
            do {
                try await refreshIfNeeded(force: true)
            } catch let error {
                Logger.error("Failed to update remote config after registration change \(error)")
            }
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
    }

    fileprivate func warmSecondaryCaches(valueFlags: [String: String]) {
        checkClientExpiration(valueFlags: valueFlags)
    }

    private static let refreshInterval = 2 * kHourInterval
    private let refreshTaskQueue = SerialTaskQueue()

    /// Nil if no attempt made this app session (not persisted across launches)
    /// Should only be accessed within `refreshTaskQueue`
    private var lastAttempt: Date?
    private var consecutiveFailures: UInt = 0

    @discardableResult
    public func refreshIfNeeded(account: AuthedAccount = .implicit()) async throws -> RemoteConfig {
        return try await self.refreshIfNeeded(account: account, force: false)
    }

    @discardableResult
    private func refreshIfNeeded(account: AuthedAccount = .implicit(), force: Bool) async throws -> RemoteConfig {
        return try await refreshTaskQueue.enqueue(operation: {
            func msToNextRefresh() -> UInt64 {
                let now = self.dateProvider()
                let nowMs = now.ows_millisecondsSince1970

                let backoffDelay = OWSOperation.retryIntervalForExponentialBackoff(failureCount: self.consecutiveFailures)
                let earliestPermittedAttempt = (self.lastAttempt ?? .distantPast).addingTimeInterval(backoffDelay)

                let lastSuccess = self.db.read { self.keyValueStore.getLastFetched(transaction: $0) }
                let nextScheduledRefresh = (lastSuccess ?? .distantPast).addingTimeInterval(Self.refreshInterval)

                let nextAttemptDate = max(earliestPermittedAttempt, nextScheduledRefresh)

                if now >= nextAttemptDate {
                    return 0
                } else {
                    return nextAttemptDate.ows_millisecondsSince1970 - nowMs
                }
            }

            if !force, msToNextRefresh() > 0, let cached = self._cachedConfig.get() {
                return cached
            } else {
                let result = await Result(catching: { try await self._refresh(account: account) })

                // Note: have to make sure we update `lastAttempt` and
                // `consecutiveFailures` before calling msToNextRefresh
                // again below. `_refresh` updates `keyValueStore.lastFetched`.
                self.lastAttempt = self.dateProvider()
                switch result {
                case .success:
                    self.consecutiveFailures = 0
                case .failure(let error):
                    Logger.error("error: \(error)")
                    self.consecutiveFailures += 1
                }

                // Kick off a task for the next refresh
                let msToNextRefresh = msToNextRefresh()
                Task {
                    try await Task.sleep(nanoseconds: msToNextRefresh * NSEC_PER_MSEC)
                    try await self.refreshIfNeeded()
                }

                return try result.get()
            }
        }).value
    }

    /// should only be called within `refreshTaskQueue`
    private func _refresh(account: AuthedAccount) async throws -> RemoteConfig {
        let fetchedConfig = try await fetchRemoteConfig(auth: account.chatServiceAuth)

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
        fetchedConfig.items.forEach { (key: String, item: FetchedRemoteConfigItem) in
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

        await self.db.awaitableWrite { transaction in
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
        // Similarly, persist the choice of libsignal for the chat websockets.
        let shouldUseLibsignalForIdentifiedWebsocket = isEnabledFlags[IsEnabledFlag.experimentalTransportUseLibsignalAuth.rawValue] ?? false
        ChatConnectionManagerImpl.saveShouldUseLibsignalForIdentifiedWebsocket(
            shouldUseLibsignalForIdentifiedWebsocket,
            in: CurrentAppContext().appUserDefaults()
        )
        let shouldUseLibsignalForUnidentifiedWebsocket = isEnabledFlags[IsEnabledFlag.experimentalTransportUseLibsignal.rawValue] ?? false
        ChatConnectionManagerImpl.saveShouldUseLibsignalForUnidentifiedWebsocket(
            shouldUseLibsignalForUnidentifiedWebsocket,
            in: CurrentAppContext().appUserDefaults()
        )
        let enableShadowingForUnidentifiedWebsocket = isEnabledFlags[IsEnabledFlag.experimentalTransportShadowingEnabled.rawValue] ?? false
        ChatConnectionManagerImpl.saveEnableShadowingForUnidentifiedWebsocket(
            enableShadowingForUnidentifiedWebsocket,
            in: CurrentAppContext().appUserDefaults()
        )

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

        newConfig.logFlags()

        return mergedConfig
    }

    // MARK: -

    private enum FetchedRemoteConfigItem {
        case isEnabled(Bool)
        case value(String)
    }

    private struct FetchedRemoteConfigResponse {
        public let items: [String: FetchedRemoteConfigItem]
        public let serverEpochTimeSeconds: UInt64?
    }

    private func fetchRemoteConfig(auth: ChatServiceAuth) async throws -> FetchedRemoteConfigResponse {
        let request = OWSRequestFactory.getRemoteConfigRequest(auth: auth)

        let response = try await networkManager.asyncRequest(request)

        guard let json = response.responseBodyJson else {
            throw OWSAssertionError("Missing or invalid JSON.")
        }
        guard let parser = ParamParser(responseObject: json) else {
            throw OWSAssertionError("Missing or invalid response.")
        }

        let config: [[String: Any]] = try parser.required(key: "config")
        let serverEpochTimeSeconds: UInt64? = try parser.optional(key: "serverEpochTime")

        let items: [String: FetchedRemoteConfigItem] = try config.reduce([:]) { accum, item in
            var accum = accum
            guard let itemParser = ParamParser(responseObject: item) else {
                throw OWSAssertionError("Missing or invalid remote config item.")
            }

            let name: String = try itemParser.required(key: "name")
            let isEnabled: Bool = try itemParser.required(key: "enabled")

            if let value: String = try itemParser.optional(key: "value") {
                accum[name] = .value(value)
            } else {
                accum[name] = .isEnabled(isEnabled)
            }

            return accum
        }

        return FetchedRemoteConfigResponse(
            items: items,
            serverEpochTimeSeconds: serverEpochTimeSeconds
        )
    }

    // MARK: - Client Expiration

    private struct MinimumVersion: Decodable, CustomDebugStringConvertible {
        let mustBeAtLeastVersion: AppVersionNumber4
        let enforcementDate: Date

        enum CodingKeys: String, CodingKey {
            case mustBeAtLeastVersion = "minVersion"
            case enforcementDate = "iso8601"
        }

        var debugDescription: String {
            return "<MinimumVersion \(mustBeAtLeastVersion) @ \(enforcementDate)>"
        }
    }

    private func checkClientExpiration(valueFlags: [String: String]) {
        if let minimumVersions = parseClientExpiration(valueFlags: valueFlags) {
            appExpiry.setExpirationDateForCurrentVersion(remoteExpirationDate(from: minimumVersions), db: db)
        } else {
            // If it's not valid, there's a typo in the config, err on the safe side
            // and leave it alone.
        }
    }

    private func parseClientExpiration(valueFlags: [String: String]) -> [MinimumVersion]? {
        let valueFlag = valueFlags[ValueFlag.clientExpiration.rawValue]
        guard let valueFlag, let dataValue = valueFlag.nilIfEmpty?.data(using: .utf8) else {
            return []
        }

        do {
            let jsonDecoder = JSONDecoder()
            jsonDecoder.dateDecodingStrategy = .iso8601
            return try jsonDecoder.decode([MinimumVersion].self, from: dataValue)
        } catch {
            owsFailDebug("Failed to decode client expiration (\(valueFlag), \(error)), ignoring.")
            return nil
        }
    }

    private func remoteExpirationDate(from minimumVersions: [MinimumVersion]) -> Date? {
        let currentVersion = AppVersionImpl.shared.currentAppVersion4
        // We only consider the requirements we don't already satisfy.
        return minimumVersions.lazy
            .filter { currentVersion < $0.mustBeAtLeastVersion }.map { $0.enforcementDate }.min()
    }
}

// MARK: -

private extension KeyValueStore {

    // MARK: - Remote Config Enabled Flags

    private static var remoteConfigIsEnabledFlagsKey: String { "remoteConfigKey" }

    func getRemoteConfigIsEnabledFlags(transaction: DBReadTransaction) -> [String: Bool]? {
        let decodedValue = getDictionary(
            Self.remoteConfigIsEnabledFlagsKey,
            keyClass: NSString.self,
            objectClass: NSNumber.self,
            transaction: transaction
        ) as [String: NSNumber]?
        return decodedValue?.mapValues { $0.boolValue }
    }

    func setRemoteConfigIsEnabledFlags(_ newValue: [String: Bool], transaction: DBWriteTransaction) {
        return setObject(newValue, key: Self.remoteConfigIsEnabledFlagsKey, transaction: transaction)
    }

    // MARK: - Remote Config Value Flags

    private static var remoteConfigValueFlagsKey: String { "remoteConfigValueFlags" }

    func getRemoteConfigValueFlags(transaction: DBReadTransaction) -> [String: String]? {
        return getDictionary(
            Self.remoteConfigValueFlagsKey,
            keyClass: NSString.self,
            objectClass: NSString.self,
            transaction: transaction
        ) as [String: String]?
    }

    func setRemoteConfigValueFlags(_ newValue: [String: String], transaction: DBWriteTransaction) {
        return setObject(newValue, key: Self.remoteConfigValueFlagsKey, transaction: transaction)
    }

    // MARK: - Remote Config Time Gated Flags

    private static var remoteConfigTimeGatedFlagsKey: String { "remoteConfigTimeGatedFlags" }

    func getRemoteConfigTimeGatedFlags(transaction: DBReadTransaction) -> [String: Date]? {
        return getDictionary(
            Self.remoteConfigTimeGatedFlagsKey,
            keyClass: NSString.self,
            objectClass: NSDate.self,
            transaction: transaction
        ) as [String: Date]?
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
