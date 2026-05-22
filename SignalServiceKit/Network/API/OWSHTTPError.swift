//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum OWSHTTPError: Error, CustomDebugStringConvertible, IsRetryableProvider, UserErrorDescriptionProvider {
    case wrappedFailure(any Error)
    /// Request failed without a response from the service.
    case networkFailure(NetworkErrorType)
    /// Request failed with a response from the service.
    case serviceResponse(ServiceResponse)

    // MARK: -

    public enum NetworkErrorType: CustomDebugStringConvertible {
        case invalidResponseStatus
        case unknownNetworkFailure
        case genericTimeout
        case genericFailure
        case wrappedFailure(any Error)

        public var isTimeoutImpl: Bool {
            switch self {
            case .invalidResponseStatus, .unknownNetworkFailure, .genericFailure:
                return false
            case .genericTimeout:
                return true
            case .wrappedFailure:
                return true
            }
        }

        public var debugDescription: String {
            switch self {
            case .invalidResponseStatus: return "Invalid response status"
            case .unknownNetworkFailure: return "Unknown network failure"
            case .genericTimeout: return "Generic timeout"
            case .genericFailure: return "Generic failure"
            case .wrappedFailure(let wrappedError):
                return "networkFailureOrTimeout(\(wrappedError.localizedDescription))"
            }
        }
    }

    public struct ServiceResponse {
        let requestUrl: URL
        let responseStatus: Int
        let responseHeaders: HttpHeaders
        let responseData: Data?

        var is5xx: Bool {
            switch responseStatus {
            case 500..<600: true
            default: false
            }
        }
    }

    // MARK: - NSError bridging

    public static var errorDomain: String {
        return "OWSHTTPError"
    }

    public var errorUserInfo: [String: Any] {
        var result = [String: Any]()
        result[NSLocalizedDescriptionKey] = localizedDescription
        return result
    }

    // MARK: -

    public var localizedDescription: String {
        switch self {
        case .networkFailure:
            OWSLocalizedString(
                "ERROR_DESCRIPTION_REQUEST_FAILED",
                comment: "Error indicating that a socket request failed.",
            )
        case .serviceResponse(let serviceResponse) where serviceResponse.responseStatus == 429:
            OWSLocalizedString(
                "REGISTER_RATE_LIMITING_ERROR",
                comment: "",
            )
        case .wrappedFailure, .serviceResponse:
            OWSLocalizedString(
                "ERROR_DESCRIPTION_RESPONSE_FAILED",
                comment: "Error indicating that a socket response failed.",
            )
        }
    }

    public var debugDescription: String {
        switch self {
        case .wrappedFailure(let error):
            return "wrappedFailure(\(error))"
        case .networkFailure:
            return "networkFailure"
        case .serviceResponse(let serviceResponse):
            return "HTTP \(serviceResponse.responseStatus); \(serviceResponse.responseHeaders))"
        }
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool {
        switch self {
        case .wrappedFailure:
            return true
        case .networkFailure:
            return true
        case .serviceResponse(let serviceResponse):
            return serviceResponse.is5xx
        }
    }

    // MARK: -

    public var responseStatusCode: Int {
        switch self {
        case .wrappedFailure, .networkFailure:
            return 0
        case .serviceResponse(let serviceResponse):
            return Int(serviceResponse.responseStatus)
        }
    }

    public var responseHeaders: HttpHeaders? {
        switch self {
        case .wrappedFailure, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseHeaders
        }
    }

    public var responseBodyData: Data? {
        switch self {
        case .wrappedFailure, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseData
        }
    }

    public var isNetworkFailureImpl: Bool {
        switch self {
        case .wrappedFailure:
            return false
        case .networkFailure(let wrappedError):
            switch wrappedError {
            case .invalidResponseStatus, .unknownNetworkFailure, .genericFailure:
                return true
            case .genericTimeout:
                return false
            case .wrappedFailure(let wrappedError):
                return wrappedError.isNetworkFailure
            }
        case .serviceResponse:
            return false
        }
    }

    public var isTimeoutImpl: Bool {
        switch self {
        case .wrappedFailure:
            return false
        case .networkFailure(let wrappedError):
            switch wrappedError {
            case .invalidResponseStatus, .unknownNetworkFailure, .genericFailure:
                return false
            case .genericTimeout:
                return true
            case .wrappedFailure(let wrappedError):
                return wrappedError.isTimeout
            }
        case .serviceResponse:
            return false
        }
    }
}
