//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Log an error message. Additionally, crashes in prerelease builds.
@inlinable
public func owsFailBeta(
    _ logMessage: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    if FeatureFlags.isPrerelease {
        owsFail(logMessage, file: file, function: function, line: line)
    } else {
        Logger.error(logMessage, file: file, function: function, line: line)
    }
}

/// Check an assertion. If the assertion fails, log an error message. Additionally, crashes in
/// prerelease builds.
@inlinable
public func owsAssertBeta(
    _ condition: Bool,
    _ message: @autoclosure () -> String = String(),
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    if !condition {
        let message: String = message()
        owsFailBeta(
            message.isEmpty ? "Assertion failed." : message,
            file: file,
            function: function,
            line: line
        )
    }
}
