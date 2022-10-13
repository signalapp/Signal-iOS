//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSOperation {
    /// The preferred error reporting mechanism, ensuring retry behavior has
    /// been specified. If your error has overridden errorUserInfo, be sure it
    /// includes has specified retry behavior using IsRetryableProvider or
    /// with(isRetryable:).
    public func reportError(_ error: Error,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line) {
        if !error.hasIsRetryable {
            let filename = (file as NSString).lastPathComponent
            let location = "[\(filename):\(line) \(function)]"
            Logger.warn("Error without isRetryable: \(type(of: error)) from: \(location)")
        }
        __reportError(error)
    }

    /// Use this if you've verified the error passed in has in fact defined retry behavior, or if you're
    /// comfortable potentially falling back to the default retry behavior (see `NSError.isRetryable`).
    ///
    /// @param `error` may or may not have defined it's retry behavior.
    public func reportError(withUndefinedRetry error: Error) {
        __reportError(error)
    }
}
