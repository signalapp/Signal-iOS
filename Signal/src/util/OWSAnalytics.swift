//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

func FormatAnalyticsLocation(file: String, function: String) -> NSString {
    return "\((file as NSString).lastPathComponent):\(function)" as NSString
}

func OWSProdError(_ eventName: String, file: String, function: String, line: Int32) {
    let location = FormatAnalyticsLocation(file: file, function: function)
    OWSAnalytics
        .logEvent(eventName, severity: .error, parameters: nil, location: location.utf8String!, line:line)
}

func OWSProdInfo(_ eventName: String, file: String, function: String, line: Int32) {
    let location = FormatAnalyticsLocation(file: file, function: function)
    OWSAnalytics
        .logEvent(eventName, severity: .info, parameters: nil, location: location.utf8String!, line:line)
}
