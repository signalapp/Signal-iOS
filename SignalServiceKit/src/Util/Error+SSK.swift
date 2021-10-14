//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension Error {
    public func hasFatalStatusCode() -> Bool {
        guard let statusCode = self.httpStatusCode else {
            return false
        }
        if statusCode == 429 {
            // "Too Many Requests", retry with backoff.
            return false
        }
        return 400 <= statusCode && statusCode <= 499
    }
}

// MARK: -

extension NSError {
    @objc
    public func httpRetryAfterDate() -> Date? {
        guard let httpError = self as? HTTPError else {
            return nil
        }
        return httpError.responseHeaders?.retryAfterDate
    }

    @objc
    public func matchesDomainAndCode(of other: NSError) -> Bool {
        other.hasDomain(domain, code: code)
    }

    @objc
    public func hasDomain(_ domain: String, code: Int) -> Bool {
        self.domain == domain && self.code == code
    }
}

// MARK: -

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
