// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

public extension Date {
    var formattedForDisplay: String {
        let dateNow: Date = Date()
        
        guard Calendar.current.isDate(self, equalTo: dateNow, toGranularity: .year) else {
            // Last year formatter: Nov 11 13:32 am, 2017
            return Date.oldDateFormatter.string(from: self)
        }
        
        guard Calendar.current.isDate(self, equalTo: dateNow, toGranularity: .weekOfYear) else {
            // This year formatter: Jun 6 10:12 am
            return Date.thisYearFormatter.string(from: self)
        }
        
        guard Calendar.current.isDate(self, equalTo: dateNow, toGranularity: .day) else {
            // Day of week formatter: Thu 9:11 pm
            return Date.thisWeekFormatter.string(from: self)
        }
        
        guard Calendar.current.isDate(self, equalTo: dateNow, toGranularity: .minute) else {
            // Today formatter: 8:32 am
            return Date.todayFormatter.string(from: self)
        }
        
        return "DATE_NOW".localized()
    }
}

// MARK: - Formatters

fileprivate extension Date {
    static let oldDateFormatter: DateFormatter = {
        let result: DateFormatter = DateFormatter()
        result.locale = Locale.current
        result.dateStyle = .medium
        result.timeStyle = .short
        result.doesRelativeDateFormatting = true
        
        return result
    }()
    
    static let thisYearFormatter: DateFormatter = {
        let result: DateFormatter = DateFormatter()
        result.locale = Locale.current
        
        // Jun 6 10:12 am
        result.dateFormat = "MMM d \(hourFormat)"
        
        return result
    }()
    
    static let thisWeekFormatter: DateFormatter = {
        let result: DateFormatter = DateFormatter()
        result.locale = Locale.current
        
        // Mon 11:36 pm
        result.dateFormat = "EEE \(hourFormat)"
        
        return result
    }()
    
    static let todayFormatter: DateFormatter = {
        let result: DateFormatter = DateFormatter()
        result.locale = Locale.current
        
        // 9:10 am
        result.dateFormat = hourFormat
        
        return result
    }()
    
    static var hourFormat: String {
        guard
            let format: String = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current),
            format.range(of: "a") != nil
        else {
            // If we didn't find 'a' then it's 24-hour time
            return "HH:mm"
        }
        
        // If we found 'a' in the format then it's 12-hour time
        return "h:mm a"
    }
}
