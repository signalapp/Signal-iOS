//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AppPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    public static let store = SDSKeyValueStore(collection: "AppPreferences")
}
