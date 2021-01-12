//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AppPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    private static let collection = "AppPreferences"

    // MARK: -

    private static let hasDimissedFirstConversationCueKey = "hasDimissedFirstConversationCue"

    @objc
    public static var hasDimissedFirstConversationCue: Bool {
        get {
            return getBool(key: hasDimissedFirstConversationCueKey)
        }
        set {
            setBool(newValue, key: hasDimissedFirstConversationCueKey)
        }
    }

    // MARK: -

    private class func getBool(key: String, defaultValue: Bool = false) -> Bool {
        return OWSPrimaryStorage.dbReadConnection().bool(forKey: key, inCollection: collection, defaultValue: defaultValue)
    }

    private class func setBool(_ value: Bool, key: String) {
        OWSPrimaryStorage.dbReadWriteConnection().setBool(value, forKey: key, inCollection: collection)
    }
}
