//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension DateUtil {

    @objc
    public static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    // Returns the difference in days, ignoring hours, minutes, seconds.
    // If both dates are the same date, returns 0.
    // If firstDate is a day before secondDate, returns 1.
    //
    // Note: Assumes both dates use the "current" calendar.
    @objc
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

    // Returns the difference in years, ignoring shorter units of time.
    // If both dates fall in the same year, returns 0.
    // If firstDate is from the year before secondDate, returns 1.
    //
    // Note: Assumes both dates use the "current" calendar.
    @objc
    public static func yearsFrom(firstDate: Date, toSecondDate secondDate: Date) -> Int {
        let calendar = Calendar.current
        let units: Set<Calendar.Component> = [.era, .year]
        var components1 = calendar.dateComponents(units, from: firstDate)
        var components2 = calendar.dateComponents(units, from: secondDate)
        components1.hour = 12
        components2.hour = 12
        guard let date1 = calendar.date(from: components1),
              let date2 = calendar.date(from: components2) else {
            owsFailDebug("Invalid date.")
            return 0
        }
        guard let result = calendar.dateComponents([.year], from: date1, to: date2).year else {
            owsFailDebug("Missing result.")
            return 0
        }
        return result
    }

    // We might receive a message "from the future" due to a bug or
    // malicious sender or a sender whose device time is misconfigured,
    // etc. Clamp message and date headers dates to the past & present.
    private static func clampBeforeNow(_ date: Date) -> Date {
        let nowDate = Date()
        return date < nowDate ? date : nowDate
    }

    @objc
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

    @objc
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
            return NSString.formatDurationSeconds(UInt32(secondsDiff), useShortFormat: true)
        }
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

    @objc(isSameDayWithTimestamp:timestamp:)
    public static func isSameDay(timestamp timestamp1: UInt64, timestamp timestamp2: UInt64) -> Bool {
        isSameDay(date: NSDate.ows_date(withMillisecondsSince1970: timestamp1),
                  date: NSDate.ows_date(withMillisecondsSince1970: timestamp2))
    }

    @objc(isSameDayWithDate:date:)
    public static func isSameDay(date date1: Date, date date2: Date) -> Bool {
        0 == daysFrom(firstDate: date1, toSecondDate: date2)
    }

    public static func format(interval: TimeInterval) -> String {
        String(format: "%0.3f", interval)
    }
}
