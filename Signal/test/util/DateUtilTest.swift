//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalMessaging

class DateUtilTest: XCTestCase {
    func buildDate(year: Int = 0,
                   month: Int = 0,
                   day: Int = 0,
                   hour: Int = 0,
                   minute: Int = 0,
                   second: Int = 0) -> Date {
        let calendar = Calendar.current
        let timeZone = TimeZone.current
        let dateComponents = DateComponents(calendar: calendar,
                                            timeZone: timeZone,
                                            year: year,
                                            month: month,
                                            day: day,
                                            hour: hour,
                                            minute: minute,
                                            second: second)
        return calendar.date(from: dateComponents)!
    }

    func testDateComparison() {
        let firstDate = Date()
        let sameDate = Date(timeIntervalSinceReferenceDate: firstDate.timeIntervalSinceReferenceDate)
        let laterDate = Date(timeIntervalSinceReferenceDate: firstDate.timeIntervalSinceReferenceDate + 1)

        XCTAssertEqual(firstDate.timeIntervalSinceReferenceDate, sameDate.timeIntervalSinceReferenceDate)
        XCTAssertNotEqual(firstDate.timeIntervalSinceReferenceDate, laterDate.timeIntervalSinceReferenceDate)
        XCTAssertEqual(firstDate, sameDate)
        XCTAssertNotEqual(firstDate, laterDate)
        XCTAssertTrue(firstDate.timeIntervalSinceReferenceDate < laterDate.timeIntervalSinceReferenceDate)
        XCTAssertFalse(firstDate.isBefore(sameDate))
        XCTAssertTrue(firstDate.isBefore(laterDate))
        XCTAssertFalse(laterDate.isBefore(firstDate))
        XCTAssertFalse(firstDate.isAfter(sameDate))
        XCTAssertFalse(firstDate.isAfter(laterDate))
        XCTAssertTrue(laterDate.isAfter(firstDate))
    }

    func testDateComparators() {
        // Use a specific reference date to make this test deterministic,
        // and to avoid failing around midnight, new year's, etc.
        var nowDateComponents = DateComponents()
        nowDateComponents.year = 2015
        nowDateComponents.month = 8
        nowDateComponents.day = 31
        nowDateComponents.hour = 8
        let now = Calendar.current.date(from: nowDateComponents)!

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .long
        Logger.info("now: \(formatter.string(from: now))")

        let oneSecondAgo =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate - kSecondInterval)
        let oneMinuteAgo =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate - kMinuteInterval)
        let oneDayAgo =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate - kDayInterval)
        let threeDaysAgo =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate - kDayInterval * 3)
        let tenDaysAgo =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate - kDayInterval * 10)
        let oneYearAgo =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate - kYearInterval)
        let twoYearsAgo =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate - kYearInterval * 2)

        let oneSecondAhead =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate + kSecondInterval)
        let oneMinuteAhead =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate + kMinuteInterval)
        let oneDayAhead =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate + kDayInterval)
        let threeDaysAhead =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate + kDayInterval * 3)
        let tenDaysAhead =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate + kDayInterval * 10)
        let oneYearAhead =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate + kYearInterval)
        let twoYearsAhead =
            Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate + kYearInterval * 2)

        Logger.info("oneSecondAgo: \(formatter.string(from: oneSecondAgo))")

        XCTAssertTrue(DateUtil.dateIsToday(oneSecondAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsToday(oneMinuteAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(oneDayAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(threeDaysAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(tenDaysAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(oneYearAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(twoYearsAgo, now: now))

        XCTAssertTrue(DateUtil.dateIsToday(oneSecondAhead, now: now))
        XCTAssertTrue(DateUtil.dateIsToday(oneMinuteAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(oneDayAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(threeDaysAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(tenDaysAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(oneYearAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsToday(twoYearsAhead, now: now))

        XCTAssertFalse(DateUtil.dateIsYesterday(oneSecondAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(oneMinuteAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsYesterday(oneDayAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(threeDaysAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(tenDaysAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(oneYearAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(twoYearsAgo, now: now))

        XCTAssertFalse(DateUtil.dateIsYesterday(oneSecondAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(oneMinuteAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(oneDayAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(threeDaysAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(tenDaysAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(oneYearAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsYesterday(twoYearsAhead, now: now))

        XCTAssertFalse(DateUtil.dateIsOlderThanToday(oneSecondAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanToday(oneMinuteAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsOlderThanToday(oneDayAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsOlderThanToday(threeDaysAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsOlderThanToday(tenDaysAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsOlderThanToday(oneYearAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsOlderThanToday(twoYearsAgo, now: now))

        XCTAssertFalse(DateUtil.dateIsOlderThanToday(oneSecondAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanToday(oneMinuteAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanToday(oneDayAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanToday(threeDaysAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanToday(tenDaysAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanToday(oneYearAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanToday(twoYearsAhead, now: now))

        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(oneSecondAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(oneMinuteAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(oneDayAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(threeDaysAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsOlderThanOneWeek(tenDaysAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsOlderThanOneWeek(oneYearAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsOlderThanOneWeek(twoYearsAgo, now: now))

        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(oneSecondAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(oneMinuteAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(oneDayAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(threeDaysAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(tenDaysAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(oneYearAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(twoYearsAhead, now: now))

        XCTAssertTrue(DateUtil.dateIsThisYear(oneSecondAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsThisYear(oneMinuteAgo, now: now))
        XCTAssertTrue(DateUtil.dateIsThisYear(oneDayAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsThisYear(oneYearAgo, now: now))
        XCTAssertFalse(DateUtil.dateIsThisYear(twoYearsAgo, now: now))

        XCTAssertTrue(DateUtil.dateIsThisYear(oneSecondAhead, now: now))
        XCTAssertTrue(DateUtil.dateIsThisYear(oneMinuteAhead, now: now))
        XCTAssertTrue(DateUtil.dateIsThisYear(oneDayAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsThisYear(oneYearAhead, now: now))
        XCTAssertFalse(DateUtil.dateIsThisYear(twoYearsAhead, now: now))
    }

    func testDateComparators_timezoneVMidnight () {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .long

        let yesterdayBeforeMidnight = buildDate(year: 2015, month: 8, day: 10, hour: 23, minute: 55)
        Logger.info("yesterdayBeforeMidnight: \(formatter.string(from: yesterdayBeforeMidnight))")

        let todayAfterMidnight = buildDate(year: 2015, month: 8, day: 11, hour: 0, minute: 5)
        Logger.info("todayAfterMidnight: \(formatter.string(from: todayAfterMidnight))")

        let todayNoon = buildDate(year: 2015, month: 8, day: 11, hour: 12, minute: 0)
        Logger.info("todayNoon: \(formatter.string(from: todayNoon))")

        // Before Midnight, after Midnight.
        XCTAssertFalse(DateUtil.dateIsToday(yesterdayBeforeMidnight, now: todayAfterMidnight))
        XCTAssertTrue(DateUtil.dateIsYesterday(yesterdayBeforeMidnight, now: todayAfterMidnight))
        XCTAssertTrue(DateUtil.dateIsOlderThanToday(yesterdayBeforeMidnight, now: todayAfterMidnight))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(yesterdayBeforeMidnight, now: todayAfterMidnight))
        XCTAssertTrue(DateUtil.dateIsThisYear(yesterdayBeforeMidnight, now: todayAfterMidnight))

        // Before Midnight, noon.
        XCTAssertFalse(DateUtil.dateIsToday(yesterdayBeforeMidnight, now: todayNoon))
        XCTAssertTrue(DateUtil.dateIsYesterday(yesterdayBeforeMidnight, now: todayNoon))
        XCTAssertTrue(DateUtil.dateIsOlderThanToday(yesterdayBeforeMidnight, now: todayNoon))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(yesterdayBeforeMidnight, now: todayNoon))
        XCTAssertTrue(DateUtil.dateIsThisYear(yesterdayBeforeMidnight, now: todayNoon))

        // After Midnight, noon.
        XCTAssertTrue(DateUtil.dateIsToday(todayAfterMidnight, now: todayNoon))
        XCTAssertFalse(DateUtil.dateIsYesterday(todayAfterMidnight, now: todayNoon))
        XCTAssertFalse(DateUtil.dateIsOlderThanToday(todayAfterMidnight, now: todayNoon))
        XCTAssertFalse(DateUtil.dateIsOlderThanOneWeek(todayAfterMidnight, now: todayNoon))
        XCTAssertTrue(DateUtil.dateIsThisYear(todayAfterMidnight, now: todayNoon))
    }

    func testDaysFrom() {
        let date1 = buildDate(year: 2017, month: 5, day: 17, hour: 19, minute: 37, second: 23)
        let date2 = buildDate(year: 2017, month: 5, day: 17, hour: 0, minute: 1, second: 2)
        let date3 = buildDate(year: 2017, month: 5, day: 16, hour: 0, minute: 1, second: 2)
        let date4 = buildDate(year: 2017, month: 5, day: 18, hour: 0, minute: 1, second: 2)
        XCTAssertEqual(0, DateUtil.daysFrom(firstDate: date1, toSecondDate: date2))
        XCTAssertEqual(-1, DateUtil.daysFrom(firstDate: date1, toSecondDate: date3))
        XCTAssertEqual(+1, DateUtil.daysFrom(firstDate: date3, toSecondDate: date1))
        XCTAssertEqual(+1, DateUtil.daysFrom(firstDate: date1, toSecondDate: date4))
        XCTAssertEqual(-1, DateUtil.daysFrom(firstDate: date4, toSecondDate: date1))
    }

    func testFastDaysFrom() {
        let referenceDate = buildDate(year: 2021, month: 9, day: 6, hour: 13, minute: 08, second: 5)
        let date1 = buildDate(year: 2017, month: 5, day: 17, hour: 19, minute: 37, second: 23)
        let date2 = buildDate(year: 2017, month: 5, day: 17, hour: 0, minute: 1, second: 2)
        let date3 = buildDate(year: 2017, month: 5, day: 16, hour: 5, minute: 31, second: 13)
        let date4 = buildDate(year: 2017, month: 5, day: 18, hour: 23, minute: 51, second: 34)

        XCTAssertEqual(1573, DateUtil.daysFrom(firstDate: date1, toSecondDate: referenceDate))
        XCTAssertEqual(1573, DateUtil.daysFrom(firstDate: date2, toSecondDate: referenceDate))
        XCTAssertEqual(1574, DateUtil.daysFrom(firstDate: date3, toSecondDate: referenceDate))
        XCTAssertEqual(1572, DateUtil.daysFrom(firstDate: date4, toSecondDate: referenceDate))
    }
}
