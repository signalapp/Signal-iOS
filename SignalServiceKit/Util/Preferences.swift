//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UIKit

public class Preferences {

    private enum Key: String {
        case screenSecurity = "Screen Security Key"
        case lastRecordedPushToken = "LastRecordedPushToken"
        case callsHideIPAddress = "CallsHideIPAddress"
        case hasDeclinedNoContactsView = "hasDeclinedNoContactsView"
        case shouldShowUnidentifiedDeliveryIndicators = "OWSPreferencesKeyShouldShowUnidentifiedDeliveryIndicators"
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
        static let isFailDebugEnabled = "IsFailDebugEnabled"
    }

    private static let preferencesCollection = "SignalPreferences"
    private let keyValueStore = KeyValueStore(collection: Preferences.preferencesCollection)

    public init() {
        if CurrentAppContext().hasUI {
            CurrentAppContext().appUserDefaults().set(
                UITraitCollection.current.displayScale,
                forKey: UserDefaultsKeys.deviceScale,
            )
        }
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

    public var cachedDeviceScale: CGFloat {
        guard !CurrentAppContext().hasUI else { return UITraitCollection.current.displayScale }

        guard let cachedValue = CurrentAppContext().appUserDefaults().object(forKey: UserDefaultsKeys.deviceScale) as? CGFloat else {
            return UITraitCollection.current.displayScale
        }

        return cachedValue
    }

    // MARK: Calls

    public func isSystemCallLogEnabled(tx: DBReadTransaction) -> Bool? {
        return keyValueStore.getBool(Key.systemCallLogEnabled.rawValue, transaction: tx)
    }

    public func isSystemCallLogEnabledOrDefault(tx: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(Key.systemCallLogEnabled.rawValue, transaction: tx) ?? true
    }

    public func setIsSystemCallLogEnabled(_ value: Bool, tx: DBWriteTransaction) {
        setBool(value, forKey: .systemCallLogEnabled, tx: tx)
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
