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
