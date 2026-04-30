//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CFNetwork
import Foundation
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
    public static func preprocessMainServiceHTTPError(
        requestUrl: URL,
        responseStatus: Int,
        responseHeaders: HttpHeaders,
        responseData: Data?,
    ) async -> OWSHTTPError {
        let httpError: OWSHTTPError
        if responseStatus == 0 {
            httpError = .networkFailure(.invalidResponseStatus)
        } else {
            httpError = .serviceResponse(.init(
                requestUrl: requestUrl,
                responseStatus: responseStatus,
                responseHeaders: responseHeaders,
                responseData: responseData,
            ))
        }

        await applyHTTPError(httpError)
        return httpError
    }

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
        return (response.headers.retryAfterTimeInterval ?? defaultRetryTime).clampedNanoseconds
    }
}

// MARK: -

public extension Error {
    var httpRetryAfterDate: Date? {
        guard let httpError = self as? OWSHTTPError else {
            return nil
        }

        return httpError.responseHeaders?.retryAfterDate
    }

    var httpResponseData: Data? {
        guard let httpError = self as? OWSHTTPError else {
            return nil
        }

        return httpError.responseBodyData
    }

    var httpStatusCode: Int? {
        guard
            let httpError = self as? OWSHTTPError,
            httpError.responseStatusCode > 0
        else {
            return nil
        }

        return httpError.responseStatusCode
    }

    var httpResponseHeaders: HttpHeaders? {
        guard let error = self as? OWSHTTPError else {
            return nil
        }
        return error.responseHeaders
    }

    /// Does this error represent a transient networking issue?
    ///
    /// a.k.a. "the internet gave up" (see also `isTimeout`)
    var isNetworkFailure: Bool {
        switch self as any Error {
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
        case SignalError.chatServiceInactive: return true
        case SignalError.connectionFailed: return true
        case SignalError.connectionInvalidated: return true
        case SignalError.ioError: return true
        case SignalError.possibleCaptiveNetwork: return true
        case SignalError.webSocketError: return true
        case Upload.Error.networkError: return true
        default: return false
        }
    }

    /// Does this error represent a self-induced timeout?
    ///
    /// a.k.a. "we gave up" (see also `isNetworkFailure`)
    var isTimeout: Bool {
        switch self as any Error {
        case URLError.timedOut: return true
        case let httpError as OWSHTTPError: return httpError.isTimeoutImpl
        case GroupsV2Error.timeout: return true
        case PaymentsError.timeout: return true
        case SignalError.connectionTimeoutError: return true
        case SignalError.requestTimeoutError: return true
        case Upload.Error.networkTimeout: return true
        default: return false
        }
    }

    var isNetworkFailureOrTimeout: Bool {
        return isNetworkFailure || isTimeout
    }

    var is5xxServiceResponse: Bool {
        switch self as? OWSHTTPError {
        case .serviceResponse(let serviceResponse):
            return serviceResponse.is5xx
        case nil, .wrappedFailure, .networkFailure:
            return false
        }
    }
}

// MARK: -

@inlinable
public func owsFailDebugUnlessNetworkFailure(
    _ error: Error,
    file: String = #file,
    function: String = #function,
    line: Int = #line,
) {
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
    line: Int = #line,
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

    public var retryAfterTimeInterval: TimeInterval? {
        return retryAfterStringValue.flatMap(TimeInterval.init(_:))
    }

    public var retryAfterDate: Date? {
        guard let retryAfterStringValue else {
            return nil
        }

        if let date = Date.ows_parseFromHTTPDateString(retryAfterStringValue) {
            return date
        } else if let date = Date.ows_parseFromISO8601String(retryAfterStringValue) {
            return date
        } else if let retryAfterTimeInterval {
            return Date().addingTimeInterval(retryAfterTimeInterval)
        } else {
            owsAssertDebug(
                CurrentAppContext().isRunningTests,
                "Failed to parse retry-after string: \(String(describing: retryAfterStringValue))",
            )
            return nil
        }
    }

    private var retryAfterStringValue: String? {
        return value(forHeader: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}
