//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum NotificationType: UInt {
    case noNameNoPreview = 0
    case nameNoPreview = 1
    case namePreview = 2

    public var displayName: String {
        switch self {
        case .namePreview:
            return OWSLocalizedString("NOTIFICATIONS_SENDER_AND_MESSAGE", comment: "")
        case .nameNoPreview:
            return OWSLocalizedString("NOTIFICATIONS_SENDER_ONLY", comment: "")
        case .noNameNoPreview:
            return OWSLocalizedString("NOTIFICATIONS_NONE", comment: "")
        }
    }
}

public class Preferences {

    private enum Key: String {
        case screenSecurity = "Screen Security Key"
        case notificationPreviewType = "Notification Preview Type Key"
        case playSoundInForeground = "NotificationSoundInForeground"
        case lastRecordedPushToken = "LastRecordedPushToken"
        case callsHideIPAddress = "CallsHideIPAddress"
        case hasDeclinedNoContactsView = "hasDeclinedNoContactsView"
        case shouldShowUnidentifiedDeliveryIndicators = "OWSPreferencesKeyShouldShowUnidentifiedDeliveryIndicators"
        case shouldNotifyOfNewAccountKey = "OWSPreferencesKeyShouldNotifyOfNewAccountKey"
        case iOSUpgradeNagDate = "iOSUpgradeNagDate"
        case systemCallLogEnabled = "OWSPreferencesKeySystemCallLogEnabled"
        case wasViewOnceTooltipShown = "OWSPreferencesKeyWasViewOnceTooltipShown"
        case wasDeleteForEveryoneConfirmationShown = "OWSPreferencesKeyWasDeleteForEveryoneConfirmationShown"
        case wasBlurTooltipShown = "OWSPreferencesKeyWasBlurTooltipShown"

        // Obsolete
        // case wasGroupCallTooltipShown = "OWSPreferencesKeyWasGroupCallTooltipShown"
        // case wasGroupCallTooltipShownCount = "OWSPreferencesKeyWasGroupCallTooltipShownCount"
        // case callKitEnabled = "CallKitEnabled"
        // case callKitPrivacyEnabled = "CallKitPrivacyEnabled"
    }

    private enum UserDefaultsKeys {
        static let deviceScale = "OWSPreferencesKeyDeviceScale"
        static let isAudibleErrorLoggingEnabled = "IsAudibleErrorLoggingEnabled"
        static let isFailDebugEnabled = "IsFailDebugEnabled"
    }

    private static let preferencesCollection = "SignalPreferences"
    private let keyValueStore = KeyValueStore(collection: Preferences.preferencesCollection)

    public init() {
        if CurrentAppContext().hasUI {
            CurrentAppContext().appUserDefaults().set(UIScreen.main.scale, forKey: UserDefaultsKeys.deviceScale)
        }
        SwiftSingletons.register(self)
    }

    // MARK: Helpers

    private func hasValue(forKey key: Key) -> Bool {
        let result = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return keyValueStore.hasValue(key.rawValue, transaction: transaction)
        }
        return result
    }

    private func removeValue(forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            keyValueStore.removeValue(forKey: key.rawValue, transaction: transaction)
        }
    }

    private func bool(forKey key: Key, defaultValue: Bool) -> Bool {
        let result = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            keyValueStore.getBool(key.rawValue, defaultValue: defaultValue, transaction: transaction)
        }
        return result
    }

    private func setBool(_ value: Bool, forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            setBool(value, forKey: key, tx: transaction)
        }
    }

    private func setBool(_ value: Bool, forKey key: Key, tx: DBWriteTransaction) {
        keyValueStore.setBool(value, key: key.rawValue, transaction: tx)
    }

    private func uint(forKey key: Key, defaultValue: UInt) -> UInt {
        let result = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            keyValueStore.getUInt(key.rawValue, defaultValue: defaultValue, transaction: transaction)
        }
        return result
    }

    private func setUInt(_ value: UInt, forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            keyValueStore.setUInt(value, key: key.rawValue, transaction: transaction)
        }
    }

    private func date(forKey key: Key) -> Date? {
        let date = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            keyValueStore.getDate(key.rawValue, transaction: transaction)
        }
        return date
    }

    private func setDate(_ value: Date, forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            keyValueStore.setDate(value, key: key.rawValue, transaction: transaction)
        }
    }

    private func string(forKey key: Key) -> String? {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in getString(for: key, tx: tx) }
    }

    private func getString(for key: Key, tx: DBReadTransaction) -> String? {
        return keyValueStore.getString(key.rawValue, transaction: tx)
    }

    private func setString(_ value: String?, forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in setString(value, for: key, tx: tx) }
    }

    private func setString(_ value: String?, for key: Key, tx: DBWriteTransaction) {
        keyValueStore.setString(value, key: key.rawValue, transaction: tx)
    }

    // MARK: Logging

    public static var isFailDebugEnabled: Bool {
        return BuildFlags.failDebug && CurrentAppContext().appUserDefaults().bool(forKey: UserDefaultsKeys.isFailDebugEnabled)
    }

    public static func setIsFailDebugEnabled(_ value: Bool) {
        CurrentAppContext().appUserDefaults().set(value, forKey: UserDefaultsKeys.isFailDebugEnabled)
    }

    public static var isAudibleErrorLoggingEnabled: Bool {
        CurrentAppContext().appUserDefaults().bool(forKey: UserDefaultsKeys.isAudibleErrorLoggingEnabled) && BuildFlags.choochoo
    }

    public static func setIsAudibleErrorLoggingEnabled(_ value: Bool) {
        CurrentAppContext().appUserDefaults().set(value, forKey: UserDefaultsKeys.isAudibleErrorLoggingEnabled)
    }

    // MARK: Specific Preferences

    public var isScreenSecurityEnabled: Bool {
        bool(forKey: .screenSecurity, defaultValue: false)
    }

    public func setIsScreenSecurityEnabled(_ value: Bool) {
        setBool(value, forKey: .screenSecurity)
    }

    public var hasDeclinedNoContactsView: Bool {
        bool(forKey: .hasDeclinedNoContactsView, defaultValue: false)
    }

    public func setHasDeclinedNoContactsView(_ value: Bool) {
        setBool(value, forKey: .hasDeclinedNoContactsView)
    }

    public var iOSUpgradeNagDate: Date? {
        date(forKey: .iOSUpgradeNagDate)
    }

    public func setIOSUpgradeNagDate(_ value: Date) {
        setDate(value, forKey: .iOSUpgradeNagDate)
    }

    @objc
    public var shouldShowUnidentifiedDeliveryIndicators: Bool {
        bool(forKey: .shouldShowUnidentifiedDeliveryIndicators, defaultValue: false)
    }

    public func shouldShowUnidentifiedDeliveryIndicators(transaction: DBReadTransaction) -> Bool {
        keyValueStore.getBool(
            Key.shouldShowUnidentifiedDeliveryIndicators.rawValue,
            defaultValue: false,
            transaction: transaction,
        )
    }

    public func setShouldShowUnidentifiedDeliveryIndicatorsAndSendSyncMessage(_ value: Bool) {
        setBool(value, forKey: .shouldShowUnidentifiedDeliveryIndicators)

        SSKEnvironment.shared.syncManagerRef.sendConfigurationSyncMessage()
        SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
    }

    @objc
    public func setShouldShowUnidentifiedDeliveryIndicators(_ value: Bool, transaction: DBWriteTransaction) {
        keyValueStore.setBool(value, key: Key.shouldShowUnidentifiedDeliveryIndicators.rawValue, transaction: transaction)
    }

    public func shouldNotifyOfNewAccounts(transaction: DBReadTransaction) -> Bool {
        keyValueStore.getBool(Key.shouldNotifyOfNewAccountKey.rawValue, defaultValue: false, transaction: transaction)
    }

    public func setShouldNotifyOfNewAccounts(_ value: Bool, transaction: DBWriteTransaction) {
        keyValueStore.setBool(value, key: Key.shouldNotifyOfNewAccountKey.rawValue, transaction: transaction)
    }

    public var cachedDeviceScale: CGFloat {
        guard !CurrentAppContext().hasUI else { return UIScreen.main.scale }

        guard let cachedValue = CurrentAppContext().appUserDefaults().object(forKey: UserDefaultsKeys.deviceScale) as? CGFloat else {
            return UIScreen.main.scale
        }

        return cachedValue
    }

    // MARK: Calls

    public func isSystemCallLogEnabled(tx: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(Key.systemCallLogEnabled.rawValue, defaultValue: true, transaction: tx)
    }

    public func setIsSystemCallLogEnabled(_ value: Bool) {
        setBool(value, forKey: .systemCallLogEnabled)
    }

    // Allow callers to connect directly, when desirable, vs. enforcing TURN only proxy connectivity
    public var doCallsHideIPAddress: Bool {
        bool(forKey: .callsHideIPAddress, defaultValue: false)
    }

    public func setDoCallsHideIPAddress(_ value: Bool) {
        setBool(value, forKey: .callsHideIPAddress)
    }

    // MARK: UI Tooltips

    public var wasViewOnceTooltipShown: Bool {
        bool(forKey: .wasViewOnceTooltipShown, defaultValue: false)
    }

    public func setWasViewOnceTooltipShown() {
        setBool(true, forKey: .wasViewOnceTooltipShown)
    }

    public var wasBlurTooltipShown: Bool {
        bool(forKey: .wasBlurTooltipShown, defaultValue: false)
    }

    public func setWasBlurTooltipShown() {
        setBool(true, forKey: .wasBlurTooltipShown)
    }

    public var wasDeleteForEveryoneConfirmationShown: Bool {
        bool(forKey: .wasDeleteForEveryoneConfirmationShown, defaultValue: false)
    }

    public func setWasDeleteForEveryoneConfirmationShown() {
        setBool(true, forKey: .wasDeleteForEveryoneConfirmationShown)
    }

    // MARK: Notification Preferences

    public var soundInForeground: Bool {
        bool(forKey: .playSoundInForeground, defaultValue: true)
    }

    public func setSoundInForeground(_ value: Bool) {
        setBool(value, forKey: .playSoundInForeground)
    }

    public func notificationPreviewType(tx: DBReadTransaction) -> NotificationType {
        let rawValue = keyValueStore.getUInt(
            Key.notificationPreviewType.rawValue,
            transaction: tx,
        )
        return rawValue.flatMap(NotificationType.init(rawValue:)) ?? .namePreview
    }

    public func setNotificationPreviewType(_ value: NotificationType) {
        setUInt(value.rawValue, forKey: .notificationPreviewType)
    }

    // MARK: Push Tokens

    public var pushToken: String? {
        string(forKey: .lastRecordedPushToken)
    }

    public func getPushToken(tx: DBReadTransaction) -> String? {
        return getString(for: .lastRecordedPushToken, tx: tx)
    }

    public func setPushToken(_ value: String, tx: DBWriteTransaction) {
        setString(value, for: .lastRecordedPushToken, tx: tx)
    }

    public func unsetRecordedAPNSTokens() {
        Logger.warn("Forgetting recorded APNS tokens")
        removeValue(forKey: .lastRecordedPushToken)
    }
}
