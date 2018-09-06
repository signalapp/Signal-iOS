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
    func makePromise(request: TSRequest) -> Promise<(task: URLSessionDataTask, responseObject: Any?)> {
        let (promise, fulfill, reject) = Promise<(task: URLSessionDataTask, responseObject: Any?)>.pending()

        self.makeRequest(request,
                         success: { task, responseObject in
                            fulfill((task: task, responseObject: responseObject))
        },
                         failure: { task, error in
                            let nmError = NetworkManagerError.taskError(task: task, underlyingError: error)
                            let nsError: NSError = nmError as NSError
                            nsError.isRetryable = (error as NSError).isRetryable
                            reject(nsError)
        })

        return promise
    }
}
