//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
