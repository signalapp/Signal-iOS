//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// A class used for making HTTP requests against the main service.
@objc
public class NetworkManager: NSObject {
    private let restNetworkManager = RESTNetworkManager()

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // This method can be called from any thread.
    public func makePromise(request: TSRequest,
                            remainingRetryCount: Int = 0) -> Promise<HTTPResponse> {
        firstly {
            FeatureFlags.deprecateREST
                ? websocketRequestPromise(request: request)
                : restRequestPromise(request: request)
        }.recover(on: .global()) { error -> Promise<HTTPResponse> in
            if error.isRetryable,
               remainingRetryCount > 0 {
                // TODO: Backoff?
                return self.makePromise(request: request,
                                        remainingRetryCount: remainingRetryCount - 1)
            } else {
                throw error
            }
        }
    }

    private func isRESTOnlyEndpoint(request: TSRequest) -> Bool {
        guard let url = request.url else {
            owsFailDebug("Missing url.")
            return true
        }
        guard let urlComponents = URLComponents(string: url.absoluteString) else {
            owsFailDebug("Missing urlComponents.")
            return true
        }
        let path: String = urlComponents.path
        let missingEndpoints = [
            "/v1/payments/auth"
        ]
        return missingEndpoints.contains(path)
    }

    private func restRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        restNetworkManager.makePromise(request: request)
    }

    private func websocketRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        return Self.socketManager.makeRequestPromise(request: request)
    }
}

// MARK: -

#if TESTABLE_BUILD

@objc
public class OWSFakeNetworkManager: NetworkManager {

    public override func makePromise(request: TSRequest, remainingRetryCount: Int = 0) -> Promise<HTTPResponse> {
        Logger.info("Ignoring request: \(request)")
        // Never resolve.
        let (promise, _) = Promise<HTTPResponse>.pending()
        return promise
    }
}

#endif

// MARK: -

@objc
public extension NetworkManager {
    // NOTE: This function should only be called from IsNetworkConnectivityFailure().
    static func isSwiftNetworkConnectivityError(_ error: Error?) -> Bool {
        guard let error = error else {
            return false
        }
        switch error {
        case let httpError as OWSHTTPError:
            return httpError.isNetworkConnectivityError
        case GroupsV2Error.timeout:
            return true
        case let contactDiscoveryError as ContactDiscoveryError:
            return contactDiscoveryError.kind == .timeout
        case PaymentsError.timeout:
            return true
        default:
            return false
        }
    }

    // NOTE: This function should only be called from HTTPStatusCodeForError().
    static func swiftHTTPStatusCodeForError(_ error: Error?) -> NSNumber? {
        if let httpError = error as? OWSHTTPError {
            let statusCode = httpError.responseStatusCode
            guard statusCode > 0 else {
                return nil
            }
            return NSNumber(value: statusCode)
        }
        return nil
    }

    // NOTE: This function should only be called from HTTPRetryAfterDate().
    static func swiftHTTPRetryAfterDateForError(_ error: Error?) -> Date? {
        if let httpError = error as? OWSHTTPError {
            if let retryAfterDate = httpError.customRetryAfterDate {
                return retryAfterDate
            }
            if let retryAfterDate = httpError.responseHeaders?.retryAfterDate {
                return retryAfterDate
            }
            if let responseError = httpError.responseError {
                return swiftHTTPRetryAfterDateForError(responseError)
            }
        }
        return nil
    }

    // NOTE: This function should only be called from HTTPResponseDataForError().
    static func swiftHTTPResponseDataForError(_ error: Error?) -> Data? {
        guard let error = error else {
            return nil
        }
        if let responseData = (error as NSError).userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] as? Data {
            return responseData
        }
        switch error {
        case let httpError as OWSHTTPError:
            if let responseData = httpError.responseBodyData {
                return responseData
            }
            if let responseError = httpError.responseError {
                return swiftHTTPResponseDataForError(responseError)
            }
            return nil
        default:
            return nil
        }
    }
}
