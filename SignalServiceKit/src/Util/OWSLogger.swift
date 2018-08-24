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

    open class func verbose(_ logString: @escaping @autoclosure () -> String,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line) {
        #if DEBUG
        OWSLogger.verbose({
            return owsFormatLogMessage(logString(), file: file, function: function, line: line)
        })
        #endif
    }

    open class func debug(_ logString: @escaping @autoclosure () -> String,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
        #if DEBUG
        OWSLogger.debug({
            return owsFormatLogMessage(logString(), file: file, function: function, line: line)
        })
        #endif
    }

    open class func info(_ logString: String,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line) {
        OWSLogger.info({
            return owsFormatLogMessage(logString, file: file, function: function, line: line)
        })
    }

    open class func warn(_ logString: String,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line) {
        OWSLogger.warn({
            return owsFormatLogMessage(logString, file: file, function: function, line: line)
        })
    }

    open class func error(_ logString: String,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
        OWSLogger.error({
            return owsFormatLogMessage(logString, file: file, function: function, line: line)
        })
    }

    open class func flush() {
        OWSLogger.flush()
    }
}
