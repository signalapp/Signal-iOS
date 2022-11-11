//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Locale {
    var isCJKV: Bool {
        guard let languageCode = languageCode else { return false }
        return ["zk", "zh", "ja", "ko", "vi"].contains(languageCode)
    }
}

@objc
public extension NSLocale {
    var isCJKV: Bool {
        return (self as Locale).isCJKV
    }
}
