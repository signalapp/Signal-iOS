//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

private extension UserDefaults {
    static var app: UserDefaults {
        CurrentAppContext().appUserDefaults()
    }

    static func removeAll() {
        UserDefaults.standard.removeAll()
        app.removeAll()
    }

    private func removeAll() {
        owsAssertDebug(CurrentAppContext().isMainApp)

        for (key, _) in self.dictionaryRepresentation() {
            self.removeObject(forKey: key)
        }
        self.synchronize()
    }
}

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

@objc(OWSPreferences)
public class Preferences: NSObject {

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
        case wasGroupCallTooltipShown = "OWSPreferencesKeyWasGroupCallTooltipShown"
        case wasGroupCallTooltipShownCount = "OWSPreferencesKeyWasGroupCallTooltipShownCount"

        // Obsolete
        // case callKitEnabled = "CallKitEnabled"
        // case callKitPrivacyEnabled = "CallKitPrivacyEnabled"
    }

    private enum UserDefaultsKeys {
        static let deviceScale = "OWSPreferencesKeyDeviceScale"
        static let isAudibleErrorLoggingEnabled = "IsAudibleErrorLoggingEnabled"
    }

    private static let preferencesCollection = "SignalPreferences"
    private let keyValueStore = KeyValueStore(collection: Preferences.preferencesCollection)

    public override init() {
        super.init()
        if CurrentAppContext().hasUI {
            CurrentAppContext().appUserDefaults().set(UIScreen.main.scale, forKey: UserDefaultsKeys.deviceScale)
        }
        SwiftSingletons.register(self)
    }

    // MARK: Helpers

    public func removeAllValues() {
        UserDefaults.removeAll()

        // We don't need to clear our key-value store; database
        // storage is cleared otherwise.
    }

    private func hasValue(forKey key: Key) -> Bool {
        let result = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return keyValueStore.hasValue(key.rawValue, transaction: transaction.asV2Read)
        }
        return result
    }

    private func removeValue(forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            keyValueStore.removeValue(forKey: key.rawValue, transaction: transaction.asV2Write)
        }
    }

    private func bool(forKey key: Key, defaultValue: Bool) -> Bool {
        let result = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            keyValueStore.getBool(key.rawValue, defaultValue: defaultValue, transaction: transaction.asV2Read)
        }
        return result
    }

    private func setBool(_ value: Bool, forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            setBool(value, forKey: key, tx: transaction)
        }
    }

    private func setBool(_ value: Bool, forKey key: Key, tx: SDSAnyWriteTransaction) {
        keyValueStore.setBool(value, key: key.rawValue, transaction: tx.asV2Write)
    }

    private func uint(forKey key: Key, defaultValue: UInt) -> UInt {
        let result = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            keyValueStore.getUInt(key.rawValue, defaultValue: defaultValue, transaction: transaction.asV2Read)
        }
        return result
    }

    private func setUInt(_ value: UInt, forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            keyValueStore.setUInt(value, key: key.rawValue, transaction: transaction.asV2Write)
        }
    }

    private func date(forKey key: Key) -> Date? {
        let date = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            keyValueStore.getDate(key.rawValue, transaction: transaction.asV2Read)
        }
        return date
    }

    private func setDate(_ value: Date, forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            keyValueStore.setDate(value, key: key.rawValue, transaction: transaction.asV2Write)
        }
    }

    private func string(forKey key: Key) -> String? {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in getString(for: key, tx: tx) }
    }

    private func getString(for key: Key, tx: SDSAnyReadTransaction) -> String? {
        return keyValueStore.getString(key.rawValue, transaction: tx.asV2Read)
    }

    private func setString(_ value: String?, forKey key: Key) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in setString(value, for: key, tx: tx) }
    }

    private func setString(_ value: String?, for key: Key, tx: SDSAnyWriteTransaction) {
        keyValueStore.setString(value, key: key.rawValue, transaction: tx.asV2Write)
    }

    // MARK: Logging

    @objc
    public static var isAudibleErrorLoggingEnabled: Bool {
        UserDefaults.app.bool(forKey: UserDefaultsKeys.isAudibleErrorLoggingEnabled) && FeatureFlags.choochoo
    }

    public static func setIsAudibleErrorLoggingEnabled(_ value: Bool) {
        UserDefaults.app.set(value, forKey: UserDefaultsKeys.isAudibleErrorLoggingEnabled)
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

    public func shouldShowUnidentifiedDeliveryIndicators(transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(
            Key.shouldShowUnidentifiedDeliveryIndicators.rawValue,
            defaultValue: false,
            transaction: transaction.asV2Read
        )
    }

    public func setShouldShowUnidentifiedDeliveryIndicatorsAndSendSyncMessage(_ value: Bool) {
        setBool(value, forKey: .shouldShowUnidentifiedDeliveryIndicators)

        SSKEnvironment.shared.syncManagerRef.sendConfigurationSyncMessage()
        SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
    }

    @objc
    public func setShouldShowUnidentifiedDeliveryIndicators(_ value: Bool, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setBool(value, key: Key.shouldShowUnidentifiedDeliveryIndicators.rawValue, transaction: transaction.asV2Write)
    }

    public func shouldNotifyOfNewAccounts(transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(Key.shouldNotifyOfNewAccountKey.rawValue, defaultValue: false, transaction: transaction.asV2Read)
    }

    public func setShouldNotifyOfNewAccounts(_ value: Bool, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setBool(value, key: Key.shouldNotifyOfNewAccountKey.rawValue, transaction: transaction.asV2Write)
    }

    public var cachedDeviceScale: CGFloat {
        guard !CurrentAppContext().hasUI else { return UIScreen.main.scale }

        guard let cachedValue = CurrentAppContext().appUserDefaults().object(forKey: UserDefaultsKeys.deviceScale) as? CGFloat else {
            return UIScreen.main.scale
        }

        return cachedValue
    }

    // MARK: Calls

    public func isSystemCallLogEnabled(tx: SDSAnyReadTransaction) -> Bool {
        return keyValueStore.getBool(Key.systemCallLogEnabled.rawValue, defaultValue: true, transaction: tx.asV2Read)
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

    public func wasGroupCallTooltipShown(withTransaction transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(Key.wasGroupCallTooltipShown.rawValue, defaultValue: false, transaction: transaction.asV2Read)
    }

    public func incrementGroupCallTooltipShownCount() {
        let currentCount = uint(forKey: .wasGroupCallTooltipShownCount, defaultValue: 0)
        let incrementedCount = currentCount + 1

        // If we have shown the tooltip more than 3 times, don't show it again.
        if incrementedCount > 3 {
            SSKEnvironment.shared.databaseStorageRef.write(block: setWasGroupCallTooltipShown(tx:))
        } else {
            setUInt(incrementedCount, forKey: .wasGroupCallTooltipShownCount)
        }
    }

    public func setWasGroupCallTooltipShown(tx: SDSAnyWriteTransaction) {
        setBool(true, forKey: .wasGroupCallTooltipShown, tx: tx)
    }

    public var wasBlurTooltipShown: Bool {
        bool(forKey: .wasBlurTooltipShown, defaultValue: false)
    }

    public func setWasBlurTooltipShown( ) {
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

    public func notificationPreviewType(tx: SDSAnyReadTransaction) -> NotificationType {
        let rawValue = keyValueStore.getUInt(
            Key.notificationPreviewType.rawValue,
            transaction: tx.asV2Read
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

    public func getPushToken(tx: SDSAnyReadTransaction) -> String? {
        return getString(for: .lastRecordedPushToken, tx: tx)
    }

    public func setPushToken(_ value: String, tx: SDSAnyWriteTransaction) {
        setString(value, for: .lastRecordedPushToken, tx: tx)
    }

    public func unsetRecordedAPNSTokens() {
        Logger.warn("Forgetting recorded APNS tokens")
        removeValue(forKey: .lastRecordedPushToken)
    }
}
