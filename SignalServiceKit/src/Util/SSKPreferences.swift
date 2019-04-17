//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    private static let store = SDSKeyValueStore(collection: "SSKPreferences")

    // MARK: -

    private static let areLinkPreviewsEnabledKey = "areLinkPreviewsEnabled"

    @objc
    public static var areLinkPreviewsEnabled: Bool {
        get {
            return store.getBool(areLinkPreviewsEnabledKey, defaultValue: true)
        }
        set {
            store.setBool(newValue, key: areLinkPreviewsEnabledKey)

            SSKEnvironment.shared.syncManager.sendConfigurationSyncMessage()
        }
    }

    // MARK: -

    private static let hasSavedThreadKey = "hasSavedThread"

    @objc
    public static var hasSavedThread: Bool {
        get {
            return store.getBool(hasSavedThreadKey)
        }
        set {
            store.setBool(newValue, key: hasSavedThreadKey)
        }
    }

    @objc
    public class func setHasSavedThread(value: Bool, transaction: YapDatabaseReadWriteTransaction) {
        transaction.setBool(value,
                            forKey: hasSavedThreadKey,
                            inCollection: store.collection)
    }
}
