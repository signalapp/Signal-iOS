import PromiseKit

/// Base class for `LokiSnodeProxy` and `LokiFileServerProxy`.
public class LokiHTTPClient {

    internal lazy var httpSession: AFHTTPSessionManager = {
        let result = AFHTTPSessionManager(sessionConfiguration: .ephemeral)
        let securityPolicy = AFSecurityPolicy.default()
        securityPolicy.allowInvalidCertificates = true
        securityPolicy.validatesDomainName = false
        result.securityPolicy = securityPolicy
        result.responseSerializer = AFHTTPResponseSerializer()
        result.completionQueue = DispatchQueue.global()
        return result
    }()

    internal func perform(_ request: TSRequest, withCompletionQueue queue: DispatchQueue = DispatchQueue.main) -> LokiAPI.RawResponsePromise {
        return TSNetworkManager.shared().perform(request, withCompletionQueue: queue).map { $0.responseObject }.recover { error -> LokiAPI.RawResponsePromise in
            throw HTTPError.from(error: error) ?? error
        }
    }

    internal func getCanonicalHeaders(for request: NSURLRequest) -> [String:Any] {
        guard let headers = request.allHTTPHeaderFields else { return [:] }
        return headers.mapValues { value in
            switch value.lowercased() {
            case "true": return true
            case "false": return false
            default: return value
            }
        }
    }
}

// MARK: - HTTP Error

public extension LokiHTTPClient {

    public enum HTTPError : LocalizedError {
        case networkError(code: Int, response: Any?, underlyingError: Error?)

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

        public var errorDescription: String? {
           switch self {
           case .networkError(let code, let body, let underlyingError): return underlyingError?.localizedDescription ?? "HTTP request failed with status code: \(code), message: \(body ?? "nil")."
           }
        }

        internal var statusCode: Int {
            switch self {
            case .networkError(let code, _, _): return code
            }
        }

        internal var isNetworkError: Bool {
            switch self {
            case .networkError(_, _, let underlyingError): return underlyingError != nil && IsNSErrorNetworkFailure(underlyingError)
            }
        }
    }
}
