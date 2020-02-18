//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AppPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    public static let store = SDSKeyValueStore(collection: "AppPreferences")

    // MARK: - hasDimissedFirstConversationCue

    private static let hasDimissedFirstConversationCueKey = "hasDimissedFirstConversationCue"

    private static var hasDimissedFirstConversationCueCache: Bool?

    @objc
    public static func hasDimissedFirstConversationCue(transaction: SDSAnyReadTransaction) -> Bool {
        AssertIsOnMainThread()

        if let value = hasDimissedFirstConversationCueCache {
          return value
        }
        let value = store.getBool(hasDimissedFirstConversationCueKey, defaultValue: false, transaction: transaction)
        hasDimissedFirstConversationCueCache = value
        return value
    }

    @objc
    public static func setHasDimissedFirstConversationCue(_ newValue: Bool, transaction: SDSAnyWriteTransaction) {
        AssertIsOnMainThread()

        store.setBool(newValue, key: hasDimissedFirstConversationCueKey, transaction: transaction)
        hasDimissedFirstConversationCueCache = newValue
    }
}
