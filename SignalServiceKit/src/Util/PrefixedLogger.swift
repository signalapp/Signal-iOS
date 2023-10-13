//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class PrefixedLogger {
    private let prefix: String
    private var suffix: String

    public init(prefix: String, suffix: String? = nil) {
        self.prefix = prefix
        self.suffix = suffix ?? ""
    }

    public func suffixed(with extraSuffix: String) -> PrefixedLogger {
        return PrefixedLogger(
            prefix: prefix,
            suffix: suffix + extraSuffix
        )
    }

    open func verbose(
        _ logString: @autoclosure () -> String,
        flushImmediately: Bool = false,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.verbose(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line
        )

        if flushImmediately { flush() }
    }

    open func debug(
        _ logString: @autoclosure () -> String,
        flushImmediately: Bool = false,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.debug(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line
        )

        if flushImmediately { flush() }
    }

    open func info(
        _ logString: @autoclosure () -> String,
        flushImmediately: Bool = false,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.info(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line
        )

        if flushImmediately { flush() }
    }

    open func warn(
        _ logString: @autoclosure () -> String,
        flushImmediately: Bool = false,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.warn(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line
        )

        if flushImmediately { flush() }
    }

    open func error(
        _ logString: @autoclosure () -> String,
        flushImmediately: Bool = false,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.error(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line
        )

        if flushImmediately { flush() }
    }

    open func flush() {
        Logger.flush()
    }

    private func buildLogString(_ logString: String) -> String {
        "\(prefix) \(logString) \(suffix)"
    }
}
