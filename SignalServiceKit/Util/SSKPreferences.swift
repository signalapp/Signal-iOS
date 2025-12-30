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

    // MARK: - Badge Count

    private static let includeMutedThreadsInBadgeCount = "includeMutedThreadsInBadgeCount"

    public static func includeMutedThreadsInBadgeCount(transaction: DBReadTransaction) -> Bool {
        return store.getBool(includeMutedThreadsInBadgeCount, defaultValue: false, transaction: transaction)
    }

    public static func setIncludeMutedThreadsInBadgeCount(_ value: Bool, transaction: DBWriteTransaction) {
        store.setBool(value, key: includeMutedThreadsInBadgeCount, transaction: transaction)
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
}
