//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

class MediaTileDateFormatter {
    private static var todayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static var thisYearDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter
    }()

    private static var longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    static func formattedDateString(for date: Date?) -> String? {
        guard let date = date else { return nil }

        let dateIsThisYear = DateUtil.dateIsThisYear(date)
        let dateIsToday = DateUtil.dateIsToday(date)

        if dateIsToday {
            return todayTimeFormatter.string(from: date)
        }

        if dateIsThisYear {
            return thisYearDateFormatter.string(from: date)
        }

        return longDateFormatter.string(from: date)
    }
}
