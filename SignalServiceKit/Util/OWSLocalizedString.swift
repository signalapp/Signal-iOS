//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Bundle {
    @objc(appBundle)
    var app: Bundle {
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

@inlinable
public func OWSLocalizedString(_ key: String, tableName: String? = nil, value: String = "", comment: String) -> String {
    return NSLocalizedString(key, tableName: tableName, bundle: .main.app, value: value, comment: comment)
}
