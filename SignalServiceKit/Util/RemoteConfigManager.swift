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
    let lastKnownClockSkew: TimeInterval

    fileprivate let valueFlags: [String: String]

    public let paymentsDisabledRegions: PhoneNumberRegions
    public let applePayDisabledRegions: PhoneNumberRegions
    public let creditAndDebitCardDisabledRegions: PhoneNumberRegions
    public let paypalDisabledRegions: PhoneNumberRegions
    public let sepaEnabledRegions: PhoneNumberRegions
    public let idealEnabledRegions: PhoneNumberRegions

    init(
        clockSkew: TimeInterval,
        valueFlags: [String: String],
    ) {
        self.lastKnownClockSkew = clockSkew
        self.valueFlags = valueFlags
        self.paymentsDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .paymentsDisabledRegions)
        self.applePayDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .applePayDisabledRegions)
        self.creditAndDebitCardDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .creditAndDebitCardDisabledRegions)
        self.paypalDisabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .paypalDisabledRegions)
        self.sepaEnabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .sepaEnabledRegions)
        self.idealEnabledRegions = Self.parsePhoneNumberRegions(valueFlags: valueFlags, flag: .idealEnabledRegions)
    }

    fileprivate static var emptyConfig: RemoteConfig {
        RemoteConfig(clockSkew: 0, valueFlags: [:])
    }

    /// Merges new values into an existing config.
    ///
    /// - Parameter newValueFlags: If nil, `valueFlags` aren't changed (e.g.,
    /// the server gave us an HTTP 304 and we're reusing the existing config).
    /// If nonnil, non-hot-swappable flags are taken from `self.valueFlags` and
    /// all others are taken from `newValueFlags`.
    ///
    /// - Parameter newClockSkew: The new clock skew; always used. Even when
    /// `newValueFlags` is nil, the HTTP 304 response has a new clock skew.
    func merging(newValueFlags: [String: String]?, newClockSkew: TimeInterval) -> RemoteConfig {
        if var newValueFlags = newValueFlags {
            for flag in IsEnabledFlag.allCases {
                if flag.isHotSwappable { continue }
                newValueFlags[flag.rawValue] = self.valueFlags[flag.rawValue]
            }
            for flag in ValueFlag.allCases {
                if flag.isHotSwappable { continue }
                newValueFlags[flag.rawValue] = self.valueFlags[flag.rawValue]
            }
            for flag in TimeGatedFlag.allCases {
                if flag.isHotSwappable { continue }
                newValueFlags[flag.rawValue] = self.valueFlags[flag.rawValue]
            }
            return RemoteConfig(clockSkew: newClockSkew, valueFlags: newValueFlags)
        } else {
            return RemoteConfig(clockSkew: newClockSkew, valueFlags: self.valueFlags)
        }
    }

    public var maxGroupSizeRecommended: UInt {
        getUIntValue(forFlag: .maxGroupSizeRecommended, defaultValue: 151)
    }

    public var maxGroupSizeHardLimit: UInt {
        getUIntValue(forFlag: .maxGroupSizeHardLimit, defaultValue: 1001)
    }

    public var maxGroupSizeBannedMembers: UInt {
        maxGroupSizeHardLimit
    }

    public var cdsSyncInterval: TimeInterval {
        interval(.cdsSyncInterval, defaultInterval: .day * 2)
    }

    public var automaticSessionResetKillSwitch: Bool {
        return isEnabled(.automaticSessionResetKillSwitch)
    }

    public var automaticSessionResetAttemptInterval: TimeInterval {
        interval(.automaticSessionResetAttemptInterval, defaultInterval: .hour)
    }

    public var reactiveProfileKeyAttemptInterval: TimeInterval {
        interval(.reactiveProfileKeyAttemptInterval, defaultInterval: .hour)
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
        interval(.replaceableInteractionExpiration, defaultInterval: .hour)
    }

    public var messageSendLogEntryLifetime: TimeInterval {
        interval(.messageSendLogEntryLifetime, defaultInterval: 2 * .week)
    }

    public var maxSenderKeyAge: TimeInterval {
        return Double(getStringConvertibleValue(forFlag: .maxSenderKeyAge, defaultValue: 2 * UInt64.weekInMs)) / 1000
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

    public var tsAttachmentMigrationBatchDelayMs: UInt64 {
        getUInt64Value(forFlag: .tsAttachmentMigrationBatchDelayMs, defaultValue: 50)
    }

    public var mediaTierFallbackCdnNumber: UInt32 {
        getUInt32Value(forFlag: .mediaTierFallbackCdnNumber, defaultValue: 3)
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
            defaultValue: UInt(TimeInterval.day)
        ))
    }

    public var messageQueueTime: TimeInterval {
        return interval(.messageQueueTimeInSeconds, defaultInterval: 45 * .day)
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

    public var isLazyDatabaseMigratorEnabled: Bool {
        return !isEnabled(.lazyDatabaseMigratorKillSwitch)
    }

    public var isNotificationServiceWebSocketEnabled: Bool {
        return isEnabled(.notificationServiceWebSocket) && isConnectionLockEnabled
    }

    public var isShareExtensionWebSocketEnabled: Bool {
        return isEnabled(.shareExtensionWebSocket) && isConnectionLockEnabled
    }

    public var isConnectionLockEnabled: Bool {
        return !isEnabled(.connectionLockKillSwitch)
    }

    public var usePqRatchet: Bool {
        return isEnabled(.usePqRatchet)
    }

    public var shouldVerifyPniAndPniIdentityKeyExist: Bool {
        return isEnabled(.shouldVerifyPniAndPniIdentityKeyExist)
    }

    public var shouldValidatePrimaryPniIdentityKey: Bool {
        return isEnabled(.shouldValidatePrimaryPniIdentityKey)
    }

    public var allowBackupSettings: Bool {
        if FeatureFlags.Backups.showSettings {
            return true
        }

        return FeatureFlags.Backups.supported && isEnabled(.allowBackupSettings)
    }

    #if TESTABLE_BUILD
    public var testHotSwappable: Bool? {
        if self.valueFlags[IsEnabledFlag.hotSwappable.rawValue] != nil {
            return isEnabled(.hotSwappable)
        }
        return nil
    }

    public var testNonSwappable: Bool? {
        if self.valueFlags[IsEnabledFlag.nonSwappable.rawValue] != nil {
            return isEnabled(.nonSwappable)
        }
        return nil
    }

    public var testHotSwappableValue: String? {
        return value(.hotSwappable)
    }

    public var testNonSwappableValue: String? {
        return value(.nonSwappable)
    }
    #endif

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

    private func getUInt64Value(
        forFlag flag: ValueFlag,
        defaultValue: UInt64
    ) -> UInt64 {
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
        var data = Data((key + ".").utf8)

        data.append(aci.serviceIdBinary)

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

    fileprivate func isEnabled(_ flag: IsEnabledFlag, defaultValue: Bool = false) -> Bool {
        switch valueFlags[flag.rawValue] {
        case nil:
            return defaultValue
        case "1", "true", "TRUE":
            return true
        default:
            return false
        }
    }

    private func isEnabled(_ flag: TimeGatedFlag, defaultValue: Bool = false) -> Bool {
        guard let rawValue = valueFlags[flag.rawValue] else {
            return defaultValue
        }
        guard let epochValue = TimeInterval(rawValue) else {
            owsFailDebug("Invalid value: \(rawValue)")
            return defaultValue
        }
        let dateThreshold = Date(timeIntervalSince1970: epochValue)
        let correctedDate = Date().addingTimeInterval(self.lastKnownClockSkew)
        return correctedDate >= dateThreshold
    }

    fileprivate func value(_ flag: ValueFlag) -> String? {
        return valueFlags[flag.rawValue]
    }

    public func debugDescriptions() -> [String: String] {
        return self.valueFlags
    }

    public func logFlags() {
        for (key, value) in debugDescriptions().sorted(by: { $0.key < $1.key }) {
            Logger.info("RemoteConfig: \(key) = \(value)")
        }
    }
}

// MARK: - IsEnabledFlag

private enum IsEnabledFlag: String, FlagType {
    case allowBackupSettings = "ios.allowBackups"
    case applePayGiftDonationKillSwitch = "ios.applePayGiftDonationKillSwitch"
    case applePayMonthlyDonationKillSwitch = "ios.applePayMonthlyDonationKillSwitch"
    case applePayOneTimeDonationKillSwitch = "ios.applePayOneTimeDonationKillSwitch"
    case automaticSessionResetKillSwitch = "ios.automaticSessionResetKillSwitch"
    case cardGiftDonationKillSwitch = "ios.cardGiftDonationKillSwitch"
    case cardMonthlyDonationKillSwitch = "ios.cardMonthlyDonationKillSwitch"
    case cardOneTimeDonationKillSwitch = "ios.cardOneTimeDonationKillSwitch"
    case connectionLockKillSwitch = "ios.connectionLockKillSwitch"
    case enableAutoAPNSRotation = "ios.enableAutoAPNSRotation"
    case enableGifSearch = "global.gifSearch"
    case lazyDatabaseMigratorKillSwitch = "ios.lazyDatabaseMigratorKillSwitch"
    case libsignalEnforceMinTlsVersion = "ios.libsignalEnforceMinTlsVersion"
    case messageResendKillSwitch = "ios.messageResendKillSwitch"
    case notificationServiceWebSocket = "ios.notificationServiceWebSocket"
    case paymentsResetKillSwitch = "ios.paymentsResetKillSwitch"
    case paypalGiftDonationKillSwitch = "ios.paypalGiftDonationKillSwitch"
    case paypalMonthlyDonationKillSwitch = "ios.paypalMonthlyDonationKillSwitch"
    case paypalOneTimeDonationKillSwitch = "ios.paypalOneTimeDonationKillSwitch"
    case ringrtcNwPathMonitorTrialKillSwitch = "ios.ringrtcNwPathMonitorTrialKillSwitch"
    case serviceExtensionFailureKillSwitch = "ios.serviceExtensionFailureKillSwitch"
    case shareExtensionWebSocket = "ios.shareExtensionWebSocket"
    case shouldValidatePrimaryPniIdentityKey = "ios.shouldValidatePrimaryPniIdentityKey"
    case shouldVerifyPniAndPniIdentityKeyExist = "ios.shouldVerifyPniAndPniIdentityKeyExist"
    case tsAttachmentMigrationBGProcessingTaskKillSwitch = "ios.tsAttachmentMigrationBGProcessingTaskKillSwitch"
    case tsAttachmentMigrationMainAppBackgroundKillSwitch = "ios.tsAttachmentMigrationMainAppBackgroundKillSwitch"
    case usePqRatchet = "ios.usePqRatchet"

    #if TESTABLE_BUILD
    case hotSwappable = "test.hotSwappable.enabled"
    case nonSwappable = "test.nonSwappable.enabled"
    #endif

    var isHotSwappable: Bool {
        switch self {
        case .allowBackupSettings: true
        case .applePayGiftDonationKillSwitch: false
        case .applePayMonthlyDonationKillSwitch: false
        case .applePayOneTimeDonationKillSwitch: false
        case .automaticSessionResetKillSwitch: false
        case .cardGiftDonationKillSwitch: false
        case .cardMonthlyDonationKillSwitch: false
        case .cardOneTimeDonationKillSwitch: false
        case .connectionLockKillSwitch: true
        case .enableAutoAPNSRotation: false
        case .enableGifSearch: false
        case .lazyDatabaseMigratorKillSwitch: true
        case .libsignalEnforceMinTlsVersion: true // cached during launch, so not hot-swapped in practice
        case .messageResendKillSwitch: false
        case .notificationServiceWebSocket: true
        case .paymentsResetKillSwitch: false
        case .paypalGiftDonationKillSwitch: false
        case .paypalMonthlyDonationKillSwitch: false
        case .paypalOneTimeDonationKillSwitch: false
        case .ringrtcNwPathMonitorTrialKillSwitch: true // cached during launch, so not hot-swapped in practice
        case .serviceExtensionFailureKillSwitch: true
        case .shareExtensionWebSocket: true
        case .shouldValidatePrimaryPniIdentityKey: true
        case .shouldVerifyPniAndPniIdentityKeyExist: true
        case .tsAttachmentMigrationBGProcessingTaskKillSwitch: true
        case .tsAttachmentMigrationMainAppBackgroundKillSwitch: true
        case .usePqRatchet: true

        #if TESTABLE_BUILD
        case .hotSwappable: true
        case .nonSwappable: false
        #endif
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
    case idealEnabledRegions = "global.donations.idealEnabledRegions"
    case maxAttachmentDownloadSizeBytes = "global.attachments.maxBytes"
    case maxGroupCallRingSize = "global.calling.maxGroupCallRingSize"
    case maxGroupSizeHardLimit = "global.groupsv2.groupSizeHardLimit"
    case maxGroupSizeRecommended = "global.groupsv2.maxGroupSize"
    case maxNicknameLength = "global.nicknames.max"
    case maxSenderKeyAge = "ios.maxSenderKeyAge"
    case mediaTierFallbackCdnNumber = "global.backups.mediaTierFallbackCdnNumber"
    case messageQueueTimeInSeconds = "global.messageQueueTimeInSeconds"
    case messageSendLogEntryLifetime = "ios.messageSendLogEntryLifetime"
    case minNicknameLength = "global.nicknames.min"
    case paymentsDisabledRegions = "global.payments.disabledRegions"
    case paypalDisabledRegions = "global.donations.paypalDisabledRegions"
    case reactiveProfileKeyAttemptInterval = "ios.reactiveProfileKeyAttemptInterval"
    case replaceableInteractionExpiration = "ios.replaceableInteractionExpiration"
    case sepaEnabledRegions = "global.donations.sepaEnabledRegions"
    case standardMediaQualityLevel = "ios.standardMediaQualityLevel"
    case tsAttachmentMigrationBatchDelayMs = "ios.tsAttachmentMigrationBatchDelayMs"

    #if TESTABLE_BUILD
    case hotSwappable = "test.hotSwappable.value"
    case nonSwappable = "test.nonSwappable.value"
    #endif

    var isHotSwappable: Bool {
        switch self {
        case .applePayDisabledRegions: true
        case .automaticSessionResetAttemptInterval: true
        case .backgroundRefreshInterval: true
        case .cdsSyncInterval: false
        case .clientExpiration: true
        case .creditAndDebitCardDisabledRegions: true
        case .idealEnabledRegions: true
        case .maxAttachmentDownloadSizeBytes: false
        case .maxGroupCallRingSize: true
        case .maxGroupSizeHardLimit: true
        case .maxGroupSizeRecommended: true
        case .maxNicknameLength: false
        case .maxSenderKeyAge: true
        case .mediaTierFallbackCdnNumber: true
        case .messageQueueTimeInSeconds: false
        case .messageSendLogEntryLifetime: false
        case .minNicknameLength: false
        case .paymentsDisabledRegions: true
        case .paypalDisabledRegions: true
        case .reactiveProfileKeyAttemptInterval: true
        case .replaceableInteractionExpiration: false
        case .sepaEnabledRegions: true
        case .standardMediaQualityLevel: false
        case .tsAttachmentMigrationBatchDelayMs: true

        #if TESTABLE_BUILD
        case .hotSwappable: true
        case .nonSwappable: false
        #endif
        }
    }
}

private enum TimeGatedFlag: String, FlagType {
    case __none

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
    func warmCaches() -> RemoteConfig
    var cachedConfig: RemoteConfig? { get }
    /// Refresh the remote config from the server if it's been too long since we
    /// last fetched it.
    func refreshIfNeeded() async throws
}

// MARK: -

#if TESTABLE_BUILD

public class StubbableRemoteConfigManager: RemoteConfigManager {
    public var cachedConfig: RemoteConfig?

    public func warmCaches() -> RemoteConfig {
        return currentConfig()
    }

    public func refreshIfNeeded() async throws {
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
            self.refreshRepeatedlyIfNeeded(forceInitialRefreshImmediately: false)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.registrationStateDidChange),
                name: .registrationStateDidChange,
                object: nil
            )
        }
    }

    // MARK: -

    @objc
    @MainActor
    private func registrationStateDidChange() {
        AssertIsOnMainThread()

        Logger.info("Forcing a refresh because the registration state changed.")
        self.refreshRepeatedlyIfNeeded(forceInitialRefreshImmediately: true)
    }

    public func warmCaches() -> RemoteConfig {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        let (clockSkew, valueFlags) = db.read { (tx) -> (TimeInterval?, [String: String]?) in
            guard self.tsAccountManager.registrationState(tx: tx).isRegistered else {
                return (nil, nil)
            }
            let valueFlags = RemoteConfigStore(keyValueStore: self.keyValueStore).loadValueFlags(tx: tx)
            guard let valueFlags else {
                return (nil, nil)
            }
            let clockSkew = self.keyValueStore.getLastKnownClockSkew(transaction: tx)
            return (clockSkew, valueFlags)
        }

        return updateCachedConfig { oldConfig in
            if let oldConfig {
                // If we're calling warmCaches for the second or later time, we can only
                // update the flags that are hot-swappable.
                return oldConfig.merging(newValueFlags: valueFlags ?? [:], newClockSkew: clockSkew ?? 0)
            } else {
                // If we're calling warmCaches for first time, we can set hot swappable and
                // non-hot swappable flags.
                return RemoteConfig(clockSkew: clockSkew ?? 0, valueFlags: valueFlags ?? [:])
            }
        }
    }

    private static let refreshInterval: TimeInterval = 2 * .hour
    private let refreshTaskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    @MainActor
    private var refreshTask: Task<Void, any Error>?

    @MainActor
    private func refreshRepeatedlyIfNeeded(forceInitialRefreshImmediately: Bool) {
        self.refreshTask?.cancel()
        guard self.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }
        self.refreshTask = Task {
            try await self.refreshRepeatedly(forceInitialRefreshImmediately: forceInitialRefreshImmediately)
        }
    }

    private func refreshRepeatedly(forceInitialRefreshImmediately: Bool) async throws {
        var refreshImmediately = forceInitialRefreshImmediately
        while true {
            try Task.checkCancellation()

            let nextFetchDate = self.fetchNextFetchDate()
            let fetchDelay = nextFetchDate.timeIntervalSince(self.dateProvider())
            if !refreshImmediately, fetchDelay > 0 {
                try await Task.sleep(nanoseconds: fetchDelay.clampedNanoseconds)
            }
            refreshImmediately = false

            try await Retry.performWithBackoff(maxAttempts: Int.max, maxAverageBackoff: 14.1 * .minute) {
                do {
                    try await self.refreshIfNeeded()
                } catch {
                    // Treat all failures as retryable. They all *should* be retryable.
                    throw OWSRetryableError()
                }
            }
        }
    }

    private func fetchNextFetchDate() -> Date {
        let lastFetchDate = self.db.read { self.keyValueStore.getLastFetched(transaction: $0) }
        return (lastFetchDate ?? .distantPast).addingTimeInterval(Self.refreshInterval)
    }

    public func refreshIfNeeded() async throws {
        try await refreshTaskQueue.run {
            let nextFetchDate = self.fetchNextFetchDate()
            guard self.dateProvider() > nextFetchDate else {
                return
            }

            do {
                try await self._refresh()
                // We expect `_refresh` to update `keyValueStore.lastFetched`, so add a
                // check to ensure that it does.
                owsPrecondition(self.fetchNextFetchDate() != nextFetchDate)
            } catch {
                Logger.warn("\(error)")
                throw error
            }
        }
    }

    /// should only be called within `refreshTaskQueue`
    private func _refresh() async throws {
        let (valueFlags, headers) = try await fetchRemoteConfig()

        if valueFlags == nil {
            Logger.info("Fetched a new remote config but the values haven't changed.")
        }

        let serverEpochTimeMs = headers["x-signal-timestamp"].flatMap(UInt64.init(_:))
        owsAssertDebug(serverEpochTimeMs != nil, "Must have X-Signal-Timestamp.")

        let clockSkew: TimeInterval
        if let serverEpochTimeMs = serverEpochTimeMs {
            let dateAccordingToServer = Date(timeIntervalSince1970: TimeInterval(serverEpochTimeMs) / 1000)
            clockSkew = dateAccordingToServer.timeIntervalSince(Date())
        } else {
            clockSkew = 0
        }

        // Persist all flags in the database to be applied on next launch.

        await self.db.awaitableWrite { transaction in
            self.keyValueStore.setClockSkew(clockSkew, transaction: transaction)
            if let valueFlags {
                self.keyValueStore.removeRemoteConfigIsEnabledFlags(tx: transaction)
                self.keyValueStore.setRemoteConfigValueFlags(valueFlags, transaction: transaction)
                self.keyValueStore.removeRemoteConfigTimeGatedFlags(tx: transaction)
                self.keyValueStore.setETag(headers["etag"], tx: transaction)
            }
            self.keyValueStore.setLastFetched(Date(), transaction: transaction)
        }

        // This has hot-swappable new values and non-hot-swappable old values.
        let mergedConfig = updateCachedConfig { oldConfig in
            return (oldConfig ?? .emptyConfig).merging(newValueFlags: valueFlags, newClockSkew: clockSkew)
        }

        // As a special case, persist RingRTC field trials. See comments in
        // ``RingrtcFieldTrials`` for details.
        RingrtcFieldTrials.saveNwPathMonitorTrialState(
            isEnabled: {
                let isKilled = mergedConfig.isEnabled(.ringrtcNwPathMonitorTrialKillSwitch, defaultValue: false)
                return !isKilled
            }(),
            in: CurrentAppContext().appUserDefaults()
        )

        let libsignalEnforceMinTlsVersion = mergedConfig.isEnabled(.libsignalEnforceMinTlsVersion, defaultValue: FeatureFlags.libsignalEnforceMinTlsVersion)

        LibsignalUserDefaults.saveShouldEnforceMinTlsVersion(libsignalEnforceMinTlsVersion, in: CurrentAppContext().appUserDefaults())

        await checkClientExpiration(valueFlag: mergedConfig.value(.clientExpiration))

        mergedConfig.logFlags()
    }

    // MARK: -

    private struct RemoteConfigurationResponse: Decodable {
        var config: [String: String]
    }

    private func fetchRemoteConfig() async throws -> ([String: String]?, HttpHeaders) {
        let oldETag = self.db.read { tx in self.keyValueStore.getETag(tx: tx) }

        let request = OWSRequestFactory.getRemoteConfigRequest(eTag: oldETag)
        do {
            let response = try await networkManager.asyncRequest(request)

            let result = try JSONDecoder().decode(RemoteConfigurationResponse.self, from: response.responseBodyData ?? Data())

            return (result.config, response.headers)
        } catch OWSHTTPError.serviceResponse(let serviceResponse) where serviceResponse.responseStatus == 304 {
            return (nil, serviceResponse.headers)
        }
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

    private func checkClientExpiration(valueFlag: String?) async {
        if let minimumVersions = parseClientExpiration(valueFlag: valueFlag) {
            await appExpiry.setExpirationDateForCurrentVersion(remoteExpirationDate(from: minimumVersions), now: dateProvider(), db: db)
        } else {
            // If it's not valid, there's a typo in the config, err on the safe side
            // and leave it alone.
        }
    }

    private func parseClientExpiration(valueFlag: String?) -> [MinimumVersion]? {
        guard let valueFlag = valueFlag?.nilIfEmpty else {
            return []
        }

        do {
            let jsonDecoder = JSONDecoder()
            jsonDecoder.dateDecodingStrategy = .iso8601
            return try jsonDecoder.decode([MinimumVersion].self, from: Data(valueFlag.utf8))
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

struct RemoteConfigStore {
    private let keyValueStore: KeyValueStore

    init(keyValueStore: KeyValueStore) {
        self.keyValueStore = keyValueStore
    }

    func loadValueFlags(tx: DBReadTransaction) -> [String: String]? {
        var result = self.keyValueStore.getRemoteConfigValueFlags(transaction: tx)

        // TODO: Remove these IsEnabled/TimeGated fallbacks after a while.
        // (Doing so will reset "IsEnabled" flags for long-inactive users, but
        // that's fine because they should fetch new ones immediately.)
        if let isEnabledFlags = self.keyValueStore.getRemoteConfigIsEnabledFlags(transaction: tx) {
            result = result ?? [:]
            isEnabledFlags.forEach { result?[$0] = $1 ? "true" : "false" }
        }
        if let timeGatedFlags = self.keyValueStore.getRemoteConfigTimeGatedFlags(transaction: tx) {
            result = result ?? [:]
            timeGatedFlags.forEach { result?[$0] = String($1.timeIntervalSince1970) }
        }

        return result
    }
}

// MARK: -

private extension KeyValueStore {

    func removeRemoteConfigIsEnabledFlags(tx: DBWriteTransaction) {
        removeValue(forKey: Self.remoteConfigIsEnabledFlagsKey, transaction: tx)
    }

    func removeRemoteConfigTimeGatedFlags(tx: DBWriteTransaction) {
        removeValue(forKey: Self.remoteConfigTimeGatedFlagsKey, transaction: tx)
    }

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

    // MARK: - ETag

    private var eTagKey: String { "eTag" }

    func getETag(tx: DBReadTransaction) -> String? {
        return getString(eTagKey, transaction: tx)
    }

    func setETag(_ newValue: String?, tx: DBWriteTransaction) {
        setString(newValue, key: eTagKey, transaction: tx)
    }
}

// MARK: -

enum LibsignalUserDefaults {

    private static var shouldEnforceMinTlsVersionKey: String = "LibsignalEnforceMinTlsVersion"

    /// We cache this in UserDefaults because it's used too early to access the RemoteConfig object.
    ///
    /// It also makes it possible to override the setting in Xcode via the Scheme settings:
    /// add the arguments "-UseLibsignalForUnidentifiedWebsocket YES" to the invocation of the app.
    static func saveShouldEnforceMinTlsVersion(
        _ shouldEnforceMinTlsVersion: Bool,
        in defaults: UserDefaults
    ) {
        defaults.set(shouldEnforceMinTlsVersion, forKey: shouldEnforceMinTlsVersionKey)
    }

    static func readShouldEnforceMinTlsVersion(from defaults: UserDefaults) -> Bool {
        return defaults.bool(forKey: shouldEnforceMinTlsVersionKey)
    }
}
