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
        (self as Date).ows_millisecondsSince1970
    }

    static func ows_millisecondsSince1970(forDate date: NSDate) -> UInt64 {
        date.ows_millisecondsSince1970
    }

    static func ows_millisecondTimeStamp() -> UInt64 {
        Date.ows_millisecondTimestamp()
    }

    static func ows_date(withMillisecondsSince1970 milliseconds: UInt64) -> NSDate {
        NSDate(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    static var distantFutureForMillisecondTimestamp: Date {
        Date.distantFutureForMillisecondTimestamp
    }

    static var distantFutureMillisecondTimestamp: UInt64 {
        Date.distantFutureMillisecondTimestamp
    }

    func isBefore(date: NSDate) -> Bool {
        (self as Date).isBefore(date as Date)
    }

    func isAfterNow() -> Bool {
        (self as Date).isAfterNow
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
        UInt64(timeIntervalSince1970 * 1000)
    }

    static func ows_millisecondTimestamp() -> UInt64 {
        Date().ows_millisecondsSince1970
    }

    init(millisecondsSince1970: UInt64) {
        self.init(timeIntervalSince1970: Double(millisecondsSince1970) / 1000)
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
        self < date
    }

    var isBeforeNow: Bool {
        self < Date()
    }

    func isAfter(_ date: Date) -> Bool {
        self > date
    }

    var isAfterNow: Bool {
        self > Date()
    }

    var formatIntervalSinceNow: String {
        String(format: "%0.3f", abs(timeIntervalSinceNow))
    }
}
