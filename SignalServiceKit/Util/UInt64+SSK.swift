//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension UInt64 {
    public static let secondInMs: UInt64 = 1000
    public static let minuteInMs: UInt64 = secondInMs * 60
    public static let hourInMs: UInt64 = minuteInMs * 60
    public static let dayInMs: UInt64 = hourInMs * 24
    public static let weekInMs: UInt64 = dayInMs * 7
}

extension UInt64 {
    public static let kilobyte: UInt64 = 1000
    public static let kibibyte: UInt64 = 1024
    public static let megabyte: UInt64 = kilobyte * 1000
    public static let mebibyte: UInt64 = kibibyte * 1024
    public static let gigabyte: UInt64 = megabyte * 1000
    public static let gibibyte: UInt64 = mebibyte * 1024
    public static let terabyte: UInt64 = gigabyte * 1000
    public static let tebibyte: UInt64 = gibibyte * 1024
}

extension UInt64 {
    init(clamping double: Double) {
        self = switch double {
        case _ where double.isNaN: 0
        case ...0: 0
        case Double(UInt64.max)...: UInt64.max
        default: UInt64(double)
        }
    }
}
