//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

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
        let error = HTTPUtils.buildServiceError(request: request,
                                                requestUrl: requestUrl,
                                                responseStatus: responseStatus,
                                                responseHeaders: responseHeaders,
                                                responseError: responseError,
                                                responseData: responseData)

        if error.isNetworkConnectivityError {
            Self.outageDetection.reportConnectionFailure()
        }

        #if TESTABLE_BUILD
        HTTPUtils.logCurl(for: request as URLRequest)
        #endif

        if error.responseStatusCode == AppExpiry.appExpiredStatusCode {
            appExpiry.setHasAppExpiredAtCurrentVersion()
        }

        return error
    }

    private static func buildServiceError(request: TSRequest,
                                          requestUrl: URL,
                                          responseStatus: Int,
                                          responseHeaders: OWSHttpHeaders,
                                          responseError: Error?,
                                          responseData: Data?) -> OWSHTTPError {

        var errorDescription = "URL: \(requestUrl.absoluteString), status: \(responseStatus)"
        if let responseError = responseError {
            errorDescription += ", error: \(responseError)"
        }
        let retryAfterDate: Date? = {
            guard let error = responseError else {
                return nil
            }
            return (error as NSError).afRetryAfterDate()
        }()
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
            Logger.warn("The network request failed because of a connectivity error: \(requestUrl.absoluteString)")
            let error = OWSHTTPError.networkFailure(requestUrl: requestUrl)
            return error
        case 400:
            Logger.warn("The request contains an invalid parameter: \(errorDescription)")
            return buildServiceResponseError()
        case 401:
            Logger.warn("The server returned an error about the authorization header: \(errorDescription)")
            deregisterAfterAuthErrorIfNecessary(request: request,
                                                requestUrl: requestUrl,
                                                statusCode: responseStatus)
            return buildServiceResponseError()
        case 402:
            return buildServiceResponseError()
        case 403:
            Logger.warn("The server returned an authentication failure: \(errorDescription)")
            deregisterAfterAuthErrorIfNecessary(request: request,
                                                requestUrl: requestUrl,
                                                statusCode: responseStatus)
            return buildServiceResponseError()
        case 404:
            Logger.warn("The requested resource could not be found: \(errorDescription)")
            return buildServiceResponseError()
        case 411:
            Logger.info("Multi-device pairing: \(responseStatus), \(errorDescription)")
            let description = NSLocalizedString("MULTIDEVICE_PAIRING_MAX_DESC",
                                                comment: "alert title: cannot link - reached max linked devices")
            let recoverySuggestion = NSLocalizedString("MULTIDEVICE_PAIRING_MAX_RECOVERY",
                                                       comment: "alert body: cannot link - reached max linked devices")
            let error = buildServiceResponseError(description: description,
                                                  recoverySuggestion: recoverySuggestion)
            return error
        case 413:
            Logger.warn("Rate limit exceeded: \(requestUrl.absoluteString)")
            let description = NSLocalizedString("REGISTER_RATE_LIMITING_ERROR", comment: "")
            let recoverySuggestion = NSLocalizedString("REGISTER_RATE_LIMITING_BODY", comment: "")
            let error = buildServiceResponseError(description: description,
                                                  recoverySuggestion: recoverySuggestion)
            return error
        case 417:
            // TODO: Is this response code obsolete?
            Logger.warn("The number is already registered on a relay. Please unregister there first: \(requestUrl.absoluteString)")
            let description = NSLocalizedString("REGISTRATION_ERROR", comment: "")
            let recoverySuggestion = NSLocalizedString("RELAY_REGISTERED_ERROR_RECOVERY", comment: "")
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

    private static func deregisterAfterAuthErrorIfNecessary(request: TSRequest,
                                                            requestUrl: URL,
                                                            statusCode: Int) {
        let requestHeaders: [String: String] = request.allHTTPHeaderFields ?? [:]
        Logger.verbose("Invalid auth: \(requestHeaders)")

        // We only want to de-register for:
        //
        // * Auth errors...
        // * ...received from Signal service...
        // * ...that used standard authorization.
        //
        // * We don't want want to deregister for:
        //
        // * CDS requests.
        // * Requests using UD auth.
        // * etc.
        //
        // TODO: Will this work with censorship circumvention?
        if requestUrl.absoluteString.hasPrefix(TSConstants.mainServiceURL),
           request.shouldHaveAuthorizationHeaders {
            DispatchQueue.main.async {
                if Self.tsAccountManager.isRegisteredAndReady {
                    Self.tsAccountManager.setIsDeregistered(true)
                } else {
                    Logger.warn("Ignoring auth failure not registered and ready: \(requestUrl.absoluteString).")
                }
            }
        } else {
            Logger.warn("Ignoring \(statusCode) for URL: \(requestUrl.absoluteString)")
        }
    }
}

// MARK: -

// Temporary obj-c wrapper for OWSHTTPError until
// OWSWebSocket, etc. have been ported to Swift.
@objc
public class OWSHTTPErrorWrapper: NSObject {
    public let error: OWSHTTPError
    @objc
    public var asNSError: NSError { error as NSError }

    public init(error: OWSHTTPError) {
        self.error = error
    }

    @objc
    public var asConnectionFailureError: OWSHTTPErrorWrapper {
        let newError = OWSHTTPError.forServiceResponse(requestUrl: error.requestUrl,
                                                       responseStatus: error.responseStatusCode,
                                                       responseHeaders: error.responseHeaders ?? OWSHttpHeaders(),
                                                       responseError: error.responseError,
                                                       responseData: error.responseBodyData,
                                                       customRetryAfterDate: error.customRetryAfterDate,
                                                       customLocalizedDescription: NSLocalizedString("ERROR_DESCRIPTION_NO_INTERNET",
                                                                                                     comment: "Generic error used whenever Signal can't contact the server"),
                                                       customLocalizedRecoverySuggestion: NSLocalizedString("NETWORK_ERROR_RECOVERY",
                                                                                                            comment: ""))
        return OWSHTTPErrorWrapper(error: newError)
    }
}

// MARK: -

@inlinable
public func owsFailDebugUnlessNetworkFailure(_ error: Error,
                                             file: String = #file,
                                             function: String = #function,
                                             line: Int = #line) {
    if IsNetworkConnectivityFailure(error) {
        // Log but otherwise ignore network failures.
        Logger.warn("Error: \(error)", file: file, function: function, line: line)
    } else {
        owsFailDebug("Error: \(error)", file: file, function: function, line: line)
    }
}
