//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This file contains common interfaces for dealing with
// HTTP request responses, failures and errors in a consistent
// way without concern for whether the request is made via
//
// * REST (e.g. AFNetworking, OWSURLSession, URLSession, etc.).
// * a Websocket (e.g. OWSChatConnection).

// A common protocol for responses from OWSUrlSession, NetworkManager, ChatConnectionManager, etc.
public protocol HTTPResponse {
    var requestUrl: URL { get }
    var responseStatusCode: Int { get }
    var headers: HttpHeaders { get }
    var responseBodyData: Data? { get }
    var responseBodyJson: Any? { get }
    var responseBodyString: String? { get }
}

// MARK: -

public enum OWSHTTPError: Error, CustomDebugStringConvertible, IsRetryableProvider, UserErrorDescriptionProvider {
    case invalidRequest
    case wrappedFailure(any Error)
    /// Request failed without a response from the service.
    case networkFailure(NetworkErrorType)
    /// Request failed with a response from the service.
    case serviceResponse(ServiceResponse)

    // MARK: -

    public enum NetworkErrorType: Error, CustomDebugStringConvertible, IsRetryableProvider {
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

        public var isRetryableProvider: Bool { true }

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
        case .invalidRequest, .networkFailure:
            OWSLocalizedString(
                "ERROR_DESCRIPTION_REQUEST_FAILED",
                comment: "Error indicating that a socket request failed."
            )
        case .serviceResponse(let serviceResponse) where serviceResponse.responseStatus == 429:
            OWSLocalizedString(
                "REGISTER_RATE_LIMITING_ERROR",
                comment: ""
            )
        case .wrappedFailure, .serviceResponse:
            OWSLocalizedString(
                "ERROR_DESCRIPTION_RESPONSE_FAILED",
                comment: "Error indicating that a socket response failed."
            )
        }
    }

    public var debugDescription: String {
        switch self {
        case .invalidRequest:
            return "invalidRequest"
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
        if isNetworkFailureImpl || isTimeoutImpl {
            return true
        }
        switch self {
        case .invalidRequest:
            return false
        case .wrappedFailure:
            return true
        case .networkFailure:
            return true
        case .serviceResponse(let serviceResponse):
            return serviceResponse.is5xx
        }
    }
}

// MARK: -

extension OWSHTTPError {
    public var responseStatusCode: Int {
        switch self {
        case .invalidRequest, .wrappedFailure, .networkFailure:
            return 0
        case .serviceResponse(let serviceResponse):
            return Int(serviceResponse.responseStatus)
        }
    }

    public var responseHeaders: HttpHeaders? {
        switch self {
        case .invalidRequest, .wrappedFailure, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseHeaders
        }
    }

    public var responseBodyData: Data? {
        switch self {
        case .invalidRequest, .wrappedFailure, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseData
        }
    }

    public var isNetworkFailureImpl: Bool {
        switch self {
        case .invalidRequest, .wrappedFailure:
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
        case .serviceResponse(_):
            return false
        }
    }

    public var isTimeoutImpl: Bool {
        switch self {
        case .invalidRequest, .wrappedFailure:
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
        case .serviceResponse(_):
            return false
        }
    }
}

// MARK: -

final public class HTTPResponseImpl {

    public let requestUrl: URL

    public let status: Int

    public let headers: HttpHeaders

    public let bodyData: Data?

    public let stringEncoding: String.Encoding

    private struct JSONValue {
        let json: Any?
    }

    // This property should only be accessed with unfairLock acquired.
    private var jsonValue: JSONValue?

    private static let unfairLock = UnfairLock()

    public init(requestUrl: URL,
                status: Int,
                headers: HttpHeaders,
                bodyData: Data?,
                stringEncoding: String.Encoding = .utf8) {
        self.requestUrl = requestUrl
        self.status = status
        self.headers = headers
        self.bodyData = bodyData
        self.stringEncoding = stringEncoding
    }

    public static func build(requestUrl: URL,
                             httpUrlResponse: HTTPURLResponse,
                             bodyData: Data?) -> HTTPResponse {
        let headers = HttpHeaders(response: httpUrlResponse)
        let stringEncoding: String.Encoding = httpUrlResponse.parseStringEncoding() ?? .utf8
        return HTTPResponseImpl(requestUrl: requestUrl,
                                status: httpUrlResponse.statusCode,
                                headers: headers,
                                bodyData: bodyData,
                                stringEncoding: stringEncoding)
    }

    public var bodyJson: Any? {
        Self.unfairLock.withLock {
            if let jsonValue = self.jsonValue {
                return jsonValue.json
            }
            let jsonValue = Self.parseJSON(data: bodyData)
            self.jsonValue = jsonValue
            return jsonValue.json
        }
    }

    private static func parseJSON(data: Data?) -> JSONValue {
        guard let data = data,
              !data.isEmpty else {
                  return JSONValue(json: nil)
              }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return JSONValue(json: json)
        } catch {
            owsFailDebug("Could not parse JSON: \(error).")
            return JSONValue(json: nil)
        }
    }
}

// MARK: -

extension HTTPResponseImpl: HTTPResponse {
    public var responseStatusCode: Int { Int(status) }
    public var responseBodyData: Data? { bodyData }
    public var responseBodyJson: Any? { bodyJson }
    public var responseBodyString: String? {
        guard let data = bodyData,
              let string = String(data: data, encoding: stringEncoding) else {
                  return nil
              }
        return string
    }
}

// MARK: -

extension HTTPURLResponse {
    fileprivate func parseStringEncoding() -> String.Encoding? {
        guard let encodingName = textEncodingName else {
            return nil
        }
        let encoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
        guard encoding != kCFStringEncodingInvalidId else {
            return nil
        }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}
