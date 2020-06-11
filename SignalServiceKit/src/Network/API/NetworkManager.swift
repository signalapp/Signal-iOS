//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum NetworkManagerError: Error {
    /// Wraps TSNetworkManager failure callback params in a single throwable error
    case taskError(task: URLSessionDataTask, underlyingError: Error)
}

fileprivate extension NetworkManagerError {
    // NOTE: This function should only be called from TSNetworkManager.isSwiftNetworkConnectivityError.
    var isNetworkConnectivityError: Bool {
        switch self {
        case .taskError(_, let underlyingError):
            return IsNetworkConnectivityFailure(underlyingError)
        }
    }

    // NOTE: This function should only be called from TSNetworkManager.swiftStatusCodeForError.
    var statusCode: Int {
        switch self {
        case .taskError(let task, _):
            return task.statusCode()
        }
    }

    var underlyingError: Error {
        switch self {
        case .taskError(_, let underlyingError):
            return underlyingError
        }
    }
}

// MARK: -

extension NetworkManagerError: CustomNSError {
    public var errorCode: Int {
        return statusCode
    }

    public var errorUserInfo: [String: Any] {
        return [NSUnderlyingErrorKey: underlyingError]
    }
}

// MARK: -

public extension TSNetworkManager {
    typealias Response = (task: URLSessionDataTask, responseObject: Any?)

    func makePromise(request: TSRequest) -> Promise<Response> {
        let (promise, resolver) = Promise<Response>.pending()

        self.makeRequest(request,
                         completionQueue: DispatchQueue.global(),
                         success: { task, responseObject in
                            resolver.fulfill((task: task, responseObject: responseObject))
        },
                         failure: { task, error in
                            let nmError = NetworkManagerError.taskError(task: task, underlyingError: error)
                            let nsError: NSError = nmError as NSError
                            nsError.isRetryable = (error as NSError).isRetryable
                            resolver.reject(nsError)
        })

        return promise
    }
}

// MARK: -

@objc
public extension TSNetworkManager {
    // NOTE: This function should only be called from IsNetworkConnectivityFailure().
    static func isSwiftNetworkConnectivityError(_ error: Error?) -> Bool {
        guard let error = error else {
            return false
        }
        switch error {
        case let networkManagerError as NetworkManagerError:
            if networkManagerError.isNetworkConnectivityError {
                return true
            }
            return false
        case RequestMakerError.websocketRequestError(_, _, let underlyingError):
            return IsNetworkConnectivityFailure(underlyingError)
        default:
            return false
        }
    }

    // NOTE: This function should only be called from HTTPStatusCodeForError().
    static func swiftHTTPStatusCodeForError(_ error: Error?) -> NSNumber? {
        guard let error = error else {
            return nil
        }
        switch error {
        case let networkManagerError as NetworkManagerError:
            guard networkManagerError.statusCode > 0 else {
                return nil
            }
            return NSNumber(value: networkManagerError.statusCode)
        case RequestMakerError.websocketRequestError(let statusCode, _, _):
            guard statusCode > 0 else {
                return nil
            }
            return NSNumber(value: statusCode)
        default:
            return nil
        }
    }
}

// MARK: -

public extension Error {
    var httpStatusCode: Int? {
        HTTPStatusCodeForError(self)?.intValue
    }
}
