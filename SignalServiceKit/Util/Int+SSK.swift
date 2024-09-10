//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension UInt32 {
    /// Convert the given millisecond time to seconds.
    ///
    /// - Returns
    /// The millisecond time in seconds, or `nil` if the resulting value would
    /// overflow `UInt32`.
    static func msToSecs(_ millis: UInt64) -> UInt32? {
        let secs: UInt64 = millis / kSecondInMs

        if secs <= UInt32.max {
            return UInt32(secs)
        } else {
            return nil
        }
    }
}

// MARK: -

public extension Int {
    var abbreviatedString: String {
        let value: Double
        let suffix: String
        switch abs(self) {
        case 1_000..<1_000_000:
            value = Double(self) / 1_000
            suffix = "K"
        case 1_000_000..<1_000_000_000:
            value = Double(self) / 1_000_000
            suffix = "M"
        case 1_000_000_000...Int.max:
            value = Double(self) / 1_000_000_000
            suffix = "B"
        default:
            value = Double(self)
            suffix = ""
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.negativeSuffix = suffix
        numberFormatter.positiveSuffix = suffix

        guard let result = numberFormatter.string(for: value) else {
            owsFailDebug("unexpectedly failed to format number")
            return "\(self)"
        }

        return result
    }
}
