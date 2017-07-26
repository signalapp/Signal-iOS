//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
//import PromiseKit
//import WebRTC

// MARK: Helpers

/**
 * We synchronize access to state in this class using this queue.
 */
func assertOnQueue(_ queue: DispatchQueue) {
    if #available(iOS 10.0, *) {
        dispatchPrecondition(condition: .onQueue(queue))
    } else {
        // Skipping check on <iOS10, since syntax is different and it's just a development convenience.
    }
}

func owsFail(_ message: String) {
    Logger.error(message)
    Logger.flush()
    assertionFailure(message)
}

// Example: OWSProdError("blah", #file, #function, #line)
func OWSProdError(_ eventName: String, file: String, function: String, line: Int32) {
    let location = "\((file as NSString).lastPathComponent):\(function)"
    OWSAnalytics
        .logEvent(eventName, severity: .error, parameters: nil, location: (location as NSString).utf8String!, line:line)
}
