//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    public static let store = SDSKeyValueStore(collection: "SSKPreferences")

    // MARK: -

    private static let areLinkPreviewsEnabledKey = "areLinkPreviewsEnabled"

    @objc
    public static func areLinkPreviewsEnabled(transaction: SDSAnyReadTransaction) -> Bool {
        return store.getBool(areLinkPreviewsEnabledKey, defaultValue: true, transaction: transaction)
    }

    @objc
    public static func setAreLinkPreviewsEnabled(_ newValue: Bool, transaction: SDSAnyWriteTransaction) {
        store.setBool(newValue, key: areLinkPreviewsEnabledKey, transaction: transaction)
        SSKEnvironment.shared.syncManager.sendConfigurationSyncMessage()
    }

    // MARK: -

    private static let hasSavedThreadKey = "hasSavedThread"

    @objc
    public static func hasSavedThread(transaction: SDSAnyReadTransaction) -> Bool {
        return store.getBool(hasSavedThreadKey, defaultValue: false, transaction: transaction)
    }

    @objc
    public static func setHasSavedThread(_ newValue: Bool, transaction: SDSAnyWriteTransaction) {
        store.setBool(newValue, key: hasSavedThreadKey, transaction: transaction)
    }

    // MARK: -

    private static let isYdbMigratedKey = "isYdbMigrated1"

    @objc
    public static func isYdbMigrated() -> Bool {
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        guard let preference = appUserDefaults.object(forKey: isYdbMigratedKey) as? NSNumber else {
            return false
        }
        return preference.boolValue
    }

    @objc
    public static func setIsYdbMigrated() {
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        appUserDefaults.set(true, forKey: isYdbMigratedKey)
        appUserDefaults.synchronize()
    }
}
