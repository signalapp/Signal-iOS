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
        return UInt32(exactly: millis / UInt64.secondInMs)
    }
}

// MARK: - Safe Casts

// Casts that can't fail and will complain if they become unsafe or redundant.

extension UInt64 {
    public init(safeCast source: UInt) { self = UInt64(source) }
    public init(safeCast source: UInt8) { self = UInt64(source) }
    public init(safeCast source: UInt16) { self = UInt64(source) }
    public init(safeCast source: UInt32) { self = UInt64(source) }
    // It's safe to cast a UInt64 from a UInt64, but we shouldn't.
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
