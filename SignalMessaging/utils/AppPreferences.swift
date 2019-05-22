//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AppPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    public static let store = SDSKeyValueStore(collection: "AppPreferences")

    // MARK: -

    private static let hasDimissedFirstConversationCueKey = "hasDimissedFirstConversationCue"

    @objc
    public static func hasDimissedFirstConversationCue(transaction: SDSAnyReadTransaction) -> Bool {
        return store.getBool(hasDimissedFirstConversationCueKey, defaultValue: false, transaction: transaction)
    }

    @objc
    public static func setHasDimissedFirstConversationCue(_ newValue: Bool, transaction: SDSAnyWriteTransaction) {
        store.setBool(newValue, key: hasDimissedFirstConversationCueKey, transaction: transaction)
    }
}
