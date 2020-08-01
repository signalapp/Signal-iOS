//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSFormat {
    class func formatNSInt(_ value: NSNumber) -> String {
        guard let value = defaultNumberFormatter.string(from: value) else {
            owsFailDebug("Could not format value.")
            return ""
        }
        return value
    }

    class func formatInt(_ value: Int) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    class func formatUInt(_ value: UInt) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    class func formatUInt32(_ value: UInt32) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    class func formatUInt64(_ value: UInt64) -> String {
        return formatNSInt(NSNumber(value: value))
    }
}
