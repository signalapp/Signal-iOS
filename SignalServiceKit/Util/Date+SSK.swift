//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private let httpDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss z"
    return formatter
}()

private let internetDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = .withInternetDateTime
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

@objc
public extension NSDate {
    static func ows_parseFromHTTPDateString(_ string: String) -> NSDate? {
        return httpDateFormatter.date(from: string) as NSDate?
    }

    static func ows_parseFromISO8601String(_ string: String) -> NSDate? {
        return internetDateFormatter.date(from: string) as NSDate?
    }

    var ows_millisecondsSince1970: UInt64 {
        return NSDate.ows_millisecondsSince1970(for: self as Date)
    }

    static var distantFutureForMillisecondTimestamp: Date {
        Date.distantFutureForMillisecondTimestamp
    }

    static var distantFutureMillisecondTimestamp: UInt64 {
        Date.distantFutureMillisecondTimestamp
    }
}

public extension Date {
    static func ows_parseFromHTTPDateString(_ string: String) -> Date? {
        return NSDate.ows_parseFromHTTPDateString(string) as Date?
    }

    static func ows_parseFromISO8601String(_ string: String) -> Date? {
        return NSDate.ows_parseFromISO8601String(string) as Date?
    }

    var ows_millisecondsSince1970: UInt64 {
        return (self as NSDate).ows_millisecondsSince1970
    }

    static func ows_millisecondTimestamp() -> UInt64 {
        return NSDate.ows_millisecondTimeStamp()
    }

    init(millisecondsSince1970: UInt64) {
        self = NSDate.ows_date(withMillisecondsSince1970: millisecondsSince1970) as Date
    }

    static var distantFutureForMillisecondTimestamp: Date {
        // Pick a value that's representable as both a UInt64 and an NSTimeInterval.
        let millis: UInt64 = 1 << 50
        let result = Date(millisecondsSince1970: millis)
        owsAssertDebug(millis == result.ows_millisecondsSince1970)
        return result
    }

    static var distantFutureMillisecondTimestamp: UInt64 {
        distantFutureForMillisecondTimestamp.ows_millisecondsSince1970
    }

    func isBefore(_ date: Date) -> Bool {
        (self as NSDate).is(before: date)
    }

    var isBeforeNow: Bool {
        (self as NSDate).isBeforeNow()
    }

    func isAfter(_ date: Date) -> Bool {
        (self as NSDate).is(after: date)
    }

    var isAfterNow: Bool {
        (self as NSDate).isAfterNow()
    }

    var formatIntervalSinceNow: String {
        String(format: "%0.3f", abs(timeIntervalSinceNow))
    }
}
