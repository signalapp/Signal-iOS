//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum NetworkManagerError: Error {
    /// Wraps TSNetworkManager failure callback params in a single throwable error
    case taskError(task: URLSessionDataTask, underlyingError: Error)
}

public extension NetworkManagerError {
    var isNetworkError: Bool {
        switch self {
        case .taskError(_, let underlyingError):
            return IsNSErrorNetworkFailure(underlyingError)
        }
    }

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

extension NetworkManagerError: CustomNSError {
    public var errorCode: Int {
        return statusCode
    }

    public var errorUserInfo: [String: Any] {
        return [NSUnderlyingErrorKey: underlyingError]
    }
}

public extension TSNetworkManager {
    typealias Response = (task: URLSessionDataTask, responseObject: Any?)

    func makePromise(request: TSRequest) -> Promise<Response> {
        let (promise, resolver) = Promise<Response>.pending()

        self.makeRequest(request,
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
