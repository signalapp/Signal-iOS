import PromiseKit

internal class LokiHTTPClient {
    
    internal enum HTTPError: LocalizedError {
        case networkError(code: Int, response: Any?, underlyingError: Error?)
        
        public var errorDescription: String? {
           switch self {
           case .networkError(let code, let body, let underlingError): return underlingError?.localizedDescription ?? "Failed HTTP request with status code: \(code), message: \(body ?? "")."
           }
        }
    }
    
    internal func perform(_ request: TSRequest, withCompletionQueue queue: DispatchQueue = DispatchQueue.main) -> LokiAPI.RawResponsePromise {
        return TSNetworkManager.shared().perform(request, withCompletionQueue: queue).map { $0.responseObject }.recover { error -> LokiAPI.RawResponsePromise in
            throw HTTPError.from(error: error) ?? error
        }
    }
}

internal extension LokiHTTPClient.HTTPError {
    
    internal static func from(error: Error) -> LokiHTTPClient.HTTPError? {
        if let error = error as? NetworkManagerError {
            if case NetworkManagerError.taskError(_, let underlyingError) = error, let nsError = underlyingError as? NSError {
                var response = nsError.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey]
                // Deserialize response if needed
                if let data = response as? Data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON {
                    response = json
                }
                return LokiHTTPClient.HTTPError.networkError(code: error.statusCode, response: response, underlyingError: underlyingError)
            }
            return LokiHTTPClient.HTTPError.networkError(code: error.statusCode, response: nil, underlyingError: error)
        }
        return nil
    }
    
    internal var isNetworkError: Bool {
        switch self {
        case .networkError(_, _, let underlyingError): return underlyingError != nil && IsNSErrorNetworkFailure(underlyingError)
        }
    }

    internal var statusCode: Int {
        switch self {
        case .networkError(let code, _, _): return code
        }
    }
}
