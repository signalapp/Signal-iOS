//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// UInt64 extension for time unit conversions migrated from Objective-C defines.
extension UInt64 {
    public static let secondInMs: UInt64 = 1000
    public static let minuteInMs: UInt64 = secondInMs * 60
    public static let hourInMs: UInt64 = minuteInMs * 60
    public static let dayInMs: UInt64 = hourInMs * 24
    public static let weekInMs: UInt64 = dayInMs * 7
}
