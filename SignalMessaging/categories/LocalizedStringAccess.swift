//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension Bundle {
    var app: Bundle {
        get {
            if self.bundleURL.pathExtension == "appex" {
                // the bundle of the main app is located in the same directory as
                // the parent of "PlugIns/MyAppExtension.appex" (the location of the app extensions bundle)
                let url = self.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                if let otherBundle = Bundle(url: url) {
                    return otherBundle
                }
                owsFailDebug("bundle of main app not found")
            }
            return self
        }
    }
}

public func NSLocalizedStringFromAppBundle(_ key: String, tableName: String? = nil, value: String = "", comment: String) -> String {
    return NSLocalizedString(key, tableName: tableName, bundle: .main.app, value: value, comment: comment)
}
