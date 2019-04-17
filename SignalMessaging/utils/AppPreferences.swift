//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AppPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    private static let store = SDSKeyValueStore(collection: "AppPreferences")

    // MARK: -

    private static let hasDimissedFirstConversationCueKey = "hasDimissedFirstConversationCue"

    @objc
    public static var hasDimissedFirstConversationCue: Bool {
        get {
            return store.getBool(hasDimissedFirstConversationCueKey)
        }
        set {
            store.setBool(newValue, key: hasDimissedFirstConversationCueKey)
        }
    }
}
