//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public class SSKPreferences: NSObject {

    public static let store = KeyValueStore(collection: "SSKPreferences")

    private var store: KeyValueStore {
        return SSKPreferences.store
    }

    // MARK: -

    private static var areLegacyLinkPreviewsEnabledKey: String { "areLegacyLinkPreviewsEnabled" }

    // The following two methods are just to make sure we can store and forward in storage service updates
    public static func areLegacyLinkPreviewsEnabled(transaction: DBReadTransaction) -> Bool {
        return store.getBool(areLegacyLinkPreviewsEnabledKey, defaultValue: true, transaction: transaction)
    }

    public static func setAreLegacyLinkPreviewsEnabled(_ newValue: Bool, transaction: DBWriteTransaction) {
        store.setBool(newValue, key: areLegacyLinkPreviewsEnabledKey, transaction: transaction)
    }

    // MARK: -

    private static var areIntentDonationsEnabledKey: String { "areSharingSuggestionsEnabled" }

    @objc
    public static func areIntentDonationsEnabled(transaction: DBReadTransaction) -> Bool {
        return store.getBool(areIntentDonationsEnabledKey, defaultValue: true, transaction: transaction)
    }

    @objc
    public static func setAreIntentDonationsEnabled(_ newValue: Bool, transaction: DBWriteTransaction) {
        store.setBool(newValue, key: areIntentDonationsEnabledKey, transaction: transaction)
    }

    // MARK: -

    @objc
    public static func hasSavedThread(transaction: DBReadTransaction) -> Bool {
        return SSKEnvironment.shared.sskPreferencesRef.hasSavedThread(transaction: transaction)
    }

    @objc
    public static func setHasSavedThread(_ newValue: Bool, transaction: DBWriteTransaction) {
        SSKEnvironment.shared.sskPreferencesRef.setHasSavedThread(newValue, transaction: transaction)
    }

    private let hasSavedThreadKey = "hasSavedThread"
    // Only access this queue within db transactions.
    private var hasSavedThreadCache: Bool?

    @objc
    public func hasSavedThread(transaction: DBReadTransaction) -> Bool {
        if let value = hasSavedThreadCache {
            return value
        }
        let value = store.getBool(hasSavedThreadKey, defaultValue: false, transaction: transaction)
        hasSavedThreadCache = value
        return value
    }

    @objc
    public func setHasSavedThread(_ newValue: Bool, transaction: DBWriteTransaction) {
        store.setBool(newValue, key: hasSavedThreadKey, transaction: transaction)
        hasSavedThreadCache = newValue
    }

    // MARK: -

    private static var didDropYdbKey: String { "didDropYdb" }
    private static var didEverUseYdbKey: String { "didEverUseYdb" }

    @objc
    public static func clearLegacyDatabaseFlags(from userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: didDropYdbKey)
        userDefaults.removeObject(forKey: didEverUseYdbKey)
    }

    // MARK: - Profile avatar preference

    @objc
    public static let preferContactAvatarsPreferenceDidChange = Notification.Name("PreferContactAvatarsPreferenceDidChange")
    private static var preferContactAvatarsKey: String { "preferContactAvatarsKey" }
    private static var preferContactAvatarsCached: Bool?

    @objc
    public static func preferContactAvatars(transaction: DBReadTransaction) -> Bool {
        if let value = preferContactAvatarsCached { return value }
        let value = store.getBool(preferContactAvatarsKey, defaultValue: false, transaction: transaction)
        preferContactAvatarsCached = value
        return value
    }

    @objc
    public static func setPreferContactAvatars(
        _ value: Bool,
        updateStorageService: Bool = true,
        transaction: DBWriteTransaction,
    ) {

        let oldValue = store.getBool(preferContactAvatarsKey, transaction: transaction)
        store.setBool(value, key: preferContactAvatarsKey, transaction: transaction)
        preferContactAvatarsCached = value

        if oldValue != value {
            if updateStorageService {
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
            }
            NotificationCenter.default.postOnMainThread(name: Self.preferContactAvatarsPreferenceDidChange, object: nil)
        }
    }

    // MARK: -

    public class var grdbSchemaVersionDefault: UInt {
        return GRDBSchemaMigrator.grdbSchemaVersionDefault
    }

    public class var grdbSchemaVersionLatest: UInt {
        return GRDBSchemaMigrator.grdbSchemaVersionLatest
    }

    private static var grdbSchemaVersionKey: String { "grdbSchemaVersion" }

    private static func grdbSchemaVersion() -> UInt {
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        guard let preference = appUserDefaults.object(forKey: grdbSchemaVersionKey) as? NSNumber else {
            return grdbSchemaVersionDefault
        }
        return preference.uintValue
    }

    private static func setGrdbSchemaVersion(_ value: UInt) {
        let lastKnownGrdbSchemaVersion = grdbSchemaVersion()
        guard value != lastKnownGrdbSchemaVersion else {
            return
        }
        guard value > lastKnownGrdbSchemaVersion else {
            owsFailDebug("Reverting to earlier schema version: \(value)")
            return
        }
        Logger.info("Updating schema version: \(lastKnownGrdbSchemaVersion) -> \(value)")
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        appUserDefaults.set(value, forKey: grdbSchemaVersionKey)
        appUserDefaults.synchronize()
    }

    @objc
    public static func markGRDBSchemaAsLatest() {
        setGrdbSchemaVersion(grdbSchemaVersionLatest)
    }

    @objc
    public static func hasUnknownGRDBSchema() -> Bool {
        guard grdbSchemaVersion() <= grdbSchemaVersionLatest else {
            owsFailDebug("grdbSchemaVersion: \(grdbSchemaVersion()), grdbSchemaVersionLatest: \(grdbSchemaVersionLatest)")
            return true
        }
        return false
    }

    // MARK: - Keep Muted Chats Archived

    private static var shouldKeepMutedChatsArchivedKey: String { "shouldKeepMutedChatsArchived" }

    @objc
    public static func shouldKeepMutedChatsArchived(transaction: DBReadTransaction) -> Bool {
        return store.getBool(shouldKeepMutedChatsArchivedKey, defaultValue: false, transaction: transaction)
    }

    @objc
    public static func setShouldKeepMutedChatsArchived(_ newValue: Bool, transaction: DBWriteTransaction) {
        store.setBool(newValue, key: shouldKeepMutedChatsArchivedKey, transaction: transaction)
    }

    // MARK: - Double Tap

    public enum DoubleTapOthersMessagesAction: String, CaseIterable {
        case react
        case reply
        case off
    }

    public enum DoubleTapOwnMessagesAction: String, CaseIterable {
        case edit
        case reply
        case off
    }

    private static var doubleTapOthersMessagesActionKey: String { "doubleTapOthersMessagesAction" }
    private static var doubleTapOwnMessagesActionKey: String { "doubleTapOwnMessagesAction" }

    /// Default: react.
    public static func doubleTapOthersMessagesAction(transaction: DBReadTransaction) -> DoubleTapOthersMessagesAction {
        stringPref(DoubleTapOthersMessagesAction.self, key: doubleTapOthersMessagesActionKey, default: .react, transaction: transaction)
    }

    public static func setDoubleTapOthersMessagesAction(
        _ action: DoubleTapOthersMessagesAction,
        transaction: DBWriteTransaction,
    ) {
        store.setString(action.rawValue, key: doubleTapOthersMessagesActionKey, transaction: transaction)
    }

    /// Default: edit (existing double-tap-to-edit).
    public static func doubleTapOwnMessagesAction(transaction: DBReadTransaction) -> DoubleTapOwnMessagesAction {
        stringPref(DoubleTapOwnMessagesAction.self, key: doubleTapOwnMessagesActionKey, default: .edit, transaction: transaction)
    }

    public static func setDoubleTapOwnMessagesAction(
        _ action: DoubleTapOwnMessagesAction,
        transaction: DBWriteTransaction,
    ) {
        store.setString(action.rawValue, key: doubleTapOwnMessagesActionKey, transaction: transaction)
    }

    private static var doubleTapReactStickersEnabledKey: String { "doubleTapReactStickersEnabled" }
    private static var doubleTapReactPhotosEnabledKey: String { "doubleTapReactPhotosEnabled" }

    /// Default: true. When false, double-tap React skips sticker messages.
    public static func isDoubleTapReactEnabledForStickers(transaction: DBReadTransaction) -> Bool {
        store.getBool(doubleTapReactStickersEnabledKey, defaultValue: true, transaction: transaction)
    }

    public static func setDoubleTapReactEnabledForStickers(_ value: Bool, transaction: DBWriteTransaction) {
        store.setBool(value, key: doubleTapReactStickersEnabledKey, transaction: transaction)
    }

    /// Default: true. When false, double-tap React skips photo/video (body media) messages.
    public static func isDoubleTapReactEnabledForPhotos(transaction: DBReadTransaction) -> Bool {
        store.getBool(doubleTapReactPhotosEnabledKey, defaultValue: true, transaction: transaction)
    }

    public static func setDoubleTapReactEnabledForPhotos(_ value: Bool, transaction: DBWriteTransaction) {
        store.setBool(value, key: doubleTapReactPhotosEnabledKey, transaction: transaction)
    }

    private static func stringPref<T: RawRepresentable>(
        _ type: T.Type,
        key: String,
        default defaultValue: T,
        transaction: DBReadTransaction,
    ) -> T where T.RawValue == String {
        if let raw = store.getString(key, transaction: transaction), let value = T(rawValue: raw) {
            return value
        }
        return defaultValue
    }
}
