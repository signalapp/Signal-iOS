//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CFNetwork
import LibSignalClient

/// This extension sacrifices Dictionary performance in order to ignore http
/// header case and should not be generally used. Since the number of http
/// headers is generally small, this is an acceptable tradeoff for this use case
/// but may not be for other use cases.
private extension Dictionary where Key == String {
    subscript(header header: String) -> Value? {
        get {
            if let key = keys.first(where: { $0.caseInsensitiveCompare(header) == .orderedSame }) {
                return self[key]
            }
            return nil
        }
        set {
            if let key = keys.first(where: { $0.caseInsensitiveCompare(header) == .orderedSame }) {
                self[key] = newValue
            } else {
                self[header] = newValue
            }
        }
    }
}

public class HTTPUtils {
    #if TESTABLE_BUILD
    public static func logCurl(for request: URLRequest) {
        guard let httpMethod = request.httpMethod else {
            Logger.debug("attempted to log curl on a request with no http method")
            return
        }
        guard let url = request.url else {
            Logger.debug("attempted to log curl on a request with no url")
            return
        }
        logCurl(
            url: url,
            method: httpMethod,
            headers: HttpHeaders(httpHeaders: request.allHTTPHeaderFields, overwriteOnConflict: true),
            body: request.httpBody
        )
    }

    public static func logCurl(for request: TSRequest) {
        logCurl(
            url: request.url,
            method: request.method,
            headers: request.headers,
            body: {
                switch request.body {
                case .data(let bodyData):
                    return bodyData
                case .parameters(_):
                    return nil
                }
            }()
        )
    }

    public static func logCurl(url: URL, method httpMethod: String, headers: HttpHeaders, body httpBody: Data?) {
        var curlComponents = ["curl", "-v", "-k", "-X", httpMethod]

        for (header, headerValue) in headers.headers {
            // We don't yet support escaping header values.
            // If these asserts trip, we'll need to add that.
            owsAssertDebug(!header.contains("'"))
            owsAssertDebug(!headerValue.contains("'"))

            curlComponents.append("-H")
            curlComponents.append("'\(header): \(headerValue)'")
        }

        if let httpBody, !httpBody.isEmpty {
            let contentType = headers["Content-Type"]
            switch contentType {
            case MimeType.applicationJson.rawValue:
                guard let jsonBody = String(data: httpBody, encoding: .utf8) else {
                    Logger.debug("data attached to request as json was not utf8 encoded")
                    return
                }
                // We don't yet support escaping JSON.
                // If these asserts trip, we'll need to add that.
                owsAssertDebug(!jsonBody.contains("'"))
                curlComponents.append("--data-ascii")
                curlComponents.append("'\(jsonBody)'")
            case MimeType.applicationXProtobuf.rawValue, "application/x-www-form-urlencoded", "application/vnd.signal-messenger.mrm":
                let filename = "\(UUID().uuidString).tmp"
                var echoBytes = ""
                for byte in httpBody {
                    echoBytes.append(String(format: "\\\\x%02X", byte))
                }
                let echoCommand = "echo -n -e \(echoBytes) > \(filename)"

                Logger.verbose("curl for request: \(echoCommand)")
                curlComponents.append("--data-binary")
                curlComponents.append("@\(filename)")
            default:
                owsFailDebug("Unknown content type: \(contentType ?? "<nil>")")
            }

        }
        // TODO: Add support for cookies.
        curlComponents.append("\"\(url.absoluteString)\"")
        let curlCommand = curlComponents.joined(separator: " ")
        Logger.verbose("curl for request: \(curlCommand)")
    }
    #endif

    public static func preprocessMainServiceHTTPError(
        requestUrl: URL,
        responseStatus: Int,
        responseHeaders: HttpHeaders,
        responseData: Data?
    ) async -> OWSHTTPError {
        let httpError = HTTPUtils.buildServiceError(
            requestUrl: requestUrl,
            responseStatus: responseStatus,
            responseHeaders: responseHeaders,
            responseData: responseData
        )

        await applyHTTPError(httpError)

        return httpError
    }

    // This DRYs up handling of main service errors so that
    // REST and websocket errors are handled in the same way.
    public static func applyHTTPError(_ httpError: OWSHTTPError) async {
        if httpError.isNetworkFailureImpl || httpError.isTimeoutImpl {
            OutageDetection.shared.reportConnectionFailure()
        }

        if httpError.responseStatusCode == AppExpiry.appExpiredStatusCode {
            let appExpiry = DependenciesBridge.shared.appExpiry
            let db = DependenciesBridge.shared.db
            await appExpiry.setHasAppExpiredAtCurrentVersion(db: db)
        }
    }

    public static func retryDelayNanoSeconds(_ response: HTTPResponse, defaultRetryTime: TimeInterval = 15) -> UInt64 {
        let retryAfter: TimeInterval
        if
            let retryAfterHeader = response.headers["retry-after"],
            let retryAfterTime = TimeInterval(retryAfterHeader)
        {
            retryAfter = retryAfterTime
        } else {
            retryAfter = defaultRetryTime
        }
        return UInt64(retryAfter * 1000) * NSEC_PER_MSEC
    }

    private static func buildServiceError(
        requestUrl: URL,
        responseStatus: Int,
        responseHeaders: HttpHeaders,
        responseData: Data?
    ) -> OWSHTTPError {

        let retryAfterDate: Date? = responseHeaders.retryAfterDate
        func buildServiceResponseError(
            localizedDescription: String? = nil,
            localizedRecoverySuggestion: String? = nil
        ) -> OWSHTTPError {
            .forServiceResponse(
                requestUrl: requestUrl,
                responseStatus: responseStatus,
                responseHeaders: responseHeaders,
                responseError: nil,
                responseData: responseData,
                customRetryAfterDate: retryAfterDate,
                customLocalizedDescription: localizedDescription,
                customLocalizedRecoverySuggestion: localizedRecoverySuggestion
            )
        }

        switch responseStatus {
        case 0:
            return .networkFailure(.invalidResponseStatus)
        case 429:
            let description = OWSLocalizedString("REGISTER_RATE_LIMITING_ERROR", comment: "")
            let recoverySuggestion = OWSLocalizedString("REGISTER_RATE_LIMITING_BODY", comment: "")
            return buildServiceResponseError(
                localizedDescription: description,
                localizedRecoverySuggestion: recoverySuggestion
            )
        default:
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

    var httpResponseHeaders: HttpHeaders? {
        guard let error = self as? OWSHTTPError else {
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

    /// Does this error represent a transient networking issue?
    ///
    /// a.k.a. "the internet gave up" (see also `isTimeout`)
    var isNetworkFailure: Bool {
        return HTTPUtils.isNetworkFailureError(self)
    }

    /// Does this error represent a self-induced timeout?
    ///
    /// a.k.a. "we gave up" (see also `isNetworkFailure`)
    var isTimeout: Bool {
        return HTTPUtils.isTimeoutError(self)
    }

    var isNetworkFailureOrTimeout: Bool {
        return isNetworkFailure || isTimeout
    }

    var is5xxServiceResponse: Bool {
        switch self as? OWSHTTPError {
        case .serviceResponse(let serviceResponse):
            return serviceResponse.is5xx
        case nil, .invalidAppState, .invalidRequest, .wrappedFailure, .networkFailure:
            return false
        }
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

    static func isNetworkFailureError(_ error: Error) -> Bool {
        switch error {
        case URLError.cannotConnectToHost: return true
        case URLError.networkConnectionLost: return true
        case URLError.dnsLookupFailed: return true
        case URLError.notConnectedToInternet: return true
        case URLError.secureConnectionFailed: return true
        case URLError.cannotLoadFromNetwork: return true
        case URLError.cannotFindHost: return true
        case URLError.badURL: return true
        case POSIXError.EPROTO: return true
        case let httpError as OWSHTTPError: return httpError.isNetworkFailureImpl
        case SignalError.connectionFailed: return true
        case StorageService.StorageError.networkError: return true
        case Upload.Error.networkError: return true
        default: return false
        }
    }

    static func isTimeoutError(_ error: Error) -> Bool {
        switch error {
        case URLError.timedOut: return true
        case let httpError as OWSHTTPError: return httpError.isTimeoutImpl
        case GroupsV2Error.timeout: return true
        case PaymentsError.timeout: return true
        case SignalError.connectionTimeoutError: return true
        case Upload.Error.networkTimeout: return true
        default: return false
        }
    }
}

// MARK: -

@inlinable
public func owsFailDebugUnlessNetworkFailure(_ error: Error,
                                             file: String = #file,
                                             function: String = #function,
                                             line: Int = #line) {
    if error.isNetworkFailureOrTimeout {
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
    if error.isNetworkFailureOrTimeout {
        // Log but otherwise ignore network failures.
        Logger.warn("Error: \(error)", file: file, function: function, line: line)
    } else {
        owsFailBeta("Error: \(error)", file: file, function: function, line: line)
    }
}

// MARK: -

extension HttpHeaders {

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
            guard let delay = scanner.scanDouble(),
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
