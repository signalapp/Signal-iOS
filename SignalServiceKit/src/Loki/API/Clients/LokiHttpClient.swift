import PromiseKit

internal class LokiHttpClient {
    enum HttpError: LocalizedError {
        /// Wraps TSNetworkManager failure callback params in a single throwable error
        case networkError(code: Int, response: Any?, underlyingError: Error?)
        
        public var errorDescription: String? {
           switch self {
           case .networkError(let code, let body, let underlingError): return underlingError?.localizedDescription ?? "Failed network request with code: \(code) \(body ?? "")"
           }
        }
    }
    
    func perform(_ request: TSRequest, withCompletionQueue queue: DispatchQueue = DispatchQueue.main) -> Promise<Any> {
        return TSNetworkManager.shared().perform(request, withCompletionQueue: queue).map { $0.responseObject }.recover { error -> Promise<Any> in
            throw LokiHttpClient.HttpError.from(error: error) ?? error
        }
    }
}

extension LokiHttpClient.HttpError {
    static func from(error: Error) -> LokiHttpClient.HttpError? {
        if let error = error as? NetworkManagerError {
            if case NetworkManagerError.taskError(_, let underlyingError) = error, let nsError = underlyingError as? NSError {
                var response = nsError.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey]
                if let data = response as? Data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON {
                    response = json
                }
                return LokiHttpClient.HttpError.networkError(code: error.statusCode, response: response, underlyingError: underlyingError)
            }
            return LokiHttpClient.HttpError.networkError(code: error.statusCode, response: nil, underlyingError: nil)
        }
        return nil
    }
    
    var isNetworkError: Bool {
        switch self {
        case .networkError(_, _, let underlyingError):
            return underlyingError != nil && IsNSErrorNetworkFailure(underlyingError)
        }
        return false
    }

    var statusCode: Int {
        switch self {
        case .networkError(let code, _, _):
            return code
        }
    }
}
