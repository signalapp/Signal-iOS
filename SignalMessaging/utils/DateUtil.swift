//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class DateUtil {

    private init() {}

    // MARK: - Formatters

    public static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .short
        return formatter
    }()

    public static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    public static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    public static let monthAndDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M/d")
        return formatter
    }()

    private static let shortDayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("E")
        return formatter
    }()

    private static let otherYearMessageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter
    }()

    private static let thisYearMessageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let thisWeekMessageFormatterShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("E")
        return formatter
    }()

    private static let thisWeekMessageFormatterLong: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    // MARK: Day Comparison

    // Returns the difference in days, ignoring hours, minutes, seconds.
    // If both dates are the same date, returns 0.
    // If firstDate is a day before secondDate, returns 1.
    //
    // Note: Assumes both dates use the "current" calendar.
    public static func daysFrom(firstDate: Date, toSecondDate secondDate: Date) -> Int {
        let calendar = Calendar.current
        guard let days = calendar.dateComponents([.day],
                                                 from: calendar.startOfDay(for: firstDate),
                                                 to: calendar.startOfDay(for: secondDate)).day else {
            owsFailDebug("Invalid result.")
            return 0
        }
        return days
    }

    public static func dateIsOlderThanToday(_ date: Date, now: Date? = nil) -> Bool {
        let dayDifference = daysFrom(firstDate: date, toSecondDate: now ?? Date())
        return dayDifference > 0
    }

    public static func dateIsOlderThanYesterday(_ date: Date, now: Date? = nil) -> Bool {
        let dayDifference = daysFrom(firstDate: date, toSecondDate: now ?? Date())
        return dayDifference > 1
    }

    public static func dateIsOlderThanOneWeek(_ date: Date, now: Date? = nil) -> Bool {
        let dayDifference = daysFrom(firstDate: date, toSecondDate: now ?? Date())
        return dayDifference > 6
    }

    public static func dateIsToday(_ date: Date, now: Date? = nil) -> Bool {
        let dayDifference = daysFrom(firstDate: date, toSecondDate: now ?? Date())
        return dayDifference == 0
    }

    public static func dateIsYesterday(_ date: Date, now: Date? = nil) -> Bool {
        let dayDifference = daysFrom(firstDate: date, toSecondDate: now ?? Date())
        return dayDifference == 1
    }

    public static func dateIsThisYear(_ date: Date, now: Date? = nil) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.year, from: date) == calendar.component(.year, from: now ?? Date())
    }

    // MARK: Generic Date Formats

    public static func formatPastTimestampRelativeToNow(_ pastTimestamp: UInt64) -> String {
        let nowTimestamp = NSDate.ows_millisecondTimeStamp()
        let isFutureTimestamp = pastTimestamp >= nowTimestamp

        let pastDate = NSDate.ows_date(withMillisecondsSince1970: pastTimestamp)
        let dateString: String = {
            if isFutureTimestamp || dateIsToday(pastDate) {
                return OWSLocalizedString("DATE_TODAY", comment: "The current day.")
            } else if dateIsYesterday(pastDate) {
                return OWSLocalizedString("DATE_YESTERDAY", comment: "The day before today.")
            } else {
                return dateFormatter.string(from: pastDate)
            }
        }()
        return dateString.appending(" ").appending(timeFormatter.string(from: pastDate))
    }

    public static func formatTimestampShort(_ timestamp: UInt64) -> String {
        return formatDateShort(NSDate.ows_date(withMillisecondsSince1970: timestamp))
    }

    public static func formatDateShort(_ date: Date) -> String {
        let dayDifference = daysFrom(firstDate: date, toSecondDate: Date())
        let dateIsOlderThanToday = dayDifference > 0
        let dateIsOlderThanOneWeek = dayDifference > 6

        let dateTimeString: String = {
            if !dateIsThisYear(date) {
                return dateFormatter.string(from: date)
            } else if dateIsOlderThanOneWeek {
                return monthAndDayFormatter.string(from: date)
            } else if dateIsOlderThanToday {
                return shortDayOfWeekFormatter.string(from: date)
            } else {
                return formatMessageTimestampForCVC(date.ows_millisecondsSince1970, shouldUseLongFormat: false)
            }
        }()

        return dateTimeString
    }

    public static func formatTimestampAsTime(_ timestamp: UInt64) -> String {
        return formatDateAsTime(NSDate.ows_date(withMillisecondsSince1970: timestamp))
    }

    public static func formatDateAsTime(_ date: Date) -> String {
        return timeFormatter.string(from: date)
    }

    // MARK: Formatting for UI

    // We might receive a message "from the future" due to a bug or
    // malicious sender or a sender whose device time is misconfigured,
    // etc. Clamp message and date headers dates to the past & present.
    private static func clampBeforeNow(_ date: Date) -> Date {
        let nowDate = Date()
        return date < nowDate ? date : nowDate
    }

    public static func formatMessageTimestampForCVC(_ timestamp: UInt64,
                                                    shouldUseLongFormat: Bool) -> String {
        let date = clampBeforeNow(Date(millisecondsSince1970: timestamp))
        let calendar = Calendar.current
        let minutesDiff = calendar.dateComponents([.minute], from: date, to: Date()).minute ?? 0
        if minutesDiff < 1 {
            return OWSLocalizedString("DATE_NOW",
                                     comment: "The present; the current time.")
        } else if minutesDiff <= 60 {
            let shortFormat = OWSLocalizedString("DATE_MINUTES_AGO_%d", tableName: "PluralAware",
                                                comment: "Format string for a relative time, expressed as a certain number of minutes in the past. Embeds {{The number of minutes}}.")
            let longFormat = OWSLocalizedString("DATE_MINUTES_AGO_LONG_%d", tableName: "PluralAware",
                                               comment: "Full format string for a relative time, expressed as a certain number of minutes in the past. Embeds {{The number of minutes}}.")
            let format = shouldUseLongFormat ? longFormat : shortFormat
            return String.localizedStringWithFormat(format, minutesDiff)
        } else {
            return timeFormatter.string(from: date)
        }
    }

    public static func formatDateHeaderForCVC(_ date: Date) -> String {
        let date = clampBeforeNow(date)
        let calendar = Calendar.current
        let monthsDiff = calendar.dateComponents([.month], from: date, to: Date()).month ?? 0
        if monthsDiff >= 6 {
            // Mar 8, 2017
            return dateHeaderOldDateFormatter.string(from: date)
        } else if dateIsOlderThanYesterday(date) {
            // Wed, Mar 3
            return dateHeaderRecentDateFormatter.string(from: date)
        } else {
            // Today / Yesterday
            return dateHeaderRelativeDateFormatter.string(from: date)
        }
    }

    public static func formatTimestampRelatively(_ timestamp: UInt64) -> String {
        let date = clampBeforeNow(Date(millisecondsSince1970: timestamp))
        let calendar = Calendar.current
        let minutesDiff = calendar.dateComponents([.minute], from: date, to: Date()).minute ?? 0
        if minutesDiff < 1 {
            return OWSLocalizedString("DATE_NOW", comment: "The present; the current time.")
        } else {
            let secondsDiff = calendar.dateComponents([.second], from: date, to: Date()).second ?? 0
            return formatDuration(seconds: UInt32(secondsDiff), useShortFormat: true)
        }
    }

    public static func formatDuration(seconds: UInt32, useShortFormat: Bool) -> String {
        let secondsPerMinute: UInt32 = 60
        let secondsPerHour = secondsPerMinute * 60
        let secondsPerDay = secondsPerHour * 24
        let secondsPerWeek = secondsPerDay * 7

        let formatString: String
        let formatReplacement: UInt32

        if seconds < secondsPerMinute { // XX Seconds
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_SECONDS_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of seconds}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5s' not '5 s'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_SECONDS",
                    comment: "{{number of seconds}} embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{5 seconds}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds

        } else if seconds < secondsPerMinute * 3 / 2 { // 1 Minute
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_MINUTES_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of minutes}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5m' not '5 m'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_SINGLE_MINUTE",
                    comment: "{{1 minute}} embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{1 minute}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds / secondsPerMinute

        } else if seconds < secondsPerHour { // Multiple Minutes
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_MINUTES_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of minutes}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5m' not '5 m'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_MINUTES",
                    comment: "{{number of minutes}} embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{5 minutes}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds / secondsPerMinute

        } else if seconds < secondsPerHour * 3 / 2 { // 1 Hour
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_HOURS_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of hours}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5h' not '5 h'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_SINGLE_HOUR",
                    comment: "{{1 hour}} embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{1 hour}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds / secondsPerHour

        } else if seconds < secondsPerDay { // Multiple Hours
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_HOURS_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of hours}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5h' not '5 h'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_HOURS",
                    comment: "{{number of hours}} embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{5 hours}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds / secondsPerHour

        } else if seconds < secondsPerDay * 3 / 2 { // 1 Day
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_DAYS_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of days}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5d' not '5 d'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_SINGLE_DAY",
                    comment: "{{1 day}} embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{1 day}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds / secondsPerDay

        } else if seconds < secondsPerWeek { // Multiple Days
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_DAYS_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of days}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5d' not '5 d'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_DAYS",
                    comment: "{{number of days}} embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{5 days}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds / secondsPerDay

        } else if seconds < secondsPerWeek * 3 / 2 { // 1 Week
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_WEEKS_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of weeks}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5w' not '5 w'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_SINGLE_WEEK",
                    comment: "{{1 week}} embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{1 week}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds / secondsPerWeek

        } else { // Multiple weeks
            if useShortFormat {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_WEEKS_SHORT_FORMAT",
                    comment: "Label text below navbar button, embeds {{number of weeks}}. Must be very short, like 1 or 2 characters, The space is intentionally omitted between the text and the embedded duration so that we get, e.g. '5w' not '5 w'. See other *_TIME_AMOUNT strings"
                )
            } else {
                formatString = OWSLocalizedString(
                    "TIME_AMOUNT_WEEKS",
                    comment: "{{number of weeks}}, embedded in strings, e.g. 'Alice updated disappearing messages expiration to {{5 weeks}}'. See other *_TIME_AMOUNT strings"
                )
            }
            formatReplacement = seconds / secondsPerWeek
        }

        return String(
            format: formatString,
            NumberFormatter.localizedString(from: NSNumber(value: formatReplacement), number: .none)
        )
    }

    private static let dateHeaderRecentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Tue, Jun 6
        formatter.setLocalizedDateFormatFromTemplate("EE, MMM d")
        return formatter
    }()

    private static let dateHeaderOldDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        // Mar 8, 2017
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let dateHeaderRelativeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .short
        // Today / Yesterday
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    public static func isSameDay(timestamp timestamp1: UInt64, timestamp timestamp2: UInt64) -> Bool {
        isSameDay(date: NSDate.ows_date(withMillisecondsSince1970: timestamp1),
                  date: NSDate.ows_date(withMillisecondsSince1970: timestamp2))
    }

    public static func isSameDay(date date1: Date, date date2: Date) -> Bool {
        0 == daysFrom(firstDate: date1, toSecondDate: date2)
    }

    public static func format(interval: TimeInterval) -> String {
        String(format: "%0.3f", interval)
    }
}
