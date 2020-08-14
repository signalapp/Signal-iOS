//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
}
