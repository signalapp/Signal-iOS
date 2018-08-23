//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// Once we're on Swift4.2 we can mark this as inlineable
// @inlinable
public func owsFormatLogMessage(_ logString: String,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) -> String {
    let filename = (file as NSString).lastPathComponent
    // We format the filename & line number in a format compatible
    // with XCode's "Open Quickly..." feature.
    return "[\(filename):\(line) \(function)]: \(logString)"
}

/**
 * A minimal DDLog wrapper for swift.
 */
open class Logger: NSObject {

    open class func verbose(_ logString: String,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line) {
        let message = owsFormatLogMessage(logString, file: file, function: function, line: line)
        OWSLogger.verbose(message)
    }

    open class func debug(_ logString: String,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
        let message = owsFormatLogMessage(logString, file: file, function: function, line: line)
        OWSLogger.debug(message)
    }

    open class func info(_ logString: String,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line) {
        let message = owsFormatLogMessage(logString, file: file, function: function, line: line)
        OWSLogger.info(message)
    }

    open class func warn(_ logString: String,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line) {
        let message = owsFormatLogMessage(logString, file: file, function: function, line: line)
        OWSLogger.warn(message)
    }

    open class func error(_ logString: String,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
        let message = owsFormatLogMessage(logString, file: file, function: function, line: line)
        OWSLogger.error(message)
    }

    open class func flush() {
        OWSLogger.flush()
    }
}
