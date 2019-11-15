//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

enum NetworkManagerError: Error {
    /// Wraps TSNetworkManager failure callback params in a single throwable error
    case taskError(task: URLSessionDataTask, underlyingError: Error)
}

extension NetworkManagerError {
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
}

extension TSNetworkManager {
    public typealias NetworkManagerResult = (task: URLSessionDataTask, responseObject: Any?)

    public func perform(_ request: TSRequest, withCompletionQueue queue: DispatchQueue = DispatchQueue.main) -> Promise<NetworkManagerResult> {
        return makePromise(request: request, queue: queue)
    }
    
    public func makePromise(request: TSRequest, queue: DispatchQueue = DispatchQueue.main) -> Promise<NetworkManagerResult> {
        let (promise, resolver) = Promise<NetworkManagerResult>.pending()

        self.makeRequest(request,
                         completionQueue: queue,
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
