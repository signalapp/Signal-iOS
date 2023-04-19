//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import CFNetwork

extension HTTPUtils {

    // This DRYs up handling of main service errors
    // so that REST and websocket errors are handled
    // in the same way.
    public static func preprocessMainServiceHTTPError(request: TSRequest,
                                                      requestUrl: URL,
                                                      responseStatus: Int,
                                                      responseHeaders: OWSHttpHeaders,
                                                      responseError: Error?,
                                                      responseData: Data?) -> OWSHTTPError {
        let httpError = HTTPUtils.buildServiceError(request: request,
                                                    requestUrl: requestUrl,
                                                    responseStatus: responseStatus,
                                                    responseHeaders: responseHeaders,
                                                    responseError: responseError,
                                                    responseData: responseData)

        applyHTTPError(httpError)

#if TESTABLE_BUILD
        HTTPUtils.logCurl(for: request as URLRequest)
#endif

        return httpError
    }

    // This DRYs up handling of main service errors so that
    // REST and websocket errors are handled in the same way.
    public static func applyHTTPError(_ httpError: OWSHTTPError) {

        if httpError.isNetworkConnectivityError {
            Self.outageDetection.reportConnectionFailure()
        }

        if httpError.responseStatusCode == AppExpiry.appExpiredStatusCode {
            appExpiry.setHasAppExpiredAtCurrentVersion(db: DependenciesBridge.shared.db)
        }
    }

    private static func buildServiceError(request: TSRequest,
                                          requestUrl: URL,
                                          responseStatus: Int,
                                          responseHeaders: OWSHttpHeaders,
                                          responseError: Error?,
                                          responseData: Data?) -> OWSHTTPError {

        var errorDescription = "URL: \(request.httpMethod) \(requestUrl.absoluteString), status: \(responseStatus)"
        if let responseError = responseError {
            errorDescription += ", error: \(responseError)"
        }
        let retryAfterDate: Date? = responseHeaders.retryAfterDate
        func buildServiceResponseError(description: String? = nil,
                                       recoverySuggestion: String? = nil) -> OWSHTTPError {
            .forServiceResponse(requestUrl: requestUrl,
                                responseStatus: responseStatus,
                                responseHeaders: responseHeaders,
                                responseError: responseError,
                                responseData: responseData,
                                customRetryAfterDate: retryAfterDate,
                                customLocalizedDescription: description,
                                customLocalizedRecoverySuggestion: recoverySuggestion)
        }

        switch responseStatus {
        case 0:
            Logger.warn("The network request failed because of a connectivity error: \(request.httpMethod) \(requestUrl.absoluteString)")
            let error = OWSHTTPError.networkFailure(requestUrl: requestUrl)
            return error
        case 400:
            Logger.warn("The request contains an invalid parameter: \(errorDescription)")
            return buildServiceResponseError()
        case 401:
            Logger.warn("The server returned an error about the authorization header: \(errorDescription)")
            return buildServiceResponseError()
        case 402:
            return buildServiceResponseError()
        case 403:
            Logger.warn("The server returned an authentication failure: \(errorDescription)")
            return buildServiceResponseError()
        case 404:
            Logger.warn("The requested resource could not be found: \(errorDescription)")
            return buildServiceResponseError()
        case 411:
            Logger.info("Device limit exceeded: \(errorDescription)")
            return buildServiceResponseError()
        case 413, 429:
            Logger.warn("Rate limit exceeded: \(request.httpMethod) \(requestUrl.absoluteString)")
            let description = OWSLocalizedString("REGISTER_RATE_LIMITING_ERROR", comment: "")
            let recoverySuggestion = OWSLocalizedString("REGISTER_RATE_LIMITING_BODY", comment: "")
            let error = buildServiceResponseError(description: description,
                                                  recoverySuggestion: recoverySuggestion)
            return error
        case 417:
            // TODO: Is this response code obsolete?
            Logger.warn("The number is already registered on a relay. Please unregister there first: \(request.httpMethod) \(requestUrl.absoluteString)")
            let description = OWSLocalizedString("REGISTRATION_ERROR", comment: "")
            let recoverySuggestion = OWSLocalizedString("RELAY_REGISTERED_ERROR_RECOVERY", comment: "")
            let error = buildServiceResponseError(description: description,
                                                  recoverySuggestion: recoverySuggestion)
            return error
        case 422:
            Logger.error("The registration was requested over an unknown transport: \(errorDescription)")
            return buildServiceResponseError()
        default:
            Logger.warn("Unknown error: \(responseStatus), \(errorDescription)")
            return buildServiceResponseError()
        }
    }
}

// MARK: -

public extension Error {
    var httpRetryAfterDate: Date? {
        HTTPUtils.httpRetryAfterDate(forError: self)
    }

    var httpResponseData: Data? {
        HTTPUtils.httpResponseData(forError: self)
    }

    var httpStatusCode: Int? {
        HTTPUtils.httpStatusCode(forError: self)
    }

    var httpRequestUrl: URL? {
        guard let error = self as? HTTPError else {
            return nil
        }
        return error.requestUrl
    }

    var httpResponseHeaders: OWSHttpHeaders? {
        guard let error = self as? HTTPError else {
            return nil
        }
        return error.responseHeaders
    }

    var httpResponseJson: Any? {
        guard let data = httpResponseData else {
            return nil
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json
        } catch {
            owsFailDebug("Could not parse JSON: \(error).")
            return nil
        }
    }

    var isNetworkConnectivityFailure: Bool {
        HTTPUtils.isNetworkConnectivityFailure(forError: self)
    }

    func hasFatalHttpStatusCode() -> Bool {
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

public extension NSError {
    @objc
    @available(swift, obsoleted: 1.0)
    var httpStatusCode: NSNumber? {
        guard let statusCode = HTTPUtils.httpStatusCode(forError: self) else {
            return nil
        }
        owsAssertDebug(statusCode > 0)
        return NSNumber(value: statusCode)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    var isNetworkConnectivityFailure: Bool {
        HTTPUtils.isNetworkConnectivityFailure(forError: self)
    }
}

// MARK: -

// This extension contains the canonical implementations for
// extracting various HTTP metadata from errors.  They should
// only be called from the convenience accessors on Error and
// NSError above.
fileprivate extension HTTPUtils {
    static func httpRetryAfterDate(forError error: Error) -> Date? {
        guard let httpError = error as? OWSHTTPError else {
            return nil
        }
        if let retryAfterDate = httpError.customRetryAfterDate {
            return retryAfterDate
        }
        if let retryAfterDate = httpError.responseHeaders?.retryAfterDate {
            return retryAfterDate
        }
        if let responseError = httpError.responseError {
            return httpRetryAfterDate(forError: responseError)
        }
        return nil
    }

    static func httpResponseData(forError error: Error) -> Data? {
        guard let httpError = error as? OWSHTTPError else {
            return nil
        }
        if let responseData = httpError.responseBodyData {
            return responseData
        }
        if let responseError = httpError.responseError {
            return httpResponseData(forError: responseError)
        }
        return nil
    }

    static func httpStatusCode(forError error: Error) -> Int? {
        guard let httpError = error as? OWSHTTPError else {
            return nil
        }
        let statusCode = httpError.responseStatusCode
        guard statusCode > 0 else {
            return nil
        }
        return statusCode
    }

    static func isNetworkConnectivityFailure(forError error: Error?) -> Bool {
        guard let error = error else {
            return false
        }

        if (error as NSError).domain == NSURLErrorDomain {
            guard let cvNetworkError = CFNetworkErrors(rawValue: Int32((error as NSError).code)) else {
                return false
            }
            switch cvNetworkError {
            case .cfurlErrorTimedOut,
                    .cfurlErrorCannotConnectToHost,
                    .cfurlErrorNetworkConnectionLost,
                    .cfurlErrorDNSLookupFailed,
                    .cfurlErrorNotConnectedToInternet,
                    .cfurlErrorSecureConnectionFailed,
                    .cfurlErrorCannotLoadFromNetwork,
                    .cfurlErrorCannotFindHost,
                    .cfurlErrorBadURL:
                return true
            default:
                return false
            }
        }

        let isNetworkProtocolError = (error as NSError).domain == NSPOSIXErrorDomain && (error as NSError).code == 100
        if isNetworkProtocolError {
            return true
        }

        switch error {
        case let httpError as OWSHTTPError:
            return httpError.isNetworkConnectivityError
        case GroupsV2Error.timeout:
            return true
        case PaymentsError.timeout:
            return true
        default:
            return false
        }
    }
}

// MARK: -

@inlinable
public func owsFailDebugUnlessNetworkFailure(_ error: Error,
                                             file: String = #file,
                                             function: String = #function,
                                             line: Int = #line) {
    if error.isNetworkConnectivityFailure {
        // Log but otherwise ignore network failures.
        Logger.warn("Error: \(error)", file: file, function: function, line: line)
    } else {
        owsFailDebug("Error: \(error)", file: file, function: function, line: line)
    }
}

@inlinable
public func owsFailBetaUnlessNetworkFailure(
    _ error: Error,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    if error.isNetworkConnectivityFailure {
        // Log but otherwise ignore network failures.
        Logger.warn("Error: \(error)", file: file, function: function, line: line)
    } else {
        owsFailBeta("Error: \(error)", file: file, function: function, line: line)
    }
}

// MARK: -

extension NSError {
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

extension OWSHttpHeaders {

    // fallback retry-after delay if we fail to parse a non-empty retry-after string
    private static var kOWSFallbackRetryAfter: TimeInterval { 60 }
    private static var kOWSRetryAfterHeaderKey: String { "Retry-After" }

    public var retryAfterDate: Date? {
        if let retryAfterValue = value(forHeader: Self.kOWSRetryAfterHeaderKey) {
            return Self.parseRetryAfterHeaderValue(retryAfterValue)
        } else {
            return nil
        }
    }

    static func parseRetryAfterHeaderValue(_ rawValue: String?) -> Date? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        if let result = Date.ows_parseFromHTTPDateString(value) {
            return result
        }
        if let result = Date.ows_parseFromISO8601String(value) {
            return result
        }
        func parseWithScanner() -> Date? {
            // We need to use NSScanner instead of -[NSNumber doubleValue] so we can differentiate
            // because the NSNumber method returns 0.0 on a parse failure. NSScanner lets us detect
            // a parse failure.
            let scanner = Scanner(string: value)
            var delay: TimeInterval = 0
            guard scanner.scanDouble(&delay),
                  scanner.isAtEnd else {
                      // Only return the delay if we've made it to the end.
                      // Helps to prevent things like: 8/11/1994 being interpreted as delay: 8.
                      return nil
                  }
            return Date(timeIntervalSinceNow: max(0, delay))
        }
        if let result = parseWithScanner() {
            return result
        }
        if !CurrentAppContext().isRunningTests {
            owsFailDebug("Failed to parse retry-after string: \(String(describing: rawValue))")
        }
        return Date(timeIntervalSinceNow: Self.kOWSFallbackRetryAfter)
    }
}
