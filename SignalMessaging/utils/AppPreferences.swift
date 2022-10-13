//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class AppPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    public static let store = SDSKeyValueStore(collection: "AppPreferences")
}
