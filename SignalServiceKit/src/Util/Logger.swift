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

    open class func verbose(_ logString: @autoclosure () -> String,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line) {
        guard ShouldLogVerbose() else {
            return
        }
        OWSLogger.verbose(owsFormatLogMessage(logString(), file: file, function: function, line: line))
    }

    open class func debug(_ logString: @autoclosure () -> String,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
        guard ShouldLogDebug() else {
            return
        }
        OWSLogger.debug(owsFormatLogMessage(logString(), file: file, function: function, line: line))
    }

    open class func info(_ logString: @autoclosure () -> String,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line) {
        guard ShouldLogInfo() else {
            return
        }
        OWSLogger.info(owsFormatLogMessage(logString(), file: file, function: function, line: line))
    }

    open class func warn(_ logString: @autoclosure () -> String,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line) {
        guard ShouldLogWarning() else {
            return
        }
        OWSLogger.warn(owsFormatLogMessage(logString(), file: file, function: function, line: line))
    }

    open class func error(_ logString: @autoclosure () -> String,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
        guard ShouldLogError() else {
            return
        }
        OWSLogger.error(owsFormatLogMessage(logString(), file: file, function: function, line: line))
    }

    open class func flush() {
        OWSLogger.flush()
    }
}
