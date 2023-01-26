//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class PrefixedLogger {
    private let prefix: String

    public init(prefix: String) {
        self.prefix = prefix
    }

    open func verbose(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.verbose(
            "\(prefix) \(logString())",
            file: file,
            function: function,
            line: line
        )
    }

    open func debug(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.debug(
            "\(prefix) \(logString())",
            file: file,
            function: function,
            line: line
        )
    }

    open func info(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.info(
            "\(prefix) \(logString())",
            file: file,
            function: function,
            line: line
        )
    }

    open func warn(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.warn(
            "\(prefix) \(logString())",
            file: file,
            function: function,
            line: line
        )
    }

    open func error(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.error(
            "\(prefix) \(logString())",
            file: file,
            function: function,
            line: line
        )
    }

    open func flush() {
        Logger.flush()
    }
}
