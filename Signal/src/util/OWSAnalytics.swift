//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

func OWSProdError(_ eventName: String, file: String, function: String, line: Int32) {
    let location = "\((file as NSString).lastPathComponent):\(function)"
    OWSAnalytics
        .logEvent(eventName, severity: .error, parameters: nil, location: (location as NSString).utf8String!, line:line)
}
