//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class PrefixedLogger {
    let prefix: String
    let suffix: String

    public static func empty() -> PrefixedLogger {
        return PrefixedLogger(rawPrefix: "")
    }

    public init(prefix: String, suffix: String? = nil) {
        self.prefix = "\(prefix) "
        self.suffix = suffix.map { " \($0)" } ?? ""
    }

    private init(rawPrefix: String, rawSuffix: String? = nil) {
        self.prefix = rawPrefix
        self.suffix = rawSuffix ?? ""
    }

    public func suffixed(with extraSuffix: String) -> PrefixedLogger {
        return PrefixedLogger(
            prefix: prefix,
            suffix: suffix + " \(extraSuffix)",
        )
    }

    open func verbose(
        _ logString: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.verbose(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line,
        )
    }

    open func debug(
        _ logString: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.debug(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line,
        )
    }

    open func info(
        _ logString: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.info(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line,
        )
    }

    open func warn(
        _ logString: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.warn(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line,
        )
    }

    open func error(
        _ logString: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
        Logger.error(
            buildLogString(logString()),
            file: file,
            function: function,
            line: line,
        )
    }

    open func flush() {
        Logger.flush()
    }

    private func buildLogString(_ logString: String) -> String {
        "\(prefix)\(logString)\(suffix)"
    }
}
